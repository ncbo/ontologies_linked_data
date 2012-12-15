require_relative "../test_case"

class TestSubmissionStatus < LinkedData::TestCase
  def setup
    @codes = ["OBO", "OWL"]
  end

  def teardown
    ofs = LinkedData::Models::SubmissionStatus.all
    ofs.each do |of|
      of.load
      of.delete
    end
  end
  
  def test_formats
    teardown
    @codes.each do |code|
      of =  LinkedData::Models::SubmissionStatus.new( { :code => code } )
      of.save
    end
    @codes.each do |code|
      list =  LinkedData::Models::SubmissionStatus.where( :code => code )
      assert_equal 1, list.length
      assert_instance_of LinkedData::Models::SubmissionStatus, list[0]
      list[0].load
      assert_equal code, list[0].code
    end
  end

  def test_init
     teardown
     assert_equal 0, LinkedData::Models::SubmissionStatus.all.length
     LinkedData::Models::SubmissionStatus.init @codes
     assert_equal 2, LinkedData::Models::SubmissionStatus.all.length
  end

end
