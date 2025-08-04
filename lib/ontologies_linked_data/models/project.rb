module LinkedData
  module Models
    class Project < LinkedData::Models::Base
      model :project, :name_with => :acronym
      attribute :acronym, enforce: [:unique, :existence]
      attribute :creator, enforce: [:existence, :user, :list]
      attribute :created, enforce: [:date_time], :default => lambda {|x| DateTime.now }
      attribute :updated, enforce: [:date_time], :default => lambda {|x| DateTime.now }
      attribute :name, enforce: [:existence]
      attribute :homePage, enforce: [:uri, :existence]
      attribute :description, enforce: [:existence]
      attribute :contacts
      attribute :institution
      attribute :ontologyUsed, enforce: [:ontology, :list]

      system_controlled :creator, :created
    end
  end
end

