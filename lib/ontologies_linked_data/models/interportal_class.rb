module LinkedData
  module Models
    class InterportalClass
      include LinkedData::Hypermedia::Resource
      # For class mapped to internal class that are inside another BioPortal appliance
      # We are generating the same link than a normal class but pointing to the other appliance

      attr_reader :id, :ontology, :type_uri, :source, :ui_link, :self
      attr_accessor :prefLabel

      serialize_never :id, :ontology, :type_uri, :source, :ui_link, :self

      link_to LinkedData::Hypermedia::Link.new("self", lambda { |ec| "#{ec.self.to_s}" }, "http://www.w3.org/2002/07/owl#Class"),
              LinkedData::Hypermedia::Link.new("ontology", lambda { |ec| ec.ontology.to_s }, Goo.vocabulary["Ontology"]),
              LinkedData::Hypermedia::Link.new("children", lambda { |ec| "#{ec.ontology.to_s}/classes/#{CGI.escape(ec.id.to_s)}/children" }, "http://www.w3.org/2002/07/owl#Class"),
              LinkedData::Hypermedia::Link.new("parents", lambda { |ec| "#{ec.ontology.to_s}/classes/#{CGI.escape(ec.id.to_s)}/parents" }, "http://www.w3.org/2002/07/owl#Class"),
              LinkedData::Hypermedia::Link.new("descendants", lambda { |ec| "#{ec.ontology.to_s}/classes/#{CGI.escape(ec.id.to_s)}/descendants" }, "http://www.w3.org/2002/07/owl#Class"),
              LinkedData::Hypermedia::Link.new("ancestors", lambda { |ec| "#{ec.ontology.to_s}/classes/#{CGI.escape(ec.id.to_s)}/ancestors" }, "http://www.w3.org/2002/07/owl#Class"),
              LinkedData::Hypermedia::Link.new("tree", lambda { |ec| "#{ec.ontology.to_s}/classes/#{CGI.escape(ec.id.to_s)}/tree" }, "http://www.w3.org/2002/07/owl#Class"),
              LinkedData::Hypermedia::Link.new("notes", lambda { |ec| "#{ec.ontology.to_s}/classes/#{CGI.escape(ec.id.to_s)}/notes" }, LinkedData::Models::Note.type_uri),
              LinkedData::Hypermedia::Link.new("mappings", lambda { |ec| "#{ec.ontology.to_s}/classes/#{CGI.escape(ec.id.to_s)}/mappings" }, Goo.vocabulary["Mapping"]),
              LinkedData::Hypermedia::Link.new("ui", lambda { |ec| ec.ui_link.to_s }, "http://www.w3.org/2002/07/owl#Class")

      def initialize(id, ontology, source)
        @id = id

        @ontology, acronym = ontology_url(ontology, source)
        @self = "#{@ontology}/classes/#{CGI.escape(id.to_s)}"
        @ui_link = "#{LinkedData.settings.interportal_hash[source]["ui"]}/ontologies/#{acronym}?p=classes&conceptid=#{CGI.escape(id)}"
        @type_uri = RDF::URI.new("http://www.w3.org/2002/07/owl#Class")
        @source = source
      end

      def getPrefLabel
        # Get the prefLabel from the source bioportal, if error it generates the label from the last part of the URL
        begin
          json_class = JSON.parse(Net::HTTP.get(URI.parse("#{@self}?apikey=#{LinkedData.settings.interportal_hash[@source]["apikey"]}")))
          @prefLabel = if !json_class["prefLabel"].nil?
                         json_class["prefLabel"]
                       else
                         id.split("/")[-1]
                       end
        rescue
          @prefLabel = id.split("/")[-1]
        end
      end

      def self.graph_uri(acronym)
        RDF::URI.new("http://data.bioontology.org/metadata/InterportalMappings/#{acronym}")
      end

      def self.graph_base_str
        "http://data.bioontology.org/metadata/InterportalMappings"
      end

      def self.url_param_str(acronym)
        # a little string to get interportal mappings in URL parameters
        RDF::URI.new("interportal:#{acronym}")
      end

      def self.base_url_param_str
        RDF::URI.new("interportal:")
      end

      private

      def ontology_url(ontology, source)
        url = ''
        if ontology =~ URI::DEFAULT_PARSER.make_regexp
          url = ontology
        else
          url = "#{LinkedData.settings.interportal_hash[source]['api']}/ontologies/#{ontology}"
        end
        acronym = url.split('/').last
        [url, acronym]

      end
    end
  end
end