require 'xml'

module LinkedData
  module Serializers
    class XML
      def self.serialize(obj, options)
        formatted_hash = obj.to_flex_hash(options) do |hash, hashed_obj|
          if hashed_obj.is_a?(Goo::Base::Resource) || hashed_obj.is_a?(Struct)
            current_cls = hashed_obj.respond_to?(:klass) ? hashed_obj.klass : hashed_obj.class
            # Add the id and type
            if current_cls.ancestors.include?(LinkedData::Hypermedia::Resource) && !current_cls.embedded?
              prefixed_id = LinkedData::Models::Base.replace_url_id_to_prefix(hashed_obj.id)
              hash["id"] = prefixed_id.to_s
              hash["type"] = current_cls.type_uri.to_s
            end

            # Generate links
            # NOTE: If this logic changes, also change in json.rb
            if generate_links?(options)
              links_xml = generate_links(hashed_obj)
              hash["links"] = links_xml unless links_xml.empty?
            end
          end
        end
        enumerable = obj.kind_of?(Array) || obj.kind_of?(Set)
        cls = enumerable ? obj.first.class : obj.class
        cls = obj.first.klass if enumerable && obj.first.is_a?(Struct)
        cls = options[:class_name] if options[:class_name]
        to_xml(formatted_hash, convert_class_name(cls)).to_s
      end

      def self.to_xml(object, type, links = {})
        doc = ::XML::Document.new
        if object.nil? || object.respond_to?("empty?") && object.empty?
          doc.root = ::XML::Node.new("empty")
          return doc
        end

        if object.kind_of?(Hash)
          root = convert_hash(object, type, links)
        elsif object.kind_of?(Array)
          root = convert_array(object, type, links)
        else
          root = ::XML::Node.new(object.to_s)
        end

        doc.root = root
        doc
      end

      private

      def self.generate_links(object)
        current_cls = object.respond_to?(:klass) ? object.klass : object.class
        return {} if !current_cls.ancestors.include?(LinkedData::Hypermedia::Resource) || current_cls.hypermedia_settings[:link_to].empty?

        links = current_cls.hypermedia_settings[:link_to]
        links_output = ::XML::Node.new("links")
        links.each do |link|
          link_xml = ::XML::Node.new(link.type)
          expanded_link = LinkedData::Hypermedia.expand_link(link, object)
          prefix = expanded_link.start_with?("http") ? "" : LinkedData.settings.rest_url_prefix
          link_xml['href'] = prefix + expanded_link
          link_xml['rel'] = link.type_uri.to_s if link.type_uri
          links_output << link_xml
        end
        return links_output
      end

      def self.convert_hash(hash, type, links = {})
        hash_container = ::XML::Node.new(clean_name(type))
        element = nil
        hash.each do |key, value|
          # If this is for a page element, use the actual type for the top-level collection
          key = type if key.to_s.eql?("collection")
          if value.kind_of?(Hash)
            element = convert_hash(value, key, links)
          elsif value.kind_of?(Enumerable)
            # If the hash is a page object, use collection for the top-level array's element name
            collection_name = hash[:page] && hash[:pageCount] ? "collection" : nil
            element = convert_array(value, key, links, collection_name)
          else
            element = ::XML::Node.new(clean_name(key))
            element << value.to_s
          end
          hash_container << element
          if hash["id"] && links[hash["id"]]
            hash_container << links[hash["id"]]
          end
        end
        hash_container
      end

      def self.convert_array(array, type, links = {}, collection_name = nil)
        collection_name ||= type.to_s
        suffix = collection_name.downcase.eql?("collection") ? "" : "Collection"
        root = ::XML::Node.new(clean_name(collection_name) + suffix)
        array.each do |item|
          element = ::XML::Node.new(clean_name(type))
          element.attributes["type"] = type.to_s unless element.name.eql?(type.to_s)
          if item.kind_of?(Hash)
            element = convert_hash(item, type, links)
          else
            element << item
          end
          root << element
        end
        root
      end

      def self.clean_name(type)
        element_name = type.to_s
        element_name = element_name.split("/").last.split("#").last if element_name.start_with?("http")
        element_name
      end

      def self.convert_class_name(cls)
        name = cls.name.split('::').last
        name[0] = name[0].downcase
        name
      end

      def self.generate_links?(options)
        params = options[:params]
        params.nil? ||
          (params["no_links"].nil? ||
                     !params["no_links"].eql?("true")) &&
          (params["display_links"].nil? ||
                    !params["display_links"].eql?("false"))
      end
    end
  end
end