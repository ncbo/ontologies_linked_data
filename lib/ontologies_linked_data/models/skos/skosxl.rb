module LinkedData
  module Models
    module SKOS
      class Label < LinkedData::Models::Base

        model :label, name_with: :id, collection: :submission,
                      namespace: :skos, rdf_type: ->(*x) { RDF::URI.new('http://www.w3.org/2008/05/skos-xl#Label') }

        attribute :literalForm, namespace: :skosxl, enforce: [:existence]
        attribute :submission, collection: ->(s) { s.resource_id }, namespace: :metadata

        serialize_never :submission, :id
        serialize_methods :properties

        link_to LinkedData::Hypermedia::Link.new('self', ->(s) { "ontologies/#{s.submission.ontology.acronym}/skos_xl_labels/#{CGI.escape(s.id)}"}, self.uri_type)

        def properties
          self.unmapped
        end

      end
    end
  end

end
