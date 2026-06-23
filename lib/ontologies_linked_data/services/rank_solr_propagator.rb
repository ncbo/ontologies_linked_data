# frozen_string_literal: true

require 'redis'

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
    # Updates use true Solr atomic updates ({ id, ontologyRank: { set: score } })
    # so no per-class triplestore read is needed. Batches are sent without a
    # commit; a single commit is issued *between* ontologies (when no updates are
    # in flight) to keep the transaction log bounded without pausing replicas
    # mid-stream — committing during the update stream backs up SolrCloud's
    # leader->replica forwarding queue and causes "distributed update stalled"
    # 500s. Each Solr call is retried with backoff so a transient stall is
    # survived rather than aborting the whole run.
    #
    # Ontologies whose rank is unchanged since the last successful propagation
    # are skipped (tracked per acronym in Redis). Pass force: true to ignore the
    # skip cache and re-propagate everything (e.g. after a collection rebuild).
    #
    # See https://github.com/ncbo/ncbo_cron/issues/132
    class RankSolrPropagator
      DEFAULT_BATCH_SIZE = 2_500
      PROGRESS_EVERY = 50_000   # log per-ontology progress every N docs
      MAX_RETRIES = 5
      RETRY_BASE_SLEEP = 5      # seconds; exponential backoff: 5, 10, 20, 40, 80
      # Redis key holding the last successfully propagated rank per acronym.
      LAST_PROPAGATED_REDIS_FIELD = 'ontology_rank_solr_propagated'

      # batch_size precedence: explicit arg > RANK_SOLR_BATCH_SIZE env > default.
      # The env override lets the batch size be tuned on staging without a deploy.
      def initialize(logger: nil, batch_size: nil)
        @logger = logger || Logger.new($stdout)
        @batch_size = (batch_size || ENV['RANK_SOLR_BATCH_SIZE'] || DEFAULT_BATCH_SIZE).to_i
      end

      # Reads the rank map and writes each ontology's normalizedScore onto all of
      # its term_search docs. Unchanged ontologies are skipped unless force: true.
      # Returns the number of ontologies whose docs were updated.
      def propagate(rank_map = nil, force: false)
        rank_map ||= LinkedData::Models::Ontology.rank

        if rank_map.nil? || rank_map.empty?
          @logger.warn('RankSolrPropagator: empty rank map; nothing to propagate')
          return 0
        end

        last_propagated = force ? {} : load_last_propagated
        total_onts = rank_map.size
        updated = 0
        skipped = 0

        rank_map.each_with_index do |(acronym, rank_info), i|
          score = rank_info[:normalizedScore].to_f

          if !force && last_propagated[acronym] == score
            skipped += 1
            next
          end

          log("[#{i + 1}/#{total_onts}] #{acronym} rank=#{score}")
          count = update_ontology_rank(acronym, score)

          last_propagated[acronym] = score
          save_last_propagated(last_propagated)
          updated += 1 if count.positive?
        end

        log("done; updated #{updated}, skipped #{skipped} unchanged (of #{total_onts})")
        updated
      end

      private

      # Cursor-scans all term_search docs for the acronym, issues batched atomic
      # updates to ontologyRank (no commit), then commits once. Returns the
      # number of docs updated.
      def update_ontology_rank(acronym, score)
        query = "submissionAcronym:\"#{acronym}\""
        num_found = (solr_search(query, rows: 0).dig('response', 'numFound') || 0).to_i

        if num_found.zero?
          log("  #{acronym}: no term_search docs; skipping")
          return 0
        end
        log("  #{acronym}: #{num_found} docs to update")

        cursor = '*'
        total = 0
        last_logged = 0

        loop do
          resp = solr_search(query, fl: 'id', rows: @batch_size, sort: 'id asc', cursorMark: cursor)
          docs = resp.dig('response', 'docs') || []

          unless docs.empty?
            batch = docs.map { |d| { id: d['id'], ontologyRank: { set: score } } }
            with_retry("update #{acronym}") do
              LinkedData::Models::Class.search_client.index_document(batch, commit: false)
            end
            total += batch.size

            if total - last_logged >= PROGRESS_EVERY
              log("  #{acronym}: #{total}/#{num_found} docs…")
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

      def solr_search(query, **params)
        with_retry('search') { LinkedData::Models::Class.search(query, params) }
      end

      # Retries transient Solr errors (e.g. distributed-update stalls under load)
      # with exponential backoff. Re-raises once retries are exhausted.
      def with_retry(what)
        attempts = 0
        begin
          yield
        rescue RSolr::Error::Http, Net::ReadTimeout, Net::OpenTimeout,
               Errno::ECONNRESET, Errno::EPIPE => e
          attempts += 1
          raise if attempts > MAX_RETRIES

          wait = RETRY_BASE_SLEEP * (2**(attempts - 1))
          first_line = e.message.to_s.lines.first&.strip
          log("#{what} failed (attempt #{attempts}/#{MAX_RETRIES}); retrying in #{wait}s — #{first_line}")
          sleep(wait)
          retry
        end
      end

      def log(msg)
        @logger.info("RankSolrPropagator: #{msg}")
        @logger.flush if @logger.respond_to?(:flush)
      end

      def redis
        @redis ||= Redis.new(host: LinkedData.settings.ontology_analytics_redis_host,
                             port: LinkedData.settings.ontology_analytics_redis_port)
      end

      def load_last_propagated
        raw = redis.get(LAST_PROPAGATED_REDIS_FIELD)
        raw ? Marshal.load(raw) : {}
      rescue StandardError => e
        @logger.warn("RankSolrPropagator: could not load skip cache (#{e.class}: #{e.message}); propagating all")
        {}
      end

      def save_last_propagated(map)
        redis.set(LAST_PROPAGATED_REDIS_FIELD, Marshal.dump(map))
      rescue StandardError => e
        @logger.warn("RankSolrPropagator: could not save skip cache (#{e.class}: #{e.message})")
      end
    end
  end
end
