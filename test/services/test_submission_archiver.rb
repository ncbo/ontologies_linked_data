require_relative '../test_case'

require 'logger'
require 'mocha/minitest'
require 'stringio'

class TestSubmissionArchiver < LinkedData::TestCase
  ARCHIVER = LinkedData::Services::OntologySubmissionArchiver

  def setup
    LinkedData::TestCase.backend_4s_delete
    _count, _acronyms, onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(
      ont_count: 1, submission_count: 2, acronym: 'ARCHTEST', process_submission: false
    )
    @old_sub = onts.first.submission(1)
    @old_sub.bring_remaining
    @original = @old_sub.uploadFilePath.to_s
    @threshold = ARCHIVER::FILE_SIZE_ZIPPING_THRESHOLD
    set_threshold(0)
  end

  def teardown
    LinkedData::Models::OntologySubmission.any_instance.unstub(:valid?)
    set_threshold(@threshold)
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def test_archiving_zips_the_upload_and_deletes_the_original
    archive(@old_sub)

    assert_equal "#{@original}.zip", stored_upload_path
    assert LinkedData::Utils::FileHelpers.zip?("#{@original}.zip")
    refute File.exist?(@original)
  end

  def test_a_submission_that_fails_to_save_keeps_its_original
    LinkedData::Models::OntologySubmission.any_instance.stubs(:valid?).returns(false)

    assert_raises(Goo::Base::NotValidException) { archive(@old_sub) }

    assert_equal @original, stored_upload_path
    assert File.file?(@original), 'the original is kept when the save fails'
    refute File.exist?("#{@original}.zip"), 'the zip of a submission that was not saved is removed'
  end

  def test_a_missing_original_with_its_zip_next_to_it_is_repointed
    LinkedData::Utils::FileHelpers.zip_file(@original)
    File.delete(@original)

    archive(@old_sub)

    assert_equal "#{@original}.zip", stored_upload_path
  end

  def test_a_missing_original_without_a_zip_still_archives
    File.delete(@original)

    archive(@old_sub)

    assert_equal @original, stored_upload_path
    assert LinkedData::Models::OntologySubmission.find(@old_sub.id).include(:submissionStatus).first.archived?
  end

  private

  def archive(sub)
    sub.process_submission(Logger.new(StringIO.new), { archive: true })
  end

  def stored_upload_path
    LinkedData::Models::OntologySubmission.find(@old_sub.id).include(:uploadFilePath).first.uploadFilePath.to_s
  end

  def set_threshold(bytes)
    verbose, $VERBOSE = $VERBOSE, nil
    ARCHIVER.const_set(:FILE_SIZE_ZIPPING_THRESHOLD, bytes)
  ensure
    $VERBOSE = verbose
  end
end
