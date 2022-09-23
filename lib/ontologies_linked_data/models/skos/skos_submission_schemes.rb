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

        def all_concepts_schemes
          LinkedData::Models::SKOS::Scheme.in(self).all
        end
      end
    end
  end
end

