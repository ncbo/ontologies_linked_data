require_relative "./test_ontology_common"
require "logger"

class TestClassModel < LinkedData::TestOntologyCommon

  def teardown
    @os = LinkedData::Models::OntologySubmission.find(@acr + '+' + 1.to_s)
    unless @os.nil?
      @os.ontology.load
      @os.ontology.delete
      @os.delete
    end
  end

  def setup
    @acr = "CSTPROPS"
    teardown
    init_test_ontology_msotest @acr
    @os = LinkedData::Models::OntologySubmission.find(@acr + '+' + 1.to_s)
  end

  def test_terms_custom_props
    return if ENV["SKIP_PARSING"]

    os_classes = @os.classes
    os_classes.each do |c|
      assert(!c.prefLabel.nil?, "Class #{c.resource_id.value} does not have a label")
    end
  end

  def test_parents
    return if ENV["SKIP_PARSING"]

    os_classes = @os.classes
    os_classes.each do |c|
#      binding.pry
    end
  end

end
