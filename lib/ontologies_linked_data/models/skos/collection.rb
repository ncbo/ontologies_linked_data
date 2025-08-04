module LinkedData
  module Models
    module SKOS
      class Collection < LinkedData::Models::Base

        model :collection, name_with: :id, collection: :submission,
                           namespace: :skos, schemaless: :true, rdf_type: ->(*x) { RDF::SKOS[:Collection] }

        attribute :prefLabel, namespace: :skos, enforce: [:existence]
        attribute :member, namespace: :skos, enforce: [:list, :class]
        attribute :submission, collection: ->(s) { s.resource_id }, namespace: :metadata

        embed :member
        serialize_default :prefLabel, :memberCount
        serialize_never :submission, :id, :member
        serialize_methods :properties, :memberCount
        aggregates memberCount: [:count, :member]

        cache_timeout 14400

        link_to LinkedData::Hypermedia::Link.new('self',
                                                 ->(s) { "ontologies/#{s.submission.ontology.acronym}/collections/#{CGI.escape(s.id.to_s)}"},
                                                 self.uri_type),
                LinkedData::Hypermedia::Link.new('members',
                                                 ->(s) { "ontologies/#{s.submission.ontology.acronym}/collections/#{CGI.escape(s.id.to_s)}/members"},
                                                 Goo.vocabulary(:skos)['Concept']),
                LinkedData::Hypermedia::Link.new('ontology', ->(s) { "ontologies/#{s.submission.ontology.acronym}"},
                                                 Goo.vocabulary['Ontology'])

        def properties
          self.unmapped
        end

        def memberCount
          sol = self.class.in(submission).models([self]).aggregate(:count, :member).first
          sol.nil? ? 0 : sol.aggregates.first.value
        end

      end
    end
  end

end
