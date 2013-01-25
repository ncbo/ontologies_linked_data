module LinkedData
  module Models
    class Project < LinkedData::Models::Base
      model :project
      attribute :creator, :instance_of => { :with => :user }, :single_value => true, :not_nil => true
      attribute :created, :date_time_xsd => true, :single_value => true, :not_nil => true, :default => lambda {|x| DateTime.new }
      attribute :name, :unique => true, :single_value => true, :not_nil => true
      attribute :homePage, :uri => true, :single_value => true, :not_nil => true
      attribute :description, :single_value => true, :not_nil => true
      attribute :contacts, :single_value => true
      attribute :ontologyUsed, :instance_of => { :with => :ontology }

      # json-schema for description and validation of REST json responses.
      # http://tools.ietf.org/id/draft-zyp-json-schema-03.html
      # http://tools.ietf.org/html/draft-zyp-json-schema-03
      JSON_SCHEMA_STR = <<-END_JSON_SCHEMA_STR
      {
        "type":"object",
        "title":"Project",
        "description":"A BioPortal project, which may refer to multiple ontologies.",
        "additionalProperties":false,
        "properties":{
          "creator":{ "type":"string", "required": true },
          "created":{ "type":"string", "format":"datetime", "required": true },
          "name":{ "type":"string", "required": true },
          "homePage":{ "type":"string", "format":"uri", "required": true },
          "description":{ "type":"string", "required": true },
          "contacts":{ "type":"string" },
          "ontologyUsed":{ "type":"array", "items":{ "type":"string" } }
        }
      }
      END_JSON_SCHEMA_STR

      def json_schema_obj
        JSON.parse(JSON_SCHEMA_STR)
      end

    end
  end
end

