module LinkedData
  module Models
    class Ontology < LinkedData::Models::Base
      model :ontology
      attribute :acronym, :unique => true
      attribute :name, :not_nil => true, :single_value => true
      attribute :submissions,
                  :inverse_of => { :with => :ontology_submission,
                  :attribute => :ontology }

      def next_submission_id
        submissions = self.submissions
        submissions = OntologySubmission.where(acronym: self.acronym) if submissions.nil?

        # This is the first!
        return 1 if submissions.nil? || submissions.empty?

        # Try to get a new one based on the old
        submission_ids = []
        submissions.each do |s|
          s.load unless s.loaded?
          submission_ids << s.submissionId.to_i
        end
        return submission_ids.max + 1
      end

      def delete(in_update=false)
        submissions = OntologySubmission.where(acronym: self.acronym)
        submissions.each {|s| s.delete(in_update) unless s.nil?}
        super()
      end
    end
  end
end
