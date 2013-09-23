# Start simplecov if this is a coverage task
if ENV["COVERAGE"].eql?("true")
  require 'simplecov'
  SimpleCov.start do
    add_filter "/test/"
    add_filter "app.rb"
    add_filter "init.rb"
    add_filter "/config/"
  end
end

require_relative "../lib/ontologies_linked_data"
require_relative "../config/config.rb"

require 'minitest/unit'
MiniTest::Unit.autorun

# Check to make sure you want to run if not pointed at localhost
safe_hosts = Regexp.new(/localhost|ncbo-dev*|ncbo-stg-app-22*/)
def safe_redis_hosts?(sh)
  return [LinkedData.settings.http_redis_host,
   LinkedData.settings.goo_redis_host].select { |x|
    x.match(sh)
  }.length == 2
end
unless LinkedData.settings.goo_host.match(safe_hosts) &&
        LinkedData.settings.search_server_url.match(safe_hosts) &&
        safe_redis_hosts?(safe_hosts)
  print "\n\n================================== WARNING ==================================\n"
  print "** TESTS CAN BE DESTRUCTIVE -- YOU ARE POINTING TO A POTENTIAL PRODUCTION/STAGE SERVER **\n"
  print "Servers:\n"
  print "triplestore -- #{LinkedData.settings.goo_host}\n"
  print "search -- #{LinkedData.settings.search_server_url}\n"
  print "redis http -- #{LinkedData.settings.http_redis_host}:#{LinkedData.settings.http_redis_port}\n"
  print "redis goo -- #{LinkedData.settings.goo_redis_host}:#{LinkedData.settings.goo_redis_port}\n"
  print "Type 'y' to continue: "
  $stdout.flush
  confirm = $stdin.gets
  if !(confirm.strip == 'y')
    abort("Canceling tests...\n\n")
  end
  print "Running tests..."
  $stdout.flush
end

module LinkedData
  class Unit < MiniTest::Unit
    def before_suites
      # code to run before the first test (gets inherited in sub-tests)
    end

    def after_suites
      # code to run after the last test (gets inherited in sub-tests)
    end

    def _run_suites(suites, type)
      begin
        before_suites
        super(suites, type)
      ensure
        after_suites
      end
    end

    def _run_suite(suite, type)
      begin
        suite.before_suite if suite.respond_to?(:before_suite)
        super(suite, type)
      ensure
        suite.after_suite if suite.respond_to?(:after_suite)
      end
    end
  end

  MiniTest::Unit.runner = LinkedData::Unit.new

  class TestCase < MiniTest::Unit::TestCase
    def submission_dependent_objects(format, acronym, user_name)
      #ontology format
      owl = LinkedData::Models::OntologyFormat.where(:acronym => format).first
      assert_instance_of LinkedData::Models::OntologyFormat, owl

      #ontology
      users = LinkedData::Models::User.where(:username => user_name).all
      user = users.first

      if user.nil?
        user = LinkedData::Models::User.new({:username => user_name})
        user.email = "a@example.org"
        user.passwordHash = "XXXXX"
        user.save
      end

      ont = LinkedData::Models::Ontology.where(:acronym => acronym).all
      ont = ont.first

      if ont.nil?
        ont = LinkedData::Models::Ontology.new({:acronym => acronym})
        ont.name = "some name for #{acronym}"
        ont.administeredBy = [user]
        ont.save
      end
      contact = LinkedData::Models::Contact.new
      contact.email = "xxx@example.org"
      contact.name  = "some name"
      contact.save
      return owl, ont, user, contact
    end

    ##
    # Creates a set of Ontology and OntologySubmission objects and stores them in the triplestore
    # @param [Hash] options the options to create ontologies with
    # @option options [Fixnum] :ont_count Number of ontologies to create
    # @option options [Fixnum] :submission_count How many submissions each ontology should have (acts as max number when random submission count is used)
    # @option options [TrueClass, FalseClass] :random_submission_count Use a random number of submissions between 1 and :submission_count
    # @option options [TrueClass, FalseClass] :process_submission Parse the test ontology file
    def create_ontologies_and_submissions(options = {})
      LinkedData::SampleData::Ontology.create_ontologies_and_submissions(options)
    end

    ##
    # Delete all ontologies and their submissions
    def delete_ontologies_and_submissions
      LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    end

    def delete_goo_models(gooModelArray)
      gooModelArray.each do |m|
        m.delete
        assert_equal(false, m.exist?(reload=true), "Failed to delete a goo model.")
      end
    end

    # Test the 'creator' attribute of a GOO model class
    # @note This method name cannot begin with 'test_' or it will be called as a test
    # @param [LinkedData::Models] model_class a GOO model class, e.g. LinkedData::Models::Project
    # @param [LinkedData::Models::User] user a valid instance of LinkedData::Models::User
    def model_creator_test(model, user)
      # TODO: if the input argument is an instance, use the .class.new methods?
      m = model.is_a?(Class) ? model.new : model
      assert_equal(false, m.valid?, "#{m} .valid? returned true, it was expected to be invalid.")
      m.creator = "test name" # string is not valid
      assert_equal(false, m.valid?, "#{m} .valid? returned true, it was expected to be invalid.")
      assert_equal(false, m.errors[:creator].nil?) # We expect there to be errors on creator
      assert_instance_of(LinkedData::Models::User, user, "#{user} is not an instance of LinkedData::Models::User")
      assert_equal(true, user.valid?, "#{user} is not a valid instance of LinkedData::Models::User")
      m.creator = user  # LinkedData::Models::User instance is valid, but other attributes may generate errors.
      assert_equal(false, m.valid?, "#{m} .valid? returned true, it was expected to be invalid.")
      assert_equal(true, m.errors[:creator].nil?) # We expect there to be no errors on creator, there may be others.
    end

    # Test the 'created' attribute of a GOO model
    # @note This method name cannot begin with 'test_' or it will be called as a test
    # @param [LinkedData::Models::Base] m a valid model instance with a 'created' attribute (without a value).
    def model_created_test(m)
      assert_equal(true, m.kind_of?(LinkedData::Models::Base), "Expected kind_of?(LinkedData::Models::Base).")
      assert_equal(true, m.valid?, "Expected valid model: #{m.errors}")
      m.save if m.valid?
      # The default value is auto-generated (during save), it should be OK.
      assert_instance_of(DateTime, m.created, "The 'created' attribute is not a DateTime instance.")
      assert_equal(true, m.errors[:created].nil?, "#{m.errors}")
      m.created = "this string should fail"
      assert (not m.valid?)
      assert_equal(false, m.errors[:created].nil?, "#{m.errors}")
      # The value should be an XSD date time.
      m.created = DateTime.new
      assert m.valid?
      assert_instance_of(DateTime, m.created)
      assert_equal(true, m.errors[:created].nil?, "#{m.errors}")
    end

    # Test the save and delete methods on a GOO model
    # @param [LinkedData::Models::Base] m a valid model instance that can be saved and deleted
    def model_lifecycle_test(m)
      assert_equal(true, m.kind_of?(LinkedData::Models::Base), "Expected kind_of?(LinkedData::Models::Base).")
      assert_equal(true, m.valid?, "Expected valid model: #{m.errors}")
      assert_equal(false, m.exist?(reload=true), "Given model is already saved, expected one that is not.")
      m.save
      assert_equal(true, m.exist?(reload=true), "Failed to save model.")
      m.delete
      assert_equal(false, m.exist?(reload=true), "Failed to delete model.")
    end

  end
end
