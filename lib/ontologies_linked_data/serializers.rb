module LinkedData
  module Serializers
    def self.serialize(obj, type, options = {})
      # Only support JSON for now
      JSON.serialize(obj, options)

      # SERIALIZERS[type].serialize(obj, options)
    end

    class JSON
      def self.serialize(obj, options)
        obj.to_flex_hash(options).to_json
      end

      private
      def self.build_context
      end
    end

    class JSONP
      def self.serialize(obj, options)
      end
    end

    class XML
      def self.serialize(obj, options)
      end
    end

    class HTML
      def self.serialize(obj, options)
      end
    end

    class Turtle
      def self.serialize(obj, options)
      end
    end

    SERIALIZERS = {
      LinkedData::MediaTypes::HTML => HTML,
      LinkedData::MediaTypes::JSON => JSON,
      LinkedData::MediaTypes::JSONP => JSONP,
      LinkedData::MediaTypes::XML => XML,
      LinkedData::MediaTypes::TURTLE => Turtle
    }
  end
end