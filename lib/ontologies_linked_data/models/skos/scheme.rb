module LinkedData
  module Models
    module SKOS
      class Scheme < LinkedData::Models::Base

        model :scheme, name_with: :id, collection: :submission,
              namespace: :skos, schemaless: :true, rdf_type: ->(*x) { RDF::SKOS[:ConceptScheme] }

        attribute :prefLabel, namespace: :skos, enforce: [:existence]

        attribute :submission, collection: ->(s) { s.resource_id }, namespace: :metadata

        serialize_never :submission, :id
        serialize_methods :properties

        cache_timeout 14400

        link_to LinkedData::Hypermedia::Link.new('self',
                                                 ->(s) { "ontologies/#{s.submission.ontology.acronym}/schemes/#{CGI.escape(s.id.to_s)}"},
                                                 self.uri_type),
                LinkedData::Hypermedia::Link.new('roots',
                                                 ->(s) { "ontologies/#{s.submission.ontology.acronym}/classes/roots?concept_scheme=#{CGI.escape(s.id.to_s)}"},
                                                 Goo.vocabulary(:skos)['Concept']),
                LinkedData::Hypermedia::Link.new('ontology', ->(s) { "ontologies/#{s.submission.ontology.acronym}"},
                                                 Goo.vocabulary['Ontology'])

        def properties
          self.unmapped
        end

      end
    end
  end

end
