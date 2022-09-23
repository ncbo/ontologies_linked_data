require 'active_support/core_ext/string'
require 'cgi'

module LinkedData
  module Models
    class Base < Goo::Base::Resource
      include LinkedData::Hypermedia::Resource
      include LinkedData::HTTPCache::CacheableResource
      include LinkedData::Security::AccessControl

      def save(*args)
        write_permission_check(*args)
        super(*args)
        self.cache_invalidate if LinkedData.settings.enable_http_cache
        self.cache_write if LinkedData.settings.enable_http_cache
        self
      end

      def delete(*args)
        write_permission_check(*args)
        super(*args)
        self.cache_invalidate if LinkedData.settings.enable_http_cache
        self
      end

      ##
      # Override find method to make sure the id matches what is in the RDF store
      # Only do this if the setting is enabled, string comparison sucks
      def self.find(id, *options)
        id = replace_url_prefix_to_id(id)

        # Handle `+` to ` ` conversion here because Sinatra doesn't do it for URI's
        id = id.gsub('+', ' ') unless id.start_with?('http')

        super(id, *options)
      end

      ##
      # This is a convenience method that will provide Goo with
      # a list of attributes and nested values to load for this request
      def self.goo_attrs_to_load(attributes = [], level = 0)
        raise ArgumentError, "`attributes` should be an array" unless attributes.is_a?(Array)

        # Get attributes, either provided, all, or default
        default_attrs = if !attributes.empty?
                          if attributes.first == :all
                            (self.attributes + self.hypermedia_settings[:serialize_default]).uniq
                          else
                            attributes
                          end
                        elsif self.hypermedia_settings[:serialize_default].empty?
                          self.attributes
                        else
                          self.hypermedia_settings[:serialize_default].dup
                        end

        embed_attrs = {}
        extra_attrs = []
        if level == 0
          # Also include attributes that are embedded
          self.hypermedia_settings[:embed].each do |e|
            next unless default_attrs.include?(e)
            default_attrs.delete(e)
            embed_class = self.range(e)
            next if embed_class.nil? || !embed_class.ancestors.include?(LinkedData::Models::Base)
            #hack to avoid nested unmapped queries in class
            if (self.model_name == :class)
              if attributes && attributes.include?(:properties)
                attributes = attributes.dup
                attributes.delete :properties
              end
            end
            embed_attrs[e] = embed_class.goo_attrs_to_load(attributes, level += 1)
          end
        end

        # Merge embedded with embedded values
        embed_values = self.hypermedia_settings[:embed_values].first
        embed_attrs.merge!(embed_values.dup) if embed_values

        # Include attributes needed for caching (if enabled)
        if LinkedData.settings.enable_http_cache
          cache_attributes = self.cache_settings[:cache_load]
          extra_attrs.concat(cache_attributes.to_a) unless cache_attributes.nil? && cache_attributes.empty?
        end

        # Include attributes needed for security (if enabled)
        if LinkedData.settings.enable_security
          access_control_attributes = self.access_control_load_attrs
          extra_attrs.concat(access_control_attributes.to_a) unless access_control_attributes.nil? && access_control_attributes.empty?
        end

        # These attributes need to be loaded to support link generation
        links_load = self.hypermedia_settings[:links_load]
        unless links_load.nil? || links_load.empty?
          extra_attrs.concat(links_load)
        end

        # Add extra attrs to appropriate group (embed Hash vs default Array)
        extra_attrs.each do |attr|
          if attr.is_a?(Hash)
            attr.each do |k, v|
              if embed_attrs.key?(k)
                embed_attrs[k].concat(v).uniq!
              else
                embed_attrs[k] = v
              end
            end
          else
            default_attrs << attr
          end
        end

        # Remove default attrs that are in the embedded
        default_attrs = default_attrs - embed_attrs.keys

        # Merge all embedded with the default (provided, all, default)
        default_attrs << embed_attrs if embed_attrs.length > 0
        default_attrs.uniq!

        # Filter out attributes that should not get loaded
        default_attrs = default_attrs - self.hypermedia_settings[:do_not_load]

        return default_attrs
      end

      ##
      # Compiles a list of aggregate-type attributes that need to be loaded for this request
      def self.goo_aggregates_to_load(attributes = [])
        included_aggregates = []
        return included_aggregates if attributes.empty?
        aggregates = self.hypermedia_settings[:aggregates].first
        aggregate_attribute, aggregate_syntax = aggregates.first
        included_aggregates = aggregate_syntax if attributes.delete(aggregate_attribute)
        included_aggregates
      end

      def self.replace_url_prefix_to_id(id)
        if replace_url_prefix?(id)
          id = RDF::IRI.new(id.to_s.sub(LinkedData.settings.rest_url_prefix, LinkedData.settings.id_url_prefix))
        end
        id
      end

      def self.replace_url_id_to_prefix(id)
        if replace_url_id?(id)
          id.to_s.gsub(LinkedData.settings.id_url_prefix, LinkedData.settings.rest_url_prefix)
        else
          id
        end
      end

      def self.replace_url_prefix?(id)
        LinkedData.settings.replace_url_prefix && id.to_s.start_with?(LinkedData.settings.rest_url_prefix)
      end

      def self.replace_url_id?(id)
        LinkedData.settings.replace_url_prefix && id.to_s.start_with?(LinkedData.settings.id_url_prefix)
      end

      private



      ##
      # Looks for an object 'owner' and looks in Thread.current[:remote_user]
      # to see if the user for this request matches the owner
      def write_permission_check(*args)
        # Don't prevent writes if creating a new object (anyone should be able to do this)
        return unless self.exist?

        if LinkedData.settings.enable_security
          user = nil
          options_hash = {}
          args.each { |e| options_hash.merge!(e) if e.is_a?(Hash) }
          user = options_hash[:user]

          # Allow a passed option to short-cut the security process
          return if options_hash[:override_security]

          user ||= Thread.current[:remote_user]

          reference_object = self

          # If we have a modified object, we should do the security check
          # on the original. This allows a user to change the ownsership of
          # an object without having to add the owner and have the new owner
          # remove the original owner.
          reference_object = self.class.find(self.id).first if self.modified?

          # Allow everyone to write
          return if reference_object.access_for_all?

          # Load attributes needed by security
          if reference_object.access_control_load?
            # Only load ones that aren't loaded so we don't overwrite changes
            not_loaded = []
            reference_object.access_control_load_attrs.each do |attr|
              not_loaded << attr unless reference_object.loaded_attributes.include?(attr)
            end
            reference_object.bring(*not_loaded) unless not_loaded.empty?
          end

          writable = reference_object.writable?(user)
          raise LinkedData::Security::WriteAccessDeniedError, "Write access denied: #{reference_object.id}" unless writable
        end
      end

    end
  end
end
