require_relative "../test_case"

class TestSubmissionStatus < LinkedData::TestCase
  def setup
  end

  def teardown
    ofs = LinkedData::Models::SubmissionStatus.all
    ofs.each do |of|
      of.load
      of.delete
    end
  end
  
  def test_submission_status
    teardown
    LinkedData::Models::SubmissionStatus.init
    assert (LinkedData::Models::SubmissionStatus.all.length > 5)
  end

end
