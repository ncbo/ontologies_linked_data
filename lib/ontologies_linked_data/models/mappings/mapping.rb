module LinkedData
  module Models
    class Mapping
      include LinkedData::Hypermedia::Resource
      embed :classes, :process
      serialize_default :id, :source, :classes, :process
      attr_reader :id, :source, :classes, :process

      def initialize(classes, source, process = nil, id = nil)
        @classes = classes
        @process = process
        @source = source
        @id = id
      end

      def self.type_uri
        "#{LinkedData.settings.id_url_prefix}metadata/Mapping"
      end
    end

    class RestBackupMapping < LinkedData::Models::Base
      include LinkedData::HTTPCache::CacheableResource
      cache_timeout 3600
      model :rest_backup_mapping, name_with: :uuid
      attribute :uuid, enforce: %i[existence unique]
      attribute :class_urns, enforce: [:uri, :existence, :list, ->(inst, attr) { validate_size(inst, attr) }]
      attribute :process, enforce: %i[existence mapping_process]

      def self.validate_size(inst, attr)
        inst.bring(attr) if inst.bring?(attr)
        value = inst.send(attr)

        unless value.is_a?(Array) && value.length >= 2
          return [:relation_value_validator, 'does not contain at least 2 terms']
        end

        [:relation_value_validator, nil]
      end
    end

    #only manual mappings
    class MappingProcess < LinkedData::Models::Base
      model :mapping_process,
            name_with: ->(s) { process_id_generator(s) }
      attribute :name, enforce: [:existence]
      attribute :creator, enforce: %i[existence user]

      attribute :source
      attribute :relation, enforce: [:uri, :existence, :list, ->(inst, attr) { validate_size(inst, attr) }]
      attribute :source_contact_info
      attribute :source_name
      attribute :comment
      attribute :date, enforce: [:date_time], default: ->(x) { DateTime.now }
      attribute :subject_source_id, enforce: [:uri]
      attribute :object_source_id, enforce: [:uri]

      embedded true

      def self.validate_size(inst, attr)
        inst.bring(attr) if inst.bring?(attr)
        value = inst.send(attr)

        if value.is_a?(Array) && value.size > 5
          return [:relation_value_validator, 'contains too many mapping relations (max 5)']
        end

        [:relation_value_validator, nil]
      end

      def self.process_id_generator(inst)
        RDF::IRI.new(
          "#{(self.namespace)}mapping_processes/" \
            "-#{CGI.escape(inst.creator.username)}" \
            "-#{UUID.new.generate}"
        )
      end
    end

    class MappingCount < LinkedData::Models::Base
      model :mapping_count, name_with: ->(x) { mapping_count_id(x) }
      attribute :ontologies, enforce: %i[existence list]
      attribute :count, enforce: %i[existence integer]
      attribute :pair_count, enforce: %i[existence boolean]

      def self.mapping_count_id(x)
        acrs = x.ontologies.sort.join('-')
        RDF::URI.new(
          "#{(Goo.id_prefix)}mappingcount/#{CGI.escape(acrs)}"
        )
      end
    end
  end
end
