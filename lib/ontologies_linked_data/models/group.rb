module LinkedData
  module Models
    class Group < LinkedData::Models::Base
      attribute :acronym, :unique => true, :single_value => true, :not_nil => true
      attribute :name, :single_value => true, :not_nil => true
      attribute :description, :single_value => true, :not_nil => true
      attribute :created, :date_time_xsd => true, :single_value => true, :not_nil => true, :default => lambda { |record| DateTime.now }
    end
  end
end