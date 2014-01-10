module LinkedData
  module Models
    class OntologyFormat < LinkedData::Models::Base
      VALUES = ["OBO", "OWL", "UMLS", "PROTEGE", "SKOS"]


      model :ontology_format, name_with: :acronym
      attribute :acronym, enforce: [:existence, :unique] 

      enum VALUES

      def obo?
        return id.to_s.end_with? "OBO"
      end
      def owl?
        return id.to_s.end_with? "OWL"
      end      
      def umls?
        return id.to_s.end_with? "UMLS"
      end
      def skos?
        return id.to_s.end_with? "SKOS"
      end

      def tree_property
        if obo?
          return Goo.vocabulary(:metadata)[:treeView]
        end
        if skos?
          return RDF::SKOS[:broader]
        end
        return RDF::RDFS[:subClassOf]
      end

      def class_type
        if skos?
          return RDF::SKOS[:Concept]
        end
        return RDF::OWL[:Class]
      end
    end
  end
end
