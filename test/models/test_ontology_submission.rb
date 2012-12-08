require_relative "../test_case"

class TestOntologySubmission < LinkedData::TestCase
  def setup
    @acronym = "SNOMED-TST"
    @name = "SNOMED-CT TEST"
    @repoPath = "some/input/repo/folder"
    @masterFileName = "snomed.owl"
    @id = 10
  end

  def teardown
    l = LinkedData::Models::OntologySubmission.where(:acronym => @acronym, :submissionId => @id)
    l.each do |o|
      os.delete
      o = os.ontology
      o.load
      o.delete
    end
  end

  def test_valid_ontology
    os = LinkedData::Models::OntologySubmission.new
    assert (not os.valid?)

    os.acronym = @acronym
    os.submissionId = @id
    os.name = @name
    o = LinkedData::Models::Ontology.find(@acronym)
    if o.nil?
      os.ontology = LinkedData::Models::Ontology.new(:acronym => @acronym)
    else
      os.ontology = o 
    end
    os.repoPath = @repoPath
    os.masterFileName = @masterFileName
    assert os.valid?
  end
end

