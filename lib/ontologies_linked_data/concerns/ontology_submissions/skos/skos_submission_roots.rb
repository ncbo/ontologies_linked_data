module LinkedData
  module Models
    module SKOS
      module RootsFetcher

        def skos_roots(concept_schemes, page, paged, pagesize)
          classes = []
          class_ids, count = roots_by_has_top_concept(concept_schemes, page, paged, pagesize)

          class_ids, count = roots_by_top_concept_of(concept_schemes, page, paged, pagesize) if class_ids.empty?

          class_ids.each do |id|
            classes << LinkedData::Models::Class.find(id).in(self).disable_rules.first
          end

          classes = Goo::Base::Page.new(page, pagesize, count, classes) if paged
          classes
        end

        private

        def roots_by_query(query_body, page, paged, pagesize)
          root_skos = <<-eos
              SELECT DISTINCT ?root WHERE {
              GRAPH #{self.id.to_ntriples} {
                #{query_body}
              }}
          eos
          count = 0

          count, root_skos = add_pagination(query_body, page, pagesize, root_skos) if paged

          #needs to get cached
          class_ids = []

          Goo.sparql_query_client.query(root_skos, { graphs: [self.id] }).each_solution do |s|
            class_ids << s[:root]
          end

          [class_ids, count]
        end

        def roots_by_has_top_concept(concept_schemes, page, paged, pagesize)
          query_body = <<-eos
            ?x #{RDF::SKOS[:hasTopConcept].to_ntriples} ?root .
            #{concept_schemes_filter(concept_schemes)}
          eos
          roots_by_query query_body, page, paged, pagesize
        end

        def roots_by_top_concept_of(concept_schemes, page, paged, pagesize)
          query_body = <<-eos
            ?root #{RDF::SKOS[:topConceptOf].to_ntriples}  ?x.
            #{concept_schemes_filter(concept_schemes)}
          eos
          roots_by_query query_body, page, paged, pagesize
        end

        def add_pagination(query_body, page, pagesize, root_skos)
          count = count_roots(query_body)

          offset = (page - 1) * pagesize
          root_skos = "#{root_skos} LIMIT #{pagesize} OFFSET #{offset}"
          [count, root_skos]
        end

        def count_roots(query_body)
          query = <<-eos
            SELECT (COUNT(?x) as ?count) WHERE {
            GRAPH #{self.id.to_ntriples} {
              #{query_body}
            }}
          eos
          rs = Goo.sparql_query_client.query(query)
          count = 0
          rs.each do |sol|
            count = sol[:count].object
          end
          count
        end

        def concept_schemes_filter(concept_schemes)
          concept_schemes = current_schemes(concept_schemes)
          concept_schemes = concept_schemes.map { |x| RDF::URI.new(x.to_s).to_ntriples }
          concept_schemes.empty? ? '' : "FILTER (?x IN (#{concept_schemes.join(',')}))"
        end

        def current_schemes(concept_schemes)
          if concept_schemes.nil? || concept_schemes.empty?
            main_concept_scheme = get_main_concept_scheme
            concept_schemes = main_concept_scheme ? [main_concept_scheme] : []
          end
          concept_schemes
        end

      end
    end
  end
end
