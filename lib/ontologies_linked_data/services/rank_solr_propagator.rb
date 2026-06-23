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
    # so no per-class triplestore read is needed. Batches use commitWithin so
    # Solr soft-commits on a bounded schedule instead of accumulating an
    # unbounded transaction log; a final hard commit makes everything durable.
    #
    # Ontologies whose rank is unchanged since the last successful propagation
    # are skipped (tracked per acronym in Redis). Pass force: true to ignore the
    # skip cache and re-propagate everything (e.g. after a collection rebuild).
    #
    # See https://github.com/ncbo/ncbo_cron/issues/132
    class RankSolrPropagator
      DEFAULT_BATCH_SIZE = 5_000
      DEFAULT_COMMIT_WITHIN = 60_000 # ms; Solr soft-commit window during bulk updates
      PROGRESS_EVERY = 50_000        # log per-ontology progress every N docs
      # Redis key holding the last successfully propagated rank per acronym.
      LAST_PROPAGATED_REDIS_FIELD = 'ontology_rank_solr_propagated'

      def initialize(logger: nil, batch_size: DEFAULT_BATCH_SIZE, commit_within: DEFAULT_COMMIT_WITHIN)
        @logger = logger || Logger.new($stdout)
        @batch_size = batch_size
        @commit_within = commit_within
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

        LinkedData::Models::Class.indexCommit(nil)
        log("final commit done; updated #{updated}, skipped #{skipped} unchanged (of #{total_onts})")
        updated
      end

      private

      # Cursor-scans all term_search docs for the acronym and issues batched
      # atomic updates to ontologyRank. Returns the number of docs updated.
      def update_ontology_rank(acronym, score)
        query = "submissionAcronym:\"#{acronym}\""
        num_found = (LinkedData::Models::Class.search(query, { rows: 0 }).dig('response', 'numFound') || 0).to_i

        if num_found.zero?
          log("  #{acronym}: no term_search docs; skipping")
          return 0
        end
        log("  #{acronym}: #{num_found} docs to update")

        cursor = '*'
        total = 0
        last_logged = 0

        loop do
          resp = LinkedData::Models::Class.search(
            query, { fl: 'id', rows: @batch_size, sort: 'id asc', cursorMark: cursor }
          )
          docs = resp.dig('response', 'docs') || []

          unless docs.empty?
            batch = docs.map { |d| { id: d['id'], ontologyRank: { set: score } } }
            LinkedData::Models::Class.search_client.index_document(
              batch, commit: true, commit_within: @commit_within
            )
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

        log("  #{acronym}: done (#{total} docs)")
        total
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
