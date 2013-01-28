require_relative "user"
require_relative "ontology"

module LinkedData
  module Models
    class Review < LinkedData::Models::Base
      model :review
      attribute :creator, :instance_of => { :with => :user }, :single_value => true, :not_nil => true
      attribute :created, :date_time_xsd => true, :single_value => true, :not_nil => true, :default => lambda { |record| DateTime.now }
      attribute :body, :cardinality => { :max => 1, :min => 1}
      attribute :ontologyReviewed, :instance_of => { :with => :ontology }, :single_value => true, :not_nil => true
      attribute :usabilityRating, :cardinality => { :max => 1 }
      attribute :coverageRating, :cardinality => { :max => 1 }
      attribute :qualityRating, :cardinality => { :max => 1 }
      attribute :formalityRating, :cardinality => { :max => 1 }
      attribute :documentationRating, :cardinality => { :max => 1 }
    end
  end
end