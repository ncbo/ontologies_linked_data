module LinkedData
  module Models
    class Category < LinkedData::Models::Base
      model :category
      attribute :acronym, :unique => true, :single_value => true, :not_nil => true
      attribute :name, :single_value => true, :not_nil => true
      attribute :description, :single_value => true, :not_nil => true
      attribute :created, :date_time_xsd => true, :single_value => true, :not_nil => true, :default => lambda { |record| DateTime.now }
      attribute :parentCategory, :instance_of => { :with => :category }
      attribute :ontologies, :inverse_of => { :with => :ontology, :attribute => :hasDomain }
    end
  end
end