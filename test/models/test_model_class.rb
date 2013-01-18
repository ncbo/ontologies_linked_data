require_relative "./test_ontology_common"
require "logger"

class TestClassModel < LinkedData::TestOntologyCommon

  def myteardown
    return

    @os = LinkedData::Models::OntologySubmission.find(@acr + '+' + 1.to_s)
    unless @os.nil?
      @os.ontology.load
      @os.ontology.delete
      @os.delete
    end
  end

  def mysetup

    @acr = "CSTPROPS"
    @os = LinkedData::Models::OntologySubmission.find(@acr + '+' + 1.to_s)
    return

    @acr = "CSTPROPS"
    teardown
    init_test_ontology_msotest @acr
    @os = LinkedData::Models::OntologySubmission.find(@acr + '+' + 1.to_s)
  end

  def test_terms_custom_props
    return if ENV["SKIP_PARSING"]
    mysetup

    begin
      os_classes = @os.classes
      os_classes.each do |c|
        assert(!c.prefLabel.nil?, "Class #{c.id.value} does not have a label")
      end
    rescue => e
      myteardown
      raise e
    end
    myteardown

  end

  def test_parents
    return if ENV["SKIP_PARSING"]
    mysetup

    os_classes = @os.classes
    os_classes.each do |c|
      assert(!c.prefLabel.nil?, "Class #{c.id.value} does not have a label")
    end

    begin
      os_classes = @os.classes
    rescue => e
      myteardown
      raise e
    end
    myteardown
  end

end
