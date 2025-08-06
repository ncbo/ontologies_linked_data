module LinkedData
  module Hypermedia
    module Resource
      def self.store_settings(cls, type, setting)
        cls.hypermedia_settings ||= {}
        cls.hypermedia_settings[type] = setting
      end

      def self.included(base)
        base.extend(ClassMethods)
        ClassMethods::SETTINGS.each do |type|
          Resource.store_settings(base, type, [])
        end
      end

      module ClassMethods
        attr_accessor :hypermedia_settings

        def embedded?
          self.hypermedia_settings[:embedded].first
        end

        # Methods with these names will be created
        # for each entry, allowing values to be
        # stored on a per-class basis
        SETTINGS = [
          :embed,
          :embed_values,
          :embedded,
          :link_to,
          :links_load,
          :do_not_load,
          :aggregates,
          :serialize_default,
          :serialize_never,
          :serialize_methods,
          :serialize_filter,
          :prevent_serialize_when_nested,
          :system_controlled
        ]

        ##
        # Write methods on the class based on settings names
        SETTINGS.each do |method_name|
          define_method method_name do |*args|
            Resource.store_settings(self, method_name, args)
          end
        end

        ##
        # Gets called by each class that inherits from this module
        # or classes that include this module
        def inherited(cls)
          super(cls)
          SETTINGS.each do |type|
            Resource.store_settings(cls, type, [])
          end
        end
      end
    end
  end
end
