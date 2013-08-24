module LinkedData
  module Mappings
    class CUI < LinkedData::Mappings::BatchProcess

      def initialize(ontA,ontB, logger)
        @record = Struct.new(:acronym,:term_id,:cui)

        f = Goo::Filter.new(:cui).bound
        paging = LinkedData::Models::Class.where.filter(f).include(:cui)
        dumper = lambda { |c,ont| [[ont.acronym, c.id.to_s, c.cui]]}
        line_parser = lambda { |line| record_from_line(line) }
        is_mapping = lambda { |ra,rb| return ra.cui == rb.cui }
        skip_mapping = lambda { |ra,rb| return (ra.acronym == rb.acronym) ||
                                               (ra.term_id == rb.term_id) }
        sort_field = 3
        super("cui",
              paging,dumper,line_parser,is_mapping,skip_mapping,
              logger,sort_field,ontA, ontB)
      end

      def record_from_line(line)
        line = line.strip
        line_parts = line.split(",")
        r = @record.new
        r.acronym = line_parts.first
        r.term_id = RDF::URI.new(line_parts[1])
        r.cui = line_parts[2]
        return r
      end
    end # cui

  end # Mappings
end # LinKedData
