require_relative "ontology_submission"

module LinkedData
  module Models
    class OntologyContainer < LinkedData::Models::Base
      model :ontology
      attribute :acronym, :unique => true
      attribute :name, :not_nil => true, :single_value => true
      attribute :submissions,
                  :inverse_of => { :with => :ontology_submission,
                  :attribute => :ontology }

      def latest_submission
        OntologySubmission.where(acronym: @acronym, submissionId: highest_submission_id())
      end

      def next_submission_id
        (highest_submission_id || 0) + 1
      end

      def highest_submission_id
        submissions = self.submissions rescue nil
        submissions = OntologySubmission.where(acronym: @acronym) if submissions.nil?

        # This is the first!
        return 0 if submissions.nil? || submissions.empty?

        # Try to get a new one based on the old
        submission_ids = []
        submissions.each do |s|
          s.load unless s.loaded?
          submission_ids << s.submissionId.to_i
        end
        return submission_ids.max
      end

    end
  end
end
