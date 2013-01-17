module LinkedData
  module Models
    class Category < LinkedData::Models::Base
      model :category
      attribute :name, :unique => true, :not_nil => true
      attribute :created, :single_value => true, :default => lambda { |o| DateTime.now }
    end
  end
end
