require_relative "../test_case"

class TestCategory < LinkedData::TestCase


  def teardown
    categories = LinkedData::Models::Category.all
    categories.each do |c|
      c.load
      c.delete
    end
  end

  def setup
    teardown
    @cat_names = ["genome", "anatomy"]
    @cat_names.each do |name|
      cat = LinkedData::Models::Category.new
      cat.name = name
      cat.save
    end

  end

  def test_category_names

    categories = LinkedData::Models::Category.all
    assert_equal(categories.length, @cat_names.length)

    categories.each do |cat|
      cat.load
      assert_instance_of String, cat.name
      assert (@cat_names.include? cat.name)
      assert_instance_of DateTime, cat.created
      assert(cat.created < DateTime.now)
    end

  end
end






