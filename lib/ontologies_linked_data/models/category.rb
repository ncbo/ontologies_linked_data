module LinkedData
  module Models
    class Category < LinkedData::Models::Base
      model :category, name_with: :acronym
      attribute :acronym, enforce: [:unique, :existence]
      attribute :name, enforce: [:existence]
      attribute :description
      attribute :created, enforce: [:date_time], default: lambda { |record| DateTime.now }
      attribute :parentCategory, enforce: [:category]
      attribute :ontologies, inverse: { on: :ontology, attribute: :hasDomain }

      system_controlled :created

      cache_timeout 86400
    end
  end
end
