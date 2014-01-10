module LinkedData
  module Utils
    module Triples
      def self.last_iri_fragment str
        token = (str.include? "#") ? "#" : "/"
        return (str.split token)[-1]
      end

      def self.triple(subject, predicate, object)
        return "#{subject.to_ntriples} #{predicate.to_ntriples} #{object.to_ntriples} ."
      end

      def self.rdf_for_custom_properties(ont_sub)
        triples = []
        subPropertyOf = Goo.vocabulary(:rdfs)[:subPropertyOf]

        triples << triple(Goo.vocabulary(:metadata_def)[:prefLabel], subPropertyOf, Goo.vocabulary(:skos)[:prefLabel])
        triples << triple(Goo.vocabulary(:skos)[:prefLabel], subPropertyOf, Goo.vocabulary(:rdfs)[:label])
        triples << triple(Goo.vocabulary(:skos)[:altLabel], subPropertyOf, Goo.vocabulary(:rdfs)[:label])
        triples << triple(Goo.vocabulary(:rdfs)[:comment], subPropertyOf, Goo.vocabulary(:skos)[:definition])

        unless ont_sub.prefLabelProperty.nil?
          unless ont_sub.prefLabelProperty == Goo.vocabulary(:rdfs)[:label]
            triples << triple(ont_sub.prefLabelProperty, subPropertyOf, Goo.vocabulary(:metadata_def)[:prefLabel])
          end
        end
        unless ont_sub.definitionProperty.nil?
          unless ont_sub.definitionProperty == Goo.vocabulary(:rdfs)[:label]
            triples << triple(ont_sub.definitionProperty, subPropertyOf, Goo.vocabulary(:skos)[:definition])
          end
        end
        unless ont_sub.synonymProperty.nil?
          unless ont_sub.synonymProperty == Goo.vocabulary(:rdfs)[:label]
            triples << triple(ont_sub.synonymProperty, subPropertyOf, Goo.vocabulary(:skos)[:altLabel])
          end
        end
        unless ont_sub.authorProperty.nil?
          triples << triple(ont_sub.authorProperty, subPropertyOf, Goo.vocabulary(:dc)[:creator])
        end

        if ont_sub.hasOntologyLanguage.obo?
          #obo syns
          triples << triple(Goo.vocabulary(:oboinowl_gen)[:hasExactSynonym], 
                              subPropertyOf, Goo.vocabulary(:skos)[:altLabel])
          triples << triple(Goo.vocabulary(:oboinowl_gen)[:hasRelatedSynonym], 
                              subPropertyOf, Goo.vocabulary(:skos)[:altLabel])
          triples << triple(Goo.vocabulary(:obo_purl)[:synonym], 
                            subPropertyOf, Goo.vocabulary(:skos)[:altLabel])

          #obo defs
          triples << triple(Goo.vocabulary(:obo_purl)[:def], subPropertyOf, Goo.vocabulary(:skos)[:definition])
        end
        return (triples.join "\n")
      end

      def self.label_for_class_triple(class_id,property,label)
        label = label.to_s.gsub('\\','\\\\\\\\')
        label = label.gsub('"','\"')
        return triple(class_id,property,RDF::Literal.new(label, :datatype => RDF::XSD.string))
      end

      def self.obselete_class_triple(class_id)
        return triple(RDF::URI.new(class_id.to_s),
                      RDF::URI.new("http://www.w3.org/2002/07/owl#deprecated"),
                      RDF::Literal.new("true", :datatype => RDF::XSD.boolean))
      end
    end
  end
end
