module LinkedData
  module Serializers
    class JSONP
      def self.serialize(obj, options)
        callback = options[:params]["callback"] || options[:params]["jsonp"] || "?"
        variable = options[:params]["variable"]
        json = LinkedData::Serializers::JSON.serialize(obj, options)
        begin
          if callback && variable
            "var #{variable} = #{json};\n#{callback}(#{variable});"
          elsif variable
            "var #{variable} = #{json};"
          elsif callback
            "#{callback}(#{json});"
          else
            "(#{json});"
          end
        end
      end
    end
  end
end
