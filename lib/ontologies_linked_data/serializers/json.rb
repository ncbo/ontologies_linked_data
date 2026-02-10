require 'multi_json'

module LinkedData
  module Serializers
    class JSON
      CONTEXTS = {}

      def self.serialize(obj, options = {})

        return serialize_mod_objects(obj, options) if mod_object?(obj)

        # Handle the serialization for all other objects in the standard way
        hash = obj.to_flex_hash(options) do |hash, hashed_obj|
          process_common_serialization(hash, hashed_obj, options)
        end
        MultiJson.dump(hash)
      end
      
      def self.serialize_mod_objects(obj, options = {})
        # using one context and links in mod objects
        global_context = {}

        hash = obj.to_flex_hash(options) do |hash, hashed_obj|
          process_common_serialization(hash, hashed_obj, options, global_context)
        end

        result = {}
        # handle adding the context for HydraPage
        if obj.is_a?(LinkedData::Models::HydraPage)
          global_context["@context"] ||= {}
          global_context["@context"].merge!(LinkedData::Models::HydraPage.generate_hydra_context)
        end
        result.merge!(global_context) unless global_context.empty?
        result.merge!(hash) if hash.is_a?(Hash)
        MultiJson.dump(result)
      end

      
      private
      
      def self.process_common_serialization(hash, hashed_obj, options, global_context= nil)
        current_cls = hashed_obj.respond_to?(:klass) ? hashed_obj.klass : hashed_obj.class
        result_lang = get_languages(get_object_submission(hashed_obj), options[:lang])

        add_id_and_type(hash, hashed_obj, current_cls)
        add_links(hash, hashed_obj, options) if generate_links?(options)
        add_context(hash, hashed_obj, options, current_cls, result_lang, global_context) if generate_context?(options)
      end

      def self.add_id_and_type(hash, hashed_obj, current_cls)
        return unless current_cls.ancestors.include?(LinkedData::Hypermedia::Resource) && !current_cls.embedded? && hashed_obj.respond_to?(:id)

        hash["@id"] = LinkedData::Models::Base.replace_url_id_to_prefix(hashed_obj.id).to_s
        hash["@type"] = type(current_cls, hashed_obj) if hash["@id"]
      end

      def self.add_links(hash, hashed_obj, options)
        links = LinkedData::Hypermedia.generate_links(hashed_obj)
        return if links.empty?
        hash["links"] = links
        hash["links"].merge!(generate_links_context(hashed_obj)) if generate_context?(options)
      end

      def self.add_context(hash, hashed_obj, options, current_cls, result_lang, global_context)
        return if global_context&.any?

        if global_context.nil?
          if current_cls.ancestors.include?(Goo::Base::Resource) && !current_cls.embedded?
            context = generate_context(hashed_obj, hash.keys, options)
            hash.merge!(context)
          elsif (hashed_obj.instance_of?(LinkedData::Models::ExternalClass) || hashed_obj.instance_of?(LinkedData::Models::InterportalClass)) && !current_cls.embedded?
            # Add context for ExternalClass
            external_class_context = { "@context" => { "@vocab" => Goo.vocabulary.to_s, "prefLabel" => "http://data.bioontology.org/metadata/skosprefLabel" } }
            hash.merge!(external_class_context)
          end
          hash['@context']['@language'] = result_lang if hash['@context']
        elsif global_context.empty?
          context = generate_context(hashed_obj, hash.keys, options)
          global_context.replace(context)
          global_context["@context"]["@language"] = result_lang unless global_context.empty?
        end
      end

      def self.mod_object?(obj)
        return false if obj.nil?
        single_object = (obj.class == Array) && obj.any? ? obj.first : obj
        single_object.class.ancestors.include?(LinkedData::Models::HydraPage) || single_object.class.ancestors.include?(LinkedData::Models::ModBase)
      end
      

      def self.get_object_submission(obj)
        obj.class.respond_to?(:attributes) && obj.class.attributes.include?(:submission) ? obj.submission : nil
      end

      def self.get_languages(submission, user_languages)
        result_lang = user_languages

        if submission
          submission.bring :naturalLanguage
          languages = get_submission_languages(submission.naturalLanguage)
          # intersection of the two arrays , if the requested language is not :all
          result_lang = user_languages == :all ? languages : Array(user_languages) & languages
          result_lang = result_lang.first if result_lang.length == 1
        end

        result_lang
      end

      def self.get_submission_languages(submission_natural_language = [])
        submission_natural_language = submission_natural_language.values.flatten if submission_natural_language.is_a?(Hash)
        submission_natural_language.map { |natural_language| natural_language.to_s['iso639'] && natural_language.to_s.split('/').last[0..1].to_sym }.compact
      end 

      def self.type(current_cls, hashed_obj)
        if current_cls.respond_to?(:type_uri)
          # For internal class
          proc = current_cls
        elsif hashed_obj.respond_to?(:type_uri)
          # For External and Interportal class
          proc = hashed_obj
        end

        collection = hashed_obj.respond_to?(:collection) ? hashed_obj.collection : nil
        if collection
          proc.type_uri(collection).to_s
        else
          proc.type_uri.to_s
        end
      end

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
            predicate = { "@id" => linked_model.type_uri.to_s, "@type" => "@id" }
          else
            # use the original predicate property if set
            predicate_attr = current_cls.model_settings[:attributes][attr][:property] || attr
            # predicate with custom namespace
            # if the namespace can be resolved by the namespaces added in Goo then it will be resolved.
            predicate = "#{Goo.vocabulary(current_cls.model_settings[:attributes][attr][:namespace])&.to_s}#{predicate_attr}"
          end
          hash[attr] = predicate unless predicate.nil?
        end
        context = { "@context" => hash }
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
        return { "@context" => links_context }
      end

      def self.remove_unused_attrs(context, serialized_attrs = [])
        new_context = context["@context"].reject { |k, v| !serialized_attrs.include?(k) && !k.to_s.start_with?("@") }
        { "@context" => new_context }
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