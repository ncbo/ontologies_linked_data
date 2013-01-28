require_relative "../test_case"

class TestCategory < LinkedData::TestCase
  def setup
    _delete
    @category = LinkedData::Models::Category.new({
        :name => "Test Category",
        :description => "This is a test category",
        :acronym => "TCG"
      })
    @category.save
  end

  def teardown
    super
    _delete
  end

  def _delete
    category = LinkedData::Models::Category.find("TCG")
    category.delete unless category.nil?
  end

  def test_valid_category
    _delete

    c = LinkedData::Models::Category.new
    assert (not c.valid?)

    # Not valid because not all attributes are present
    c.name = "Test Category"
    c.created = DateTime.parse("2012-10-04T07:00:00.000Z")
    assert (not c.valid?)

    # All attributes now present, should be valid
    c.acronym = "TCG"
    c.description = "Test category description"
    assert c.valid?
  end

  def test_no_duplicate_category_ids
    c2 = LinkedData::Models::Category.new({
        :created => DateTime.parse("2012-10-04T07:00:00.000Z"),
        :name => "Test Category",
        :description => "This is a test category",
        :acronym => "TCG"
      })

    assert (not c2.valid?)
  end

  def test_category_lifecycle
    c = LinkedData::Models::Category.new({
        :created => DateTime.parse("2012-10-04T07:00:00.000Z"),
        :name => "Test Category",
        :description => "This is a test category",
        :acronym => "TCG1"
      })

    assert_equal false, c.exist?(reload=true)
    c.save
    assert_equal true, c.exist?(reload=true)
    c.delete
    assert_equal false, c.exist?(reload=true)
  end

  def test_category_default_datetime
    c = LinkedData::Models::Category.new
    assert c.created.instance_of? DateTime
  end

  def test_category_inverse_of
    delete_ontologies_and_submissions
    ont_count, ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1)
    ont = onts.first
    ont.hasDomain = @category
    ont.save

    category_ont = @category.ontologies.first
    category_ont.load

    assert_equal category_ont.acronym, ont.acronym
  end

end