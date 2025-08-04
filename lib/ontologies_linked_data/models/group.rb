module LinkedData
  module Models
    class Group < LinkedData::Models::Base
      model :group, name_with: :acronym
      attribute :acronym, enforce: [:unique, :existence]
      attribute :name, enforce: [:existence]
      attribute :description
      attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
      attribute :ontologies, inverse: { on: :ontology, attribute: :group }

      serialize_default :acronym, :name, :description, :created, :ontologies
      system_controlled :created

      cache_timeout 86400
    end
  end
end
