require 'ontologies_linked_data/models/properties/ontology_property'

module LinkedData
  module Models

    class ObjectProperty < LinkedData::Models::OntologyProperty
      model :object_property, name_with: :id, collection: :submission,
            namespace: :owl, :schemaless => :true,
            rdf_type: lambda { |*x| RDF::OWL[:ObjectProperty] }

      PROPERTY_TYPE = "OBJECT"
      TOP_PROPERTY = "#topObjectProperty"

      attribute :submission, :collection => lambda { |s| s.resource_id }, :namespace => :metadata
      attribute :label, namespace: :rdfs, enforce: [:list]
      attribute :definition, namespace: :skos, enforce: [:list], alias: true
      attribute :parents, namespace: :rdfs, enforce: [:list, :object_property], property: :subPropertyOf
      attribute :children, namespace: :rdfs, inverse: { on: :object_property, :attribute => :parents }
      attribute :ancestors, namespace: :rdfs, property: :subPropertyOf, handler: :retrieve_ancestors
      attribute :descendants, namespace: :rdfs, property: :subPropertyOf, handler: :retrieve_descendants
      attribute :domain, namespace: :rdfs
      attribute :range, namespace: :rdfs

      serialize_default :label, :labelGenerated, :definition, :matchType, :ontologyType, :propertyType, :parents, :children, :hasChildren, :domain, :range # some of these attributes are used in Search (not shown out of context)
      aggregates childrenCount: [:count, :children]
      serialize_methods :properties
      # this command allows the children to be serialized in the output
      embed :children

      link_to LinkedData::Hypermedia::Link.new("self", lambda {|m| "#{self.ontology_link(m)}/properties/#{CGI.escape(m.id.to_s)}"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("ontology", lambda {|m| self.ontology_link(m)}, Goo.vocabulary["Ontology"]),
              LinkedData::Hypermedia::Link.new("submission", lambda {|m| "#{self.ontology_link(m)}/submissions/#{m.submission.id.to_s.split("/")[-1]}"}, Goo.vocabulary["OntologySubmission"]),
              LinkedData::Hypermedia::Link.new("parents", lambda {|m| "#{self.ontology_link(m)}/properties/#{CGI.escape(m.id.to_s)}/parents"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("children", lambda {|m| "#{self.ontology_link(m)}/properties/#{CGI.escape(m.id.to_s)}/children"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("ancestors", lambda {|m| "#{self.ontology_link(m)}/properties/#{CGI.escape(m.id.to_s)}/ancestors"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("descendants", lambda {|m| "#{self.ontology_link(m)}/properties/#{CGI.escape(m.id.to_s)}/descendants"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("tree", lambda {|m| "#{self.ontology_link(m)}/properties/#{CGI.escape(m.id.to_s)}/tree"}, self.uri_type)

      enable_indexing(:property_search,
                      :property,
                      bootstrap_collection: :property_search_bootstrap,
                      num_shards: LinkedData.settings.property_search_num_shards,
                      replication_factor: LinkedData.settings.property_search_replication_factor) do |schema_generator|
        index_schema(schema_generator)
      end
    end

  end
end
