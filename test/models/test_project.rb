require_relative "../test_case"

class TestProject < LinkedData::TestCase

  def self.before_suite
    self.new("before_suite").teardown
  end

  def self.after_suite
    self.new("after_suite").teardown
  end

  def setup
    super
    @user = LinkedData::Models::User.new({:username => "test_user", :email => "test_user@example.org", :password => "password"})
    @user.save
    @ont = LinkedData::Models::Ontology.new({:acronym => "TST_ONT", :name => "Test Ontology", :administeredBy => [@user]})
    @ont.save
    # Create valid project parameters
    @project_params = {
      :name => "Great Project",
      :acronym => "GP",
      :creator => [@user],
      :created => DateTime.now,
      :institution => "A university.",
      :contacts => "Anonymous Funk, Anonymous Miller.",
      :homePage => RDF::IRI.new("http://valid.uri.com"),
      :description => "This is a test project",
      :ontologyUsed => [@ont],
    }
  end

  def teardown
    super
    delete_goo_models(LinkedData::Models::Ontology.where.all)
    delete_goo_models(LinkedData::Models::Project.where.all)
    delete_goo_models(LinkedData::Models::User.where.all)
    @ont = nil
    @project_params = nil
    @user = nil
  end

  def test_project_acronym
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    # name should be a valid URI, this should be:
    p.acronym = @project_params[:acronym]
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:acronym].nil?)
  end

  def test_project_contacts
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    # This should be a string.
    p.contacts = @project_params[:contacts]
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:contacts].nil?)
  end

  def test_project_created
    # Ensure there is no 'created' parameter so the model creates a default value.
    @project_params.delete :created
    model_created_test(LinkedData::Models::Project.new(@project_params)) # method from test_case.rb
  end

  def test_project_creator
    model_creator_test(LinkedData::Models::Project.new(acronym: "TST_PRJ"), @user)
  end

  def test_project_creator_multiple
    p = LinkedData::Models::Project.new

    # Missing attributes.
    assert_equal(false, p.valid?, p.errors)

    # Required attributes present.
    p.name = @project_params[:name]
    p.acronym = @project_params[:acronym]
    p.description = @project_params[:description]
    p.creator = @project_params[:creator]
    p.homePage = @project_params[:homePage]
    assert p.valid?, p.errors

    # Creator attribute not a list.
    p.creator = @user
    assert_equal(false, p.valid?, p.errors)

    # Creator attribute is a list.
    users = Array.new(3) { LinkedData::Models::User.new }
    users.each_with_index do |user, i|
      user.username = "Test User #{i}"
      user.email = "test_user#{i}@example.org"
      user.password = 'password'
      user.save
      assert user.valid?, user.errors
    end
    p.creator = users
    assert p.valid?, p.errors

    # Proper number of creators.
    p.save
    p1 = LinkedData::Models::Project.where(creator: [username: 'Test User 0']).first
    p1.bring(creator: [:username])
    assert_equal(3, p1.creator.length)

    # Proper list of users in creator attribute.
    creators = p1.creator.sort { |a,b| a.username <=> b.username }
    creators.zip(users).map { |x,y| assert x.id == y.id }
  end

  def test_project_description
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    # This should be a string.
    p.description = @project_params[:description]
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:description].nil?)
  end

  def test_project_homePage
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    # This should be a valid URI, this is not:
    p.homePage = "test homePage"
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(false, p.errors[:homePage].nil?)
    # homePage should be a valid URI, this should be:
    p.homePage = @project_params[:homePage]
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:homePage].nil?)
  end

  def test_project_institution
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    # This should be a string.
    p.institution = @project_params[:institution]
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:institution].nil?)
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

  def test_project_ontologyUsed
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    p.ontologyUsed = "this string will fail"
    assert (not p.valid?)
    assert_equal(false, p.errors[:ontologyUsed].nil?)
    p.ontologyUsed = @project_params[:ontologyUsed]
    assert (not p.valid?) # Other attributes generate errors
    assert_equal(true, p.errors[:ontologyUsed].nil?)
  end

  def test_valid_project
    # The setup project parameters should be valid
    p = LinkedData::Models::Project.new(@project_params)
    assert_equal(true, p.valid?, "Invalid project parameters: #{p.errors}")
    # Incrementally evaluate project validity...
    p = LinkedData::Models::Project.new
    assert (not p.valid?)
    # Not valid because not all attributes are present...
    p.name = @project_params[:name]
    p.acronym = @project_params[:acronym]
    p.created = @project_params[:created]
    p.homePage = @project_params[:homePage]
    p.description = @project_params[:description]
    p.institution = @project_params[:institution]
    assert (not p.valid?)
    # Still not valid because not all attributes are typed properly...
    p.creator = "test_user" # must be LinkedData::Model::User
    assert (not p.valid?)
    p.ontologyUsed = "TEST_ONT" # must be array of LinkedData::Model::Ontology
    assert (not p.valid?)
    # Complete valid project...
    p.creator = @project_params[:creator]
    p.ontologyUsed = @project_params[:ontologyUsed]
    assert p.valid?

    p.name = "Global Collaborative Project for the Standardization, Harmonization, and Federated Analysis of Longitudinal Multi-Center Patient Health Records, Genomic Sequencing Data, and Real-World Evidence to Accelerate Discovery and Deployment of AI-Driven Clinical Decision Support Systems and Therapeutic Innovations"
    refute p.valid?

    p.name = "Valid name"
    p.contacts = "Evil contacts text\u202Eevil.com"
    refute p.valid?

    p.contacts = "Good contacts"
    assert p.valid?
  end

  def test_project_lifecycle
    model_lifecycle_test(LinkedData::Models::Project.new(@project_params))
  end

end
