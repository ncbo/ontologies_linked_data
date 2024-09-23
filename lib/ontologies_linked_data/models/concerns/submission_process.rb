module LinkedData
  module Concerns
    module SubmissionProcessable

      def process_submission(logger, options={})
        LinkedData::Services::OntologyProcessor.new(self).process(logger, options)
      end

      def diff(logger, older)
        LinkedData::Services::SubmissionDiffGenerator.new(self).diff(logger, older)
      end

      def generate_diff(logger)
        LinkedData::Services::SubmissionDiffGenerator.new(self).process(logger)
      end

      def index(logger, commit: true, optimize: true)
        LinkedData::Services::OntologySubmissionIndexer.new(self).process(logger, commit: commit, optimize: optimize)
      end

      def index_properties(logger, commit: true, optimize: true)
        LinkedData::Services::SubmissionPropertiesIndexer.new(self).process(logger, commit: commit, optimize: optimize)
      end

      def archive
        LinkedData::Services::OntologySubmissionArchiver.new(self ).process
      end

      def generate_rdf(logger, reasoning: true)
        LinkedData::Services::SubmissionRDFGenerator.new(self).process(logger, reasoning: reasoning)
      end

      def generate_metrics(logger)
        LinkedData::Services::SubmissionMetricsCalculator.new(self).process(logger)
      end

    end
  end
end

