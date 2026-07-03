module LinkedData
  module Models
    module SKOS
      module ConceptSchemes
        def get_main_concept_scheme(default_return: ontology_uri)
          all = all_concepts_schemes
          unless all.nil?
            all = all.map { |x| x.id }
            return  default_return if all.include?(ontology_uri)
          end
        end

        # Memoized: the tree/paths endpoints resolve isInActiveScheme once per
        # node, so without this the same SKOS::Scheme query fires ~N times per
        # request (one triplestore miss + N-1 Redis cache hits). Cache the
        # result on the submission instance for the life of the request.
        def all_concepts_schemes
          @all_concepts_schemes ||= LinkedData::Models::SKOS::Scheme.in(self).all
        end
      end
    end
  end
end

