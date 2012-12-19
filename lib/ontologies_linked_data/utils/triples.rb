module LinkedData
  module Utils
    module Triples
      def self.names
        LinkedData::Utils::Namespaces
      end
      def self.rdf_for_custom_properties(ont_sub)
        triples = []
        unless ont_sub.prefLabelProperty.nil?
          triples << "<#{ont_sub.prefLabelProperty.value}> <#{names.rdfs_subPropertyOf}> <#{names.meta_prefLabel}> ."
          triples << "<#{names.meta_prefLabel}> <#{names.rdfs_subPropertyOf}> <#{names.skos_prefLabel}> ."
          triples << "<#{names.skos_prefLabel}> <#{names.rdfs_subPropertyOf}> <#{names.rdfs_label}> ."
        end
        unless ont_sub.definitionProperty.nil?
          triples << "<#{ont_sub.definitionProperty.value}> <#{names.rdfs_subPropertyOf}> <#{names.skos_definition}> ."
        end
        unless ont_sub.synonymProperty.nil?
          triples << "<#{ont_sub.synonymProperty.value}> <#{names.rdfs_subPropertyOf}> <#{names.skos_altLabel}> ."
          triples << "<#{names.skos_altLabel}> <#{names.rdfs_subPropertyOf}> <#{names.rdfs_label}> ."
        end
        unless ont_sub.authorProperty.nil?
          triples << "<#{ont_sub.authorProperty.value}> <#{names.rdfs_subPropertyOf}> <#{names.dc_creator}> ."
        end
        return (triples.join "\n")
      end

      def self.label_for_class_triple(class_id,property,label)
        "<#{class_id.value}> <#{property.value}> \"\"\"#{label}\"\"\"^^<#{names.xsd_string}> ."
      end
    end
  end
end
