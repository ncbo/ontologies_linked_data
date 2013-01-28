module LinkedData
  module Models
    class Project < LinkedData::Models::Base
      model :project
      attribute :creator, :instance_of => { :with => :user }, :single_value => true, :not_nil => true
      attribute :created, :date_time_xsd => true, :single_value => true, :not_nil => true, :default => lambda {|x| DateTime.new }
      attribute :name, :unique => true, :single_value => true, :not_nil => true
      attribute :homePage, :uri => true, :single_value => true, :not_nil => true
      attribute :description, :single_value => true, :not_nil => true
      attribute :contacts, :cardinality => { :max => 1 }
      attribute :ontologyUsed, :instance_of => { :with => :ontology }
    end
  end
end

