require 'ontologies_linked_data/media_types'
require 'ontologies_linked_data/serializers/xml'
require 'ontologies_linked_data/serializers/rdf_xml'
require 'ontologies_linked_data/serializers/json'
require 'ontologies_linked_data/serializers/jsonp'
require 'ontologies_linked_data/serializers/jsonld'
require 'ontologies_linked_data/serializers/html'
require 'ontologies_linked_data/serializers/ntriples'
require 'ontologies_linked_data/serializers/turtle'

module LinkedData
  module Serializers
    def self.serialize(obj, type, options = {})
      SERIALIZERS[type].serialize(obj, options)
    end

    SERIALIZERS = {
      LinkedData::MediaTypes::HTML => HTML,
      LinkedData::MediaTypes::JSON => JSON,
      LinkedData::MediaTypes::JSONP => JSONP,
      LinkedData::MediaTypes::JSONLD => JSONLD,
      LinkedData::MediaTypes::XML => XML,
      LinkedData::MediaTypes::RDF_XML => RDF_XML,
      LinkedData::MediaTypes::TURTLE => TURTLE,
      LinkedData::MediaTypes::NTRIPLES => NTRIPLES
    }
  end
end