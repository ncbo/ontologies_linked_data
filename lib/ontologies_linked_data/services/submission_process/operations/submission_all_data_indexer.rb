require 'parallel'
module LinkedData
  module Services
    class OntologySubmissionAllDataIndexer < OntologySubmissionProcess

      def process(logger, options = nil)
        status = LinkedData::Models::SubmissionStatus.find('INDEXED_ALL_DATA').first
        begin
          index_all_data(logger, **options)
          @submission.add_submission_status(status)
        rescue StandardError => e
          logger.error("Error indexing all data for submission: #{e.message} : #{e.backtrace.join("\n")}")
          @submission.add_submission_status(status.get_error_status)
        ensure
          @submission.save
        end
      end

      private

      def index_all_data(logger, commit: true)
        size = Goo.backend_vo? ? 100 : 1000
        count_ids = 0

        ontology = @submission.bring(:ontology).ontology
                              .bring(:acronym).acronym
        conn = init_search_collection(ontology)
        r = Goo.sparql_query_client.query("SELECT (COUNT(DISTINCT ?id) as ?count) WHERE { GRAPH <#{@submission.id}> { ?id ?p ?v } }")
        total_ids = r.each_solution.first[:count].to_i
        logger.info "Total ids count: #{total_ids}"

        r = Goo.sparql_query_client.query("SELECT (COUNT(*) as ?count) WHERE { GRAPH <#{@submission.id}> { ?id ?p ?v } }")
        total_triples = r.each_solution.first[:count].to_i
        logger.info "Total triples count: #{total_triples}"

        chunk_size = total_ids / size + 1
        total_triples_indexed = 0
        total_time = Benchmark.realtime do
          results = Parallel.map((1..chunk_size).to_a, in_threads: 10) do |p|
            index_all_data_page(logger, p, size, ontology, conn, commit)
          end
          results.each do |x|
            next if x.nil?

            count_ids += x[1]
            total_triples_indexed += x[2]
          end
        end

        logger.info("Completed indexing all ontology data in #{total_time} sec. (#{count_ids} ids / #{total_triples} triples)")
      end

      def index_all_data_page(logger, page, size, ontology, conn, commit = true)
        ids = []
        time = Benchmark.realtime do
          ids = fetch_ids(size, page)
        end
        count_ids = ids.size
        total_time = time
        return if ids.empty?

        logger.info("Page #{page} - Fetch IDS: #{ids.size} ids (total: #{count_ids})  in #{time} sec.")
        documents = []
        triples_count = 0
        time = Benchmark.realtime do
          documents, triples_count = fetch_triples(ids, ontology)
        end
        total_time += time
        logger.info("Page #{page} - Fetch IDs triples: #{triples_count}  in #{time} sec.")
        return if documents.empty?

        time = Benchmark.realtime do
          puts "Indexing #{documents.size} documents page: #{page}"
          conn.index_document(documents.values, commit: commit)
        end
        logger.info("Page #{page} - Indexed #{documents.size} documents page: #{page} in #{time} sec.")
        [total_time, count_ids, triples_count]
      end

      def fetch_ids(size, page)
        query = Goo.sparql_query_client.select(:id)
                   .distinct
                   .from(RDF::URI.new(@submission.id))
                   .where(%i[id p v])
                   .limit(size)
                   .offset((page - 1) * size)

        query.each_solution.map{|x| x.id.to_s}
      end

      def update_doc(doc, property, new_val)
        unescaped_prop = property.gsub('___', '://')

        unescaped_prop = unescaped_prop.gsub('_', '/')
        existent_val = doc["#{unescaped_prop}_t"] || doc["#{unescaped_prop}_txt"]

        if !existent_val && !property['#']
          unescaped_prop = unescaped_prop.sub(%r{/([^/]+)$}, '#\1') # change latest '/' with '#'
          existent_val = doc["#{unescaped_prop}_t"] || doc["#{unescaped_prop}_txt"]
        end

        if existent_val && new_val || new_val.is_a?(Array)
          doc.delete("#{unescaped_prop}_t")
          doc["#{unescaped_prop}_txt"] = Array(existent_val) + Array(new_val).map(&:to_s)
        elsif existent_val.nil? && new_val
          doc["#{unescaped_prop}_t"] = new_val.to_s
        end
        doc
      end

      def init_search_collection(ontology)
        @submission.class.clear_indexed_content(ontology)
      end

      def fetch_triples(ids_slice, ontology)
        documents = {}
        count = 0
        fetch_paginated_triples(ids_slice).each do |sol|
          count += 1
          doc = documents[sol[:id].to_s]
          doc ||= {
            id: "#{sol[:id]}_#{ontology}", submission_id_t: @submission.id.to_s,
            ontology_t: ontology, resource_model: @submission.class.model_name,
            resource_id: sol[:id].to_s
          }
          property = sol[:p].to_s
          value = sol[:v]

          if property.to_s.eql?(RDF.type.to_s)
            update_doc(doc, 'type', value)
          else
            update_doc(doc, property, value)
          end
          documents[sol[:id].to_s] = doc
        end

        [documents, count]
      end

      def fetch_paginated_triples(ids_slice)
        solutions = []
        count = 0
        page = 1
        page_size = 10_000
        filter = ids_slice.map { |x| "?id = <#{x}>" }.join(' || ')

        while count.positive? || page == 1
          query = Goo.sparql_query_client.select(:id, :p, :v)
                     .from(RDF::URI.new(@submission.id))
                     .where(%i[id p v])
                     .filter(filter)
                     .slice((page - 1) * page_size, page_size)

          sol = query.each_solution.to_a
          count = sol.size
          solutions += sol
          break if count.zero? || count < page_size

          page += 1
        end
        solutions
      end
    end
  end

end