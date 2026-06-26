module LinkedData
  module MediaTypes
    HTML = :html
    JSON = :json
    JSONP = :jsonp
    JSONLD = :jsonld
    XML = :xml
    RDF_XML = :rdf_xml
    TURTLE = :turtle
    NTRIPLES = :ntriples
    DEFAULT = JSON

    def self.all
      TYPE_MAP.keys
    end

    def self.base_type(type)
      TYPE_MAP[type]
    end

    def self.media_type_from_base(type)
      DEFAULT_TYPES[type]
    end

    def self.supported_base_type?(type)
      DEFAULT_TYPES.key?(type.to_sym)
    end

    def self.supported_type?(type)
      TYPE_MAP.key?(type.to_s)
    end

    private

    DEFAULT_TYPES = {
      JSON => "application/json",
      HTML => "text/html",
      TURTLE => "application/x-turtle",
      XML => "application/rdf+xml",
      JSONP => "application/javascript"
    }

    TYPE_MAP = {
      DEFAULT_TYPES[DEFAULT] => DEFAULT,
      "text/html" => HTML,
      "application/xhtml+xml" => HTML,
      "application/json" => JSON,
      "text/javascript" => JSONP,
      "application/javascript" => JSONP,
      "application/ecmascript" => JSONP,
      "application/x-ecmascript" => JSONP,
      "application/rdf+turtle" => TURTLE,
      "application/x-turtle" => TURTLE,
      "application/turtle" => TURTLE,
      "application/rdf+xml" => XML,
      "application/xml" => XML,
      "text/xml" => XML
    }

  end
end
