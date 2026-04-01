module LinkedData
  module Serializers
    class NTRIPLES

      def self.serialize(hashes, options = {})
        subject = RDF::URI.new(hashes['id'])
        reverse = hashes['reverse'] || {}
        hashes.delete('id')
        hashes.delete('reverse')
        RDF::Writer.for(:ntriples).buffer(prefixes: options) do |writer|
          hashes.each do |p, o|
            predicate = RDF::URI.new(p)
            Array(o).each do |item|
              if item.is_a?(Hash)
                blank_node = RDF::Node.new
                item.each do |blank_predicate, blank_value|
                  writer << RDF::Statement.new(blank_node, RDF::URI.new(blank_predicate), blank_value)
                end
                item = blank_node
              end
              writer << RDF::Statement.new(subject, predicate, item)
            end
          end

          reverse.each do |reverse_subject, reverse_property|
            Array(reverse_property).each do |s|
              writer << RDF::Statement.new(RDF::URI.new(reverse_subject), RDF::URI.new(s), subject)
            end
          end
        end
      end

    end
  end
end
  
  