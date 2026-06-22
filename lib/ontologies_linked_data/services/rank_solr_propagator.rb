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
    # Updates use true Solr atomic updates ({ id, ontologyRank: { set: score } })
    # so no per-class triplestore read is needed.
    #
    # See https://github.com/ncbo/ncbo_cron/issues/132
    class RankSolrPropagator
      DEFAULT_BATCH_SIZE = 1000

      def initialize(logger: nil, batch_size: DEFAULT_BATCH_SIZE)
        @logger = logger || Logger.new($stdout)
        @batch_size = batch_size
      end

      # Reads the rank map and writes each ontology's normalizedScore onto all
      # of its term_search docs. Returns the count of ontologies whose docs were
      # updated.
      def propagate(rank_map = nil)
        rank_map ||= LinkedData::Models::Ontology.rank

        if rank_map.nil? || rank_map.empty?
          @logger.warn('RankSolrPropagator: empty rank map; nothing to propagate')
          return 0
        end

        updated = 0
        rank_map.each do |acronym, rank_info|
          score = rank_info[:normalizedScore].to_f
          count = update_ontology_rank(acronym, score)
          @logger.info("RankSolrPropagator: #{acronym} rank=#{score} (#{count} docs)")
          updated += 1 if count.positive?
        end

        LinkedData::Models::Class.indexCommit(nil)
        @logger.info("RankSolrPropagator: committed; updated #{updated} ontologies")
        updated
      end

      private

      # Cursor-scans all term_search docs for the acronym and issues batched
      # atomic updates to ontologyRank. Returns the number of docs updated.
      def update_ontology_rank(acronym, score)
        cursor = '*'
        total = 0
        query = "submissionAcronym:\"#{acronym}\""

        loop do
          resp = LinkedData::Models::Class.search(
            query,
            { fl: 'id', rows: @batch_size, sort: 'id asc', cursorMark: cursor }
          )
          docs = resp.dig('response', 'docs') || []

          unless docs.empty?
            batch = docs.map { |d| { id: d['id'], ontologyRank: { set: score } } }
            LinkedData::Models::Class.search_client.index_document(batch, commit: false)
            total += batch.size
          end

          next_cursor = resp['nextCursorMark']
          break if next_cursor.nil? || next_cursor == cursor

          cursor = next_cursor
        end

        total
      end
    end
  end
end
