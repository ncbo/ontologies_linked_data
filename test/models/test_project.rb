require_relative "../test_case"
require 'json-schema'

class TestProject < LinkedData::TestCase

  def setup
    super
    teardown
    # Create and save a valid user
    @user = LinkedData::Models::User.new
    @user.username = "test_user"
    @user.save
    # Create and save a valid ontology
    @ont = LinkedData::Models::Ontology.new
    @ont.acronym = "TST_ONT"
    @ont.name = "Test Ontology"
    @ont.administeredBy = @user
    @ont.save
    # Create a valid project (don't save it here).
    @p = LinkedData::Models::Project.new
    @p.name = "Great Project"
    @p.creator = @user
    # Created value has a default that is set during @p.save
    #@p.created = DateTime.new
    @p.homePage = "http://valid.uri.com"
    @p.description = "This is a test project"
    @p.ontologyUsed = [@ont]
  end

  def teardown
    super
    delete(LinkedData::Models::User.all)
    delete(LinkedData::Models::Ontology.all)
    delete(LinkedData::Models::Project.all)
    @user = nil
    @ont = nil
    @p = nil
  end

  def delete(modelList)
    modelList.each do |x|
      x.load
      x.delete
    end
  end

  def test_project_name
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    ## In goo, the name is prefixed with a URI namespace.
    ## name should be a valid URI, this is not:
    #p.name = "test name"
    #assert (not p.valid?) # Other attributes generate errors
    #assert_equal(false, p.errors[:name].nil?)
    # name should be a valid URI, this should be:
    p.name = "test_name"
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:name].nil?)
  end

  def test_project_creator
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    p.creator = "test name"
    assert (not p.valid?)
    assert_equal(false, p.errors[:creator].nil?)
    p.creator = @user
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:creator].nil?)
  end

  def test_project_created
    # The default value is auto-generated, it should be OK.
    @p.save if @p.valid?
    assert_instance_of(DateTime, @p.created)
    assert_equal(true, @p.errors[:created].nil?)
    @p.created = "this string should fail"
    assert (not @p.valid?)
    assert_equal(false, @p.errors[:created].nil?)
    # The value should be an XSD date time.
    @p.created = DateTime.new
    assert @p.valid?
    assert_instance_of(DateTime, @p.created)
    assert_equal(true, @p.errors[:created].nil?)
  end

  def test_project_homePage
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    ## This should be a valid URI, this is not:
    #p.homePage = "test homePage"
    #assert (not p.valid?) # Other attributes generate errors
    #assert_equal(false, p.errors[:homePage].nil?)
    # homePage should be a valid URI, this should be:
    p.homePage = "http://bioportal.bioontology.org"
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:homePage].nil?)
  end

  def test_project_description
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    # This should be a string.
    p.description = "test description"
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:description].nil?)
  end

  def test_project_ontologyUsed
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    p.ontologyUsed = "this string will fail"
    assert (not p.valid?)
    assert_equal(false, p.errors[:ontologyUsed].nil?)
    p.ontologyUsed = @ont
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:ontologyUsed].nil?)
  end

  def test_valid_project
    # The setup project should be valid
    assert @p.valid?
    # Incrementally evaluate project validity...
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    # Not valid because not all attributes are present...
    p.name = "Great Project"
    p.created = DateTime.parse("2012-10-04T07:00:00.000Z")
    p.homePage = "http://valid.uri.com"
    p.description = "This is a test project"
    assert (not p.valid?)
    # Still not valid because not all attributes are typed properly...
    p.creator = "test_user" # must be LinkedData::Model::User
    assert (not p.valid?)
    p.ontologyUsed = "TEST_ONT" # must be array of LinkedData::Model::Ontology
    assert (not p.valid?)
    # Complete valid project...
    p.creator = @user
    p.ontologyUsed = [@ont,]
    assert p.valid?
  end

  def test_project_default_datetime
    p = LinkedData::Models::Project.new
    assert p.created.instance_of? DateTime
  end

  def test_project_save
    assert_equal false, @p.exist?(reload=true)
    @p.save
    assert_equal true, @p.exist?(reload=true)
    @p.delete
    assert_equal false, @p.exist?(reload=true)
  end

  def test_project_json
    # TODO: Resolve how to get the project model serialized into json format.
    assert true
    return
    # A placeholder to test the serialization of a project in json format
    # Validate the json against a schema, body contains a list of projects
    schema = JSON.parse(LinkedData::Models::Project::JSON_SCHEMA_STR)
    @p.save unless @p.exist?(reload=true)
    project_json = @p.to_json
    assert(
        JSON::Validator.validate(schema, project_json, :validate_schema => true),
        JSON::Validator.fully_validate(schema, project_json, :validate_schema => true).to_s
    )
  end
end
