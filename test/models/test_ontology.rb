require_relative "../test_case"
require 'pry'

class TestOntology < LinkedData::TestCase
  def setup
    @acronym = "SNOMED-TST"
    @name = "SNOMED-CT TEST"
    teardown
    _delete_ontology_objects
  end

  def teardown
    _delete_ontology_objects
  end

  def test_valid_ontology
    o = LinkedData::Models::Ontology.new
    assert (not o.valid?)

    u = LinkedData::Models::User.new(username: "tim")
    u.save

    of = LinkedData::Models::OntologyFormat.new(acronym: "OWL")
    of.save

    o.acronym = @acronym
    o.name = @name
    o.ontologyFormat = of
    o.administeredBy = u
    o.status = LinkedData::Models::SubmissionStatus.new(:code => "UPLOADED")
    o.pullLocation = RDF::IRI.new("http://example.com")
    assert o.valid?
  end

  def test_ontology_lifecycle
    u = LinkedData::Models::User.new(username: "tim")
    u.save

    of = LinkedData::Models::OntologyFormat.new(acronym: "OWL")
    of.save

    o = LinkedData::Models::Ontology.new({
      acronym: @acronym,
      name: @name,
      ontologyFormat: of,
      administeredBy: u,
      pullLocation: RDF::IRI.new("http://example.com"),
      status: LinkedData::Models::SubmissionStatus.new(:code => "UPLOADED"),
    })

    # Create
    assert_equal false, o.exist?(reload=true)
    o.save
    assert_equal true, o.exist?(reload=true)

    # Delete
    o.delete
    assert_equal false, o.exist?(reload=true)
  end

  def test_next_submission_id
    _create_ontology
    assert LinkedData::Models::Ontology.find(@acronym).next_submission_id == 2
  end

  def test_ontology_deletes_submissions
    _create_ontology
    ont = LinkedData::Models::Ontology.find(@acronym)
    ont.delete
    submissions = LinkedData::Models::OntologySubmission.where(acronym: @acronym)
    assert submissions.empty?
  end

end
