module LinkedData
  module Serializers
    class RDF_XML
      def self.serialize(hashes, options = {})
        subject = RDF::URI.new(hashes["id"])
        reverse = hashes["reverse"] || {}
        hashes.delete("id")
        hashes.delete("reverse")
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

        inverse_graph = RDF::Graph.new
        reverse.each do |reverse_subject, reverse_property|
          Array(reverse_property).each do |s|
            inverse_graph << RDF::Statement.new(RDF::URI.new(reverse_subject), RDF::URI.new(s), subject)
          end
        end

        a = RDF::RDFXML::Writer.buffer(prefixes: options) do |writer|
          writer << graph
        end

        b = RDF::RDFXML::Writer.buffer(prefixes: options) do |writer|
          writer << inverse_graph
        end
        xml_result = "#{a.chomp("</rdf:RDF>\n")}\n#{b.sub!(/^<\?xml[^>]*>\n<rdf:RDF[^>]*>/, '').gsub(/^$\n/, '')}"
        xml_result.gsub(/^$\n/, '')
      end
    end
  end
end