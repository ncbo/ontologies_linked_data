# frozen_string_literal: true

module LinkedData
  module Services
    # Propagates the current ontology rank values into the denormalized
    # `ontologyRank` field on every class document in the Solr `term_search`
    # collection. Pure Redis -> Solr propagation: no analytics/UMLS
    # recomputation happens here (that is the job of ncbo_cron's
    # NcboCron::Models::OntologyRank, which calls this immediately after it
    # writes the freshly computed rank to Redis).
    #
    # Rank is read through LinkedData::Models::Ontology.rank (the same source
    # the indexer uses), which derives normalizedScore from the Redis-stored
    # bioportalScore/umlsScore using the configured weights.
    #
    # For each ontology the propagator first asks Solr how many of its docs are
    # NOT already at the current rank (a cheap rows:0 count with a negative range
    # filter). If none are stale it skips the ontology entirely — so even the
    # first run skips ontologies whose Solr rank already matches (e.g. set at
    # index time and never drifted), and a re-run resumes from Solr's actual
    # state. Otherwise it cursor-scans just the stale docs and issues true atomic
    # updates ({ id, ontologyRank: { set: score } }) with no triplestore read.
    #
    # Batches are sent without a commit; a single commit is issued between
    # ontologies (no updates in flight) to keep the transaction log bounded
    # without stalling replica forwarding mid-stream. Every Solr call is retried
    # with backoff so a transient stall/blip is survived rather than aborting.
    #
    # See https://github.com/ncbo/ncbo_cron/issues/132
    class RankSolrPropagator
      DEFAULT_BATCH_SIZE = 2_500
      PROGRESS_EVERY = 50_000   # log per-ontology progress every N docs
      MAX_RETRIES = 5
      RETRY_BASE_SLEEP = 5      # seconds; exponential backoff: 5, 10, 20, 40, 80
      # Half-width of the match band. normalizedScore is rounded to 3 dp, so a
      # +/-0.0005 band uniquely identifies a stored pfloat value despite float
      # representation.
      SCORE_TOLERANCE = 0.0005

      def initialize(logger: nil, batch_size: nil)
        @logger = logger || Logger.new($stdout)
        @batch_size = (batch_size || ENV['RANK_SOLR_BATCH_SIZE'] || DEFAULT_BATCH_SIZE).to_i
        @retry_count = 0
      end

      # Writes each ontology's normalizedScore onto its stale term_search docs,
      # skipping ontologies already at the current rank. Returns the number of
      # ontologies that needed an update.
      def propagate(rank_map = nil)
        rank_map ||= LinkedData::Models::Ontology.rank

        if rank_map.nil? || rank_map.empty?
          @logger.warn('RankSolrPropagator: empty rank map; nothing to propagate')
          return 0
        end

        total_onts = rank_map.size
        updated = 0
        skipped = 0
        @retry_count = 0

        rank_map.each_with_index do |(acronym, rank_info), i|
          score = rank_info[:normalizedScore].to_f
          log("[#{i + 1}/#{total_onts}] #{acronym} rank=#{score}")
          count = update_ontology_rank(acronym, score)
          count.positive? ? (updated += 1) : (skipped += 1)
        end

        summary = "done; updated #{updated}, skipped #{skipped} already-current (of #{total_onts}); Solr retries: #{@retry_count}"
        if @retry_count.zero?
          log(summary)
        else
          @logger.warn("RankSolrPropagator: BACKPRESSURE — #{summary}. " \
                       'Solr stalled and was retried; consider a smaller RANK_SOLR_BATCH_SIZE.')
          @logger.flush if @logger.respond_to?(:flush)
        end
        updated
      end

      private

      # Counts docs whose ontologyRank is not already the target, then cursor-scans
      # just those stale docs and atomic-updates them. Returns docs updated.
      # Scanning the stale set is safe under cursorMark: docs we update leave the
      # set only behind the (id-ascending) cursor, so no stale doc is skipped.
      def update_ontology_rank(acronym, score)
        acronym_q = "submissionAcronym:\"#{acronym}\""
        lo = format('%.4f', score - SCORE_TOLERANCE)
        hi = format('%.4f', score + SCORE_TOLERANCE)
        stale_fq = "-ontologyRank:[#{lo} TO #{hi}]"

        stale = solr_count(acronym_q, stale_fq)
        if stale.zero?
          log("  #{acronym}: already current; skipping")
          return 0
        end
        log("  #{acronym}: #{stale} docs to update")

        cursor = '*'
        total = 0
        last_logged = 0

        loop do
          resp = solr_search(acronym_q, fq: stale_fq, fl: 'id', rows: @batch_size,
                                        sort: 'id asc', cursorMark: cursor)
          docs = resp.dig('response', 'docs') || []

          unless docs.empty?
            batch = docs.map { |d| { id: d['id'], ontologyRank: { set: score } } }
            with_retry("update #{acronym}") do
              LinkedData::Models::Class.search_client.index_document(batch, commit: false)
            end
            total += batch.size

            if total - last_logged >= PROGRESS_EVERY
              log("  #{acronym}: #{total}/#{stale} docs…")
              last_logged = total
            end
          end

          next_cursor = resp['nextCursorMark']
          break if next_cursor.nil? || next_cursor == cursor

          cursor = next_cursor
        end

        # Commit between ontologies (no updates in flight) — keeps the tlog
        # bounded without stalling replica forwarding mid-stream.
        log("  #{acronym}: committing #{total} docs…")
        with_retry("commit #{acronym}") { LinkedData::Models::Class.indexCommit(nil) }
        log("  #{acronym}: done (#{total} docs)")
        total
      end

      def solr_count(query, fq = nil)
        params = { rows: 0 }
        params[:fq] = fq if fq
        (solr_search(query, **params).dig('response', 'numFound') || 0).to_i
      end

      def solr_search(query, **params)
        with_retry('search') { LinkedData::Models::Class.search(query, params) }
      end

      # Retries transient Solr/network errors (distributed-update stalls,
      # connection blips, timeouts) with exponential backoff. Re-raises once
      # retries are exhausted.
      def with_retry(what)
        attempts = 0
        begin
          yield
        rescue RSolr::Error::Http, RSolr::Error::ConnectionRefused,
               Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, Errno::ETIMEDOUT,
               Net::ReadTimeout, Net::OpenTimeout, Net::WriteTimeout,
               SocketError => e
          attempts += 1
          @retry_count += 1
          first_line = e.message.to_s.lines.first&.strip

          if attempts > MAX_RETRIES
            @logger.error("RankSolrPropagator: BACKPRESSURE — #{what} still failing after " \
                          "#{MAX_RETRIES} retries; aborting — #{first_line}")
            @logger.flush if @logger.respond_to?(:flush)
            raise
          end

          wait = RETRY_BASE_SLEEP * (2**(attempts - 1))
          @logger.warn("RankSolrPropagator: BACKPRESSURE — #{what} failed (attempt " \
                       "#{attempts}/#{MAX_RETRIES}); retrying in #{wait}s — #{first_line}")
          @logger.flush if @logger.respond_to?(:flush)
          sleep(wait)
          retry
        end
      end

      def log(msg)
        @logger.info("RankSolrPropagator: #{msg}")
        @logger.flush if @logger.respond_to?(:flush)
      end
    end
  end
end
