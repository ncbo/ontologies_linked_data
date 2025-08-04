require 'date'

module LinkedData
  module Models
    class Review < LinkedData::Models::Base
      model :review, name_with: lambda { |inst| uuid_uri_generator(inst) }
      attribute :creator, enforce: [:user, :existence]
      attribute :created, enforce: [:date_time], :default => lambda {|x| DateTime.now}
      attribute :updated, enforce: [:date_time], :default => lambda {|x| DateTime.now}
      attribute :body, enforce: [:existence]
      attribute :ontologyReviewed, enforce: [:ontology, :existence]
      attribute :usabilityRating
      attribute :coverageRating
      attribute :qualityRating
      attribute :formalityRating
      attribute :correctnessRating
      attribute :documentationRating
    end
  end
end
