
module LinkedData
  module Models
    class Mapping
      include LinkedData::Hypermedia::Resource
      embed :classes, :process
      serialize_default :id, :source, :classes, :process

      def initialize(classes, source, process=nil, id=nil)
        @classes = classes
        @process = process
        @source = source
        @id = id
      end
      def classes
        return @classes
      end
      def process
        return @process
      end
      def source
        return @source
      end
      def id
        return @id
      end
      def self.type_uri
        LinkedData.settings.id_url_prefix+"metadata/Mapping"
      end
    end

    class RestBackupMapping < LinkedData::Models::Base
      model :rest_backup_mapping, name_with: :uuid
      attribute :uuid, enforce: [:existence, :unique]
      attribute :class_urns, enforce: [:uri, :existence, :list]
      attribute :process, enforce: [:existence, :mapping_process]
    end

    #only manual mappings
    class MappingProcess < LinkedData::Models::Base
          model :mapping_process,
                :name_with => lambda { |s| process_id_generator(s) }
          attribute :name, enforce: [:existence]
          attribute :creator, enforce: [:existence, :user]

          attribute :source
          attribute :relation, enforce: [:uri]
          attribute :source_contact_info
          attribute :source_name
          attribute :comment
          attribute :date, enforce: [:date_time],
                      :default => lambda {|x| DateTime.new }

          embedded true

          def self.process_id_generator(inst)
              return RDF::IRI.new(
        "#{(self.namespace)}mapping_processes/" +
        "-#{CGI.escape(inst.creator.username)}" +
        "-#{UUID.new.generate}")
          end
    end

    class MappingCount < LinkedData::Models::Base
      model :mapping_count, name_with: lambda { |x| mapping_count_id(x) }
      attribute :ontologies, enforce: [:existence, :list]
      attribute :count, enforce: [:existence, :integer]
      attribute :pair_count, enforce: [:existence, :boolean]
      def self.mapping_count_id(x)
        acrs = x.ontologies.sort.join("-")
        return RDF::URI.new(
          "#{(Goo.id_prefix)}mappingcount/#{CGI.escape(acrs)}"
        )
      end
    end
  end
end
