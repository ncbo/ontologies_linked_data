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


        # Add subPropertyOf triples for custom properties
        unless ont_sub.prefLabelProperty.nil?
          unless ont_sub.prefLabelProperty == Goo.vocabulary(:rdfs)[:label] || ont_sub.prefLabelProperty == Goo.vocabulary(:metadata_def)[:prefLabel]
              triples << triple(ont_sub.prefLabelProperty, subPropertyOf, Goo.vocabulary(:metadata_def)[:prefLabel])
          end
        end
        unless ont_sub.definitionProperty.nil?
          unless ont_sub.definitionProperty == Goo.vocabulary(:rdfs)[:label] || ont_sub.definitionProperty == Goo.vocabulary(:skos)[:definition]
              triples << triple(ont_sub.definitionProperty, subPropertyOf, Goo.vocabulary(:skos)[:definition])
          end
        end
        unless ont_sub.synonymProperty.nil?
          unless ont_sub.synonymProperty == Goo.vocabulary(:rdfs)[:label] || ont_sub.synonymProperty == Goo.vocabulary(:skos)[:altLabel]
            triples << triple(ont_sub.synonymProperty, subPropertyOf, Goo.vocabulary(:skos)[:altLabel])
          end
        end
        unless ont_sub.authorProperty.nil?
          unless ont_sub.authorProperty == Goo.vocabulary(:dc)[:creator]
            triples << triple(ont_sub.authorProperty, subPropertyOf, Goo.vocabulary(:dc)[:creator])
          end
        end

        if ont_sub.hasOntologyLanguage.obo? || ont_sub.hasOntologyLanguage.owl?
          #obo syns
          #<http://www.geneontology.org/formats/oboInOwl#hasExactSynonym> 10M
          triples << triple(Goo.vocabulary(:oboinowl_gen)[:hasExactSynonym],
                            subPropertyOf, Goo.vocabulary(:skos)[:altLabel])
          triples << triple(Goo.vocabulary(:obo_purl)[:synonym], subPropertyOf, Goo.vocabulary(:skos)[:altLabel])
          #NCBO-1007

          #<http://www.geneontology.org/formats/oboInOwl#hasBroadSynonym> 22K
          triples << triple(Goo.vocabulary(:oboinowl_gen)[:hasBroadSynonym],
                            subPropertyOf, Goo.vocabulary(:skos)[:altLabel])
          #<http://www.geneontology.org/formats/oboInOwl#hasNarrowSynonym>  49K
          triples << triple(Goo.vocabulary(:oboinowl_gen)[:hasNarrowSynonym],
                            subPropertyOf, Goo.vocabulary(:skos)[:altLabel])
          #<http://www.geneontology.org/formats/oboInOwl#hasRelatedSynonym>  6M
          triples << triple(Goo.vocabulary(:oboinowl_gen)[:hasRelatedSynonym],
                            subPropertyOf, Goo.vocabulary(:skos)[:altLabel])

          #obo defs
          triples << triple(obo_definition_standard(),
                            subPropertyOf, Goo.vocabulary(:skos)[:definition])
          triples << triple(RDF::URI.new("http://purl.obolibrary.org/obo/def"),
                            subPropertyOf, Goo.vocabulary(:skos)[:definition])
        end
        return (triples.join "\n")
      end

      def self.label_for_class_triple(class_id,property,label)
        label = label.to_s.gsub('\\','\\\\\\\\')
        label = label.gsub('"','\"')
        return triple(class_id,property,RDF::Literal.new(label, :datatype => RDF::XSD.string))
      end

      def self.generated_label(class_id, existing_label)
        existing_label ||= []
        last_frag = last_iri_fragment(class_id.to_s)
        last_frag_words = last_frag.titleize
        generated_label = [last_frag, last_frag_words].uniq { |l| l.downcase }.map(&:downcase) - existing_label.map(&:downcase)
        existing_label_words = existing_label.map { |l| l.titleize.downcase }
        (generated_label + existing_label_words).uniq - existing_label.map(&:downcase)
      end

      def self.obselete_class_triple(class_id)
        return triple(RDF::URI.new(class_id.to_s),
                      RDF::URI.new("http://www.w3.org/2002/07/owl#deprecated"),
                      RDF::Literal.new("true", :datatype => RDF::XSD.boolean))
      end

      def self.obo_in_owl_obsolete_uri
        return RDF::URI.new "http://www.geneontology.org/formats/oboInOwl#ObsoleteClass"
      end

      def self.loom_mapping_triple(class_id,property,label)
        return triple(class_id,property,
                      RDF::Literal.new(label, :datatype => RDF::XSD.string))
      end

      def self.uri_mapping_triple(class_id,property,uri_class)
        return triple(class_id,property,uri_class)
      end

      def self.obo_definition_standard
        return RDF::URI.new("http://purl.obolibrary.org/obo/IAO_0000115")
      end
    end
  end
end
