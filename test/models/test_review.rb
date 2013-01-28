require_relative "../test_case"

class TestReview < LinkedData::TestCase
  def test_valid_review
    r = LinkedData::Models::Review.new
    assert (not r.valid?)

    # Not valid because not all attributes are present
    r.body = "This is a test review"
    r.created = DateTime.parse("2012-10-04T07:00:00.000Z")
    assert (not r.valid?)

    # Still not valid because not all attributes are typed properly
    r.creator = "paul"
    r.ontologyReviewed = "SNOMED"
    assert (not r.valid?)

    # Fix typing
    r.creator = LinkedData::Models::User.new(username: "paul")
    r.ontologyReviewed = LinkedData::Models::Ontology.new(acronym: "SNOMED", name: "SNOMED CT")
    assert r.valid?
  end

  def test_review_lifecycle
    r = LinkedData::Models::Review.new({
        :creator => LinkedData::Models::User.new(username: "paul"),
        :created => DateTime.parse("2012-10-04T07:00:00.000Z"),
        :body => "This is a test review",
        :ontologyReviewed => LinkedData::Models::Ontology.new(acronym: "SNOMED", name: "SNOMED CT")
      })

    assert_equal false, r.exist?(reload=true)
    r.save
    assert_equal true, r.exist?(reload=true)
    r.delete
    assert_equal false, r.exist?(reload=true)
  end

  def test_review_default_datetime
    r = LinkedData::Models::Review.new
    assert r.created.instance_of? DateTime
  end
end