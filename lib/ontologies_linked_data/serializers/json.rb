require 'multi_json'

module LinkedData
  module Serializers
    class JSON
      CONTEXTS = {}

      def self.serialize(obj, options = {})
        hash = obj.to_flex_hash(options) do |hash, hashed_obj|
          current_cls = hashed_obj.respond_to?(:klass) ? hashed_obj.klass : hashed_obj.class

          # Add the id to json-ld attribute
          if current_cls.ancestors.include?(LinkedData::Hypermedia::Resource) && !current_cls.embedded? && hashed_obj.respond_to?(:id)
            prefixed_id = LinkedData::Models::Base.replace_url_id_to_prefix(hashed_obj.id)
            hash["@id"] = prefixed_id.to_s
          end
          # Add the type
          if hash["@id"] && current_cls.respond_to?(:type_uri)
            # For internal class
            hash["@type"] = current_cls.type_uri.to_s
          elsif hash["@id"] && hashed_obj.respond_to?(:type_uri)
            # For External and Interportal class
            hash["@type"] = hashed_obj.type_uri.to_s
          end

          # Generate links
          # NOTE: If this logic changes, also change in xml.rb
          if generate_links?(options)
            links = LinkedData::Hypermedia.generate_links(hashed_obj)
            unless links.empty?
              hash["links"] = links
              hash["links"].merge!(generate_links_context(hashed_obj)) if generate_context?(options)
            end
          end

          # Generate context
          if current_cls.ancestors.include?(Goo::Base::Resource) && !current_cls.embedded?
            if generate_context?(options)
              context = generate_context(hashed_obj, hash.keys, options)
              hash.merge!(context)
            end
          elsif (hashed_obj.instance_of?(LinkedData::Models::ExternalClass) || hashed_obj.instance_of?(LinkedData::Models::InterportalClass)) && !current_cls.embedded?
            # Add context for ExternalClass
            context_hash = {"@vocab" => Goo.vocabulary.to_s, "prefLabel" => "http://data.bioontology.org/metadata/skosprefLabel"}
            context = {"@context" => context_hash}
            hash.merge!(context)
          end
        end

        MultiJson.dump(hash)
      end

      private

      def self.generate_context(object, serialized_attrs = [], options = {})
        return remove_unused_attrs(CONTEXTS[object.hash], serialized_attrs) unless CONTEXTS[object.hash].nil?
        hash = {}
        current_cls = object.respond_to?(:klass) ? object.klass : object.class
        class_attributes = current_cls.attributes
        hash["@vocab"] = Goo.vocabulary.to_s
        class_attributes.each do |attr|
          if current_cls.model_settings[:range].key?(attr)
            linked_model = current_cls.model_settings[:range][attr]
          end

          if linked_model && linked_model.ancestors.include?(Goo::Base::Resource) && !embedded?(object, attr)
            # linked object
            predicate = {"@id" => linked_model.type_uri.to_s, "@type" => "@id"}
          else
            # use the original predicate property if set
            predicate_attr =  current_cls.model_settings[:attributes][attr][:property] || attr
            # predicate with custom namespace
            # if the namespace can be resolved by the namespaces added in Goo then it will be resolved.
            predicate = "#{Goo.vocabulary(current_cls.model_settings[:attributes][attr][:namespace])&.to_s}#{predicate_attr}"
          end
          hash[attr] = predicate unless predicate.nil?
        end
        context = {"@context" => hash}
        CONTEXTS[object.hash] = context
        context = remove_unused_attrs(context, serialized_attrs) unless options[:params] && options[:params]["full_context"].eql?("true")
        context
      end

      def self.generate_links_context(object)
        current_cls = object.respond_to?(:klass) ? object.klass : object.class
        links = current_cls.hypermedia_settings[:link_to]
        links_context = {}
        links.each do |link|
          links_context[link.type] = link.type_uri.to_s
        end
        return {"@context" => links_context}
      end

      def self.remove_unused_attrs(context, serialized_attrs = [])
        new_context = context["@context"].reject {|k,v| !serialized_attrs.include?(k) && !k.to_s.start_with?("@")}
        {"@context" => new_context}
      end

      def self.embedded?(object, attribute)
        current_cls = object.respond_to?(:klass) ? object.klass : object.class
        embedded = false
        embedded = true if current_cls.hypermedia_settings[:embed].include?(attribute)
        embedded = true if (
          !current_cls.hypermedia_settings[:embed_values].empty? && current_cls.hypermedia_settings[:embed_values].first.key?(attribute)
        )
        embedded
      end

      def self.generate_context?(options)
        params = options[:params]
        params.nil? ||
          (params["no_context"].nil? ||
                     !params["no_context"].eql?("true")) &&
          (params["display_context"].nil? ||
                    !params["display_context"].eql?("false"))
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

