require_relative '../test_case'

require 'logger'
require 'mocha/minitest'
require 'stringio'

class TestSubmissionProcessor < LinkedData::TestCase

  def self.before_suite
    LinkedData::TestCase.backend_4s_delete
    _count, _acronyms, onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(
      ont_count: 1, submission_count: 1, acronym: 'PROCTEST', process_submission: false
    )
    @@ont = onts.first
  end

  def self.after_suite
    @@ont&.delete
    LinkedData::TestCase.backend_4s_delete
  end

  # Regression test for:
  #   "Email sending failed: undefined method `archived?' for nil:NilClass"
  #
  # When SubmissionMetadataExtractor#extract_metadata hit the `unless @submission.valid?`
  # branch it used a bare `return` (returns nil). OntologyProcessor#process_submission
  # reassigned @submission to that nil, and the ensure-block call to
  # notify_submission_processed then raised NoMethodError on nil.archived?, which its
  # inner rescue logged as the misleading "Email sending failed" line above.
  def test_processor_survives_extract_metadata_returning_nil
    log_io = StringIO.new
    logger = Logger.new(log_io)

    submission = @@ont.latest_submission(status: :any)
    submission.bring_remaining

    # Simulate the pre-fix extractor behavior on an invalid submission.
    submission.stubs(:extract_metadata).returns(nil)

    # Disable every other step so the test isolates the extract_metadata → notify path.
    options = {
      process_rdf: false, generate_missing_labels: false, generate_obsolete_classes: false,
      index_search: false, index_properties: false, index_all_data: false,
      run_metrics: false, diff: false, archive: false
    }

    begin
      submission.process_submission(logger, options)
    rescue NoMethodError => e
      flunk "processor raised NoMethodError because @submission was overwritten with nil: #{e.message}"
    end

    refute_match(/Email sending failed/, log_io.string,
                 'notify_submission_processed logged a misleading "Email sending failed" on a nil submission')
  end
end
