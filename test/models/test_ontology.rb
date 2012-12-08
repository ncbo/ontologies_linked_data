require_relative "../test_case"

class TestOntology < LinkedData::TestCase
  def setup
    @acronym = "SNOMED-TST"
    @name = "SNOMED-CT TEST"
  end

  def teardown
    o = LinkedData::Models::Ontology.find(@acronym)
    o.delete unless o.nil?
  end

  def test_valid_ontology
    o = LinkedData::Models::Ontology.new
    assert (not o.valid?)

    o.acronym = @acronym
    o.name = @name
    assert o.valid?
  end

  def test_ontology_lifecycle
    o = LinkedData::Models::Ontology.new({
        acronym: @acronym,
      })

    # Create
    assert_equal false, o.exist?(reload=true)
    o.save
    assert_equal true, o.exist?(reload=true)

    # Delete
    o.delete
    assert_equal false, o.exist?(reload=true)
  end
end
