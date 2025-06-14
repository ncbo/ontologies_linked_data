module LinkedData
  module Models
    class ExternalClass
      include LinkedData::Hypermedia::Resource
      # For class mapped to internal class that are outside any BioPortal appliance
      # We just generate a link to self class and a link to the external ontology

      attr_reader :id, :ontology, :type_uri
      attr_accessor :prefLabel

      serialize_never :id, :ontology, :type_uri

      link_to LinkedData::Hypermedia::Link.new("self", lambda {|ec| ec.id.to_s}, "http://www.w3.org/2002/07/owl#Class"),
              LinkedData::Hypermedia::Link.new("ontology", lambda {|ec| ec.ontology.to_s}, Goo.vocabulary["Ontology"])

      def initialize(id, ontology)
        @id = id
        @ontology = RDF::URI.new(CGI.unescape(ontology.to_s))
        @type_uri = RDF::URI.new("http://www.w3.org/2002/07/owl#Class")
      end

      def getPrefLabel
        # take the last part of the URL to generate the prefLabel (the one after the last #, or if not after the last /)
        if id.include? "#"
          @prefLabel = id.split("#")[-1]
        else
          @prefLabel = id.split("/")[-1]
        end
      end

      def self.graph_uri
        RDF::URI.new("http://data.bioontology.org/metadata/ExternalMappings")
      end
      def self.url_param_str
        # a little string to get external mappings in URL parameters
        RDF::URI.new("mappings:external")
      end
    end
  end
end