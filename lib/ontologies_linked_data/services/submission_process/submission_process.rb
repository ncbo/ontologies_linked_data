module LinkedData
  module Services
    class OntologySubmissionProcess

      def initialize(submission)
        @submission = submission
      end

      def process(logger, options = {})
        raise NotImplementedError
      end
    end
  end
end
