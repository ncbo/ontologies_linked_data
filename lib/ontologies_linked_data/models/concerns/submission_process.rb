module LinkedData
  module Concerns
    module SubmissionProcessable

      def process_submission(logger, options = {})
        LinkedData::Services::OntologyProcessor.new(self).process(logger, options)
      end

      def generate_missing_labels(logger)
        LinkedData::Services::GenerateMissingLabels.new(self).process(logger, file_path: self.master_file_path)
      end

      def generate_obsolete_classes(logger)
        LinkedData::Services::ObsoleteClassesGenerator.new(self).process(logger, file_path: self.master_file_path)
      end

      def extract_metadata(logger, options = {})
        LinkedData::Services::SubmissionMetadataExtractor.new(self).process(logger, options)
      end

      def diff(logger, older)
        LinkedData::Services::SubmissionDiffGenerator.new(self).diff(logger, older)
      end

      def generate_diff(logger)
        LinkedData::Services::SubmissionDiffGenerator.new(self).process(logger)
      end

      def index_all(logger, commit: true)
        LinkedData::Services::OntologySubmissionAllDataIndexer.new(self).process(logger, commit: commit)
      end

      def index_terms(logger, commit: true, optimize: true)
        LinkedData::Services::OntologySubmissionIndexer.new(self).process(logger, commit: commit, optimize: optimize)
      end

      def index_properties(logger, commit: true, optimize: true)
        LinkedData::Services::SubmissionPropertiesIndexer.new(self).process(logger, commit: commit, optimize: optimize)
      end

      def archive(force: false)
        LinkedData::Services::OntologySubmissionArchiver.new(self).process(force: force)
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