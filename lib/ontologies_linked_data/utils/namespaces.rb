module LinkedData
  module Utils
    module Namespaces

      #TODO: here we can do better.

      SKOS = "http://www.w3.org/2004/02/skos/core#"
      RDFS = "http://www.w3.org/2000/01/rdf-schema#"
      OWL = "http://www.w3.org/2002/07/owl#"
      DC = "http://purl.org/dc/elements/1.1/"
      XSD = "http://www.w3.org/2001/XMLSchema#"
      META = "http://bioportal.bioontology.org/metadata/def/"

      def self.meta_prefLabel
        META + "prefLabel"
      end
      def self.skos_prefLabel
        SKOS + "prefLabel"
      end
      def self.skos_altLabel
        SKOS + "altLabel"
      end
      def self.skos_definition
        SKOS + "definition"
      end
      def self.rdfs_subPropertyOf
        RDFS + "subPropertyOf"
      end
      def self.rdfs_subClassOf
        RDFS + "subClassOf"
      end
      def self.rdfs_label
        RDFS + "label"
      end
      def self.owl_class
        OWL + "Class"
      end
      def self.dc_creator
        return DC + "creator"
      end
      def self.xsd_string
        return XSD + "string"
      end
      def self.default_pref_label
        RDF::IRI.new(skos_prefLabel)
      end
      def self.default_hieararchy_property
        RDF:IRI.new(rdfs_subClassOf)
      end
      def self.default_type_for_classes
        RDF::IRI.new(owl_class)
      end
      def self.meta_prefLabel_iri
        RDF::IRI.new(meta_prefLabel)
      end


      #TODO: to move somewhere else
      def self.last_iri_fragment str
        token = (str.include? "#") ? "#" : "/"
        return (str.split token)[-1]
      end
    end
  end
end
