require_relative "./test_ontology_common"
require "logger"

class TestClassModel < LinkedData::TestOntologyCommon

  def setup
  end

  def test_terms_custom_props
    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.find(acr + '+' + 1.to_s)
    os_classes = os.classes
    os_classes.each do |c|
      assert (not c.prefLabel.nil?)
    end
    os.ontology.load
    os.ontology.delete
    os.delete
  end
end
