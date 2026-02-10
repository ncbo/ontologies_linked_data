require 'multi_json'
require 'json/ld'

module LinkedData
  module Serializers
    class JSONLD

      def self.serialize(hashes, options = {})
        subject = RDF::URI.new(hashes['id'])
        reverse = hashes['reverse'] || {}
        hashes.delete('id')
        hashes.delete('reverse')
        graph = RDF::Graph.new

        hashes.each do |property_url, val|
          Array(val).each do |v|
            if v.is_a?(Hash)
              blank_node = RDF::Node.new
              v.each do |blank_predicate, blank_value|
                graph << RDF::Statement.new(blank_node, RDF::URI.new(blank_predicate), blank_value)
              end
              v = blank_node
            end
            graph << RDF::Statement.new(subject, RDF::URI.new(property_url), v)
          end
        end

        reverse.each do |reverse_subject, reverse_property|
          Array(reverse_property).each do |s|
            graph << RDF::Statement.new(RDF::URI.new(reverse_subject), RDF::URI.new(s), subject)
          end
        end

        context = { '@context' => options.transform_keys(&:to_s) }
        compacted = ::JSON::LD::API.compact(::JSON::LD::API.fromRdf(graph), context['@context'])
        MultiJson.dump(compacted)
      end
    end
  end
end