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

  # Regression test for the misleading log line:
  #   "Email sending failed: undefined method `archived?' for nil:NilClass"
  #
  # When SubmissionMetadataExtractor#extract_metadata bails on an invalid submission it
  # returns nil, and OntologyProcessor#process_submission reassigns @submission to that
  # nil. Two invariants must hold:
  #   1. processing aborts with a clear StandardError (not a NoMethodError on nil), and
  #   2. notify_submission_processed (run from the ensure block) skips cleanly on a nil
  #      submission instead of logging the misleading "Email sending failed" line above.
  def test_processor_aborts_cleanly_when_extract_metadata_returns_nil
    log_io = StringIO.new
    logger = Logger.new(log_io)

    submission = @@ont.latest_submission(status: :any)
    submission.bring_remaining

    # Simulate extract_metadata bailing on an invalid submission.
    submission.stubs(:extract_metadata).returns(nil)

    # Disable every other step so the test isolates the extract_metadata → notify path.
    options = {
      process_rdf: false, generate_missing_labels: false, generate_obsolete_classes: false,
      index_search: false, index_properties: false, index_all_data: false,
      run_metrics: false, diff: false, archive: false
    }

    error = assert_raises(StandardError) do
      submission.process_submission(logger, options)
    end

    refute_instance_of NoMethodError, error,
                       'processor crashed on a nil @submission instead of aborting cleanly'
    assert_match(/aborted/i, error.message,
                 'processor should abort with a clear message when extract_metadata returns nil')

    refute_match(/Email sending failed/, log_io.string,
                 'notify_submission_processed logged a misleading "Email sending failed" on a nil submission')
  end
end
