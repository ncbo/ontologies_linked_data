# Start simplecov if this is a coverage task or if it is run in the CI pipeline
if ENV['COVERAGE'] == 'true' || ENV['CI'] == 'true'
  require 'simplecov'
  require 'simplecov-cobertura'
  # https://github.com/codecov/ruby-standard-2
  # Generate HTML and Cobertura reports which can be consumed by codecov uploader
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter
  ])
  SimpleCov.start do
    add_filter '/test/'
    add_filter 'app.rb'
    add_filter 'init.rb'
    add_filter '/config/'
  end
end

require_relative 'test_log_file'
require_relative '../lib/ontologies_linked_data'

if ENV['OVERRIDE_CONFIG'] == 'true'
  SOLR_HOST = ENV.include?('SOLR_HOST') ? ENV['SOLR_HOST'] : 'localhost'

  LinkedData.config do |config|
    config.goo_backend_name           = ENV['GOO_BACKEND_NAME']
    config.goo_port                   = ENV['GOO_PORT'].to_i
    config.goo_host                   = ENV['GOO_HOST']
    config.goo_path_query             = ENV['GOO_PATH_QUERY']
    config.goo_path_data              = ENV['GOO_PATH_DATA']
    config.goo_path_update            = ENV['GOO_PATH_UPDATE']
    config.goo_redis_host             = ENV['REDIS_HOST']
    config.goo_redis_port             = ENV['REDIS_PORT']
    config.http_redis_host            = ENV['REDIS_HOST']
    config.http_redis_port            = ENV['REDIS_PORT']
    config.search_server_url          = "http://#{SOLR_HOST}:8983/solr/term_search_core1"
    config.property_search_server_url = "http://#{SOLR_HOST}:8983/solr/prop_search_core1"
  end
end

require_relative '../config/config'
require 'minitest/unit'
MiniTest::Unit.autorun

# Check to make sure you want to run if not pointed at localhost
safe_hosts = Regexp.new(/localhost|-ut|ncbo-dev*|ncbo-unittest*/)
def safe_redis_hosts?(sh)
  return [LinkedData.settings.http_redis_host,
   LinkedData.settings.goo_redis_host].select { |x|
    x.match(sh)
  }.length == 2
end
unless LinkedData.settings.goo_host.match(safe_hosts) &&
       LinkedData.settings.search_server_url.match(safe_hosts) &&
       safe_redis_hosts?(safe_hosts)
  print '\n\n================================== WARNING ==================================\n'
  print '** TESTS CAN BE DESTRUCTIVE -- YOU ARE POINTING TO A POTENTIAL PRODUCTION/STAGE SERVER **\n'
  print 'Servers:\n'
  print "triplestore -- #{LinkedData.settings.goo_host}\n"
  print "search -- #{LinkedData.settings.search_server_url}\n"
  print "redis http -- #{LinkedData.settings.http_redis_host}:#{LinkedData.settings.http_redis_port}\n"
  print "redis goo -- #{LinkedData.settings.goo_redis_host}:#{LinkedData.settings.goo_redis_port}\n"
  print "Type 'y' to continue: "
  $stdout.flush
  confirm = $stdin.gets
  abort('Canceling tests...\n\n') unless confirm.strip == 'y'
  print 'Running tests...'
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
      TestCase.backend_4s_delete
      before_suites
      super(suites, type)
    ensure
      TestCase.backend_4s_delete
      after_suites
    end

    def _run_suite(suite, type)
      suite.before_suite if suite.respond_to?(:before_suite)
      super(suite, type)
    rescue Exception => e
      puts e.message
      puts e.backtrace.join("\n\t")
      puts 'Traced from:'
      raise e
    ensure
      suite.after_suite if suite.respond_to?(:after_suite)
    end
  end

  MiniTest::Unit.runner = LinkedData::Unit.new

  class TestCase < MiniTest::Unit::TestCase

    # Ensure all threads exit on any exception
    Thread.abort_on_exception = true

    def submission_dependent_objects(format, acronym, user_name)
      # ontology format
      owl = LinkedData::Models::OntologyFormat.where(acronym: format).first
      assert_instance_of LinkedData::Models::OntologyFormat, owl

      # ontology
      users = LinkedData::Models::User.where(username: user_name).all
      user = users.first

      if user.nil?
        user = LinkedData::Models::User.new({username: user_name})
        user.email = 'a@example.org'
        user.passwordHash = 'XXXXX'
        user.save
      end

      ont = LinkedData::Models::Ontology.where(acronym: acronym).all
      ont = ont.first

      if ont.nil?
        ont = LinkedData::Models::Ontology.new({acronym: acronym})
        ont.name = "some name for #{acronym}"
        ont.administeredBy = [user]
        ont.save
      end
      contact = LinkedData::Models::Contact.new
      contact.email = 'xxx@example.org'
      contact.name  = 'some name'
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
    # Retrieve ontology dependent objects
    def ontology_objects
      LinkedData::SampleData::Ontology.ontology_objects
    end

    ##
    # Delete all ontologies and their submissions
    def delete_ontologies_and_submissions
      LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    end

    def delete_goo_models(gooModelArray)
      gooModelArray.each do |m|
        m.delete
        assert_equal(false, m.exist?(reload=true), 'Failed to delete a goo model.')
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
      m.creator = 'test name' # string is not valid
      assert_equal(false, m.valid?, "#{m} .valid? returned true, it was expected to be invalid.")
      assert_equal(false, m.errors[:creator].nil?) # We expect there to be errors on creator
      assert_instance_of(LinkedData::Models::User, user, "#{user} is not an instance of LinkedData::Models::User")
      assert_equal(true, user.valid?, "#{user} is not a valid instance of LinkedData::Models::User")
      m.instance_of?(LinkedData::Models::Project) ? m.creator = [user] : m.creator = user
      assert_equal(false, m.valid?, "#{m} .valid? returned true, it was expected to be invalid.")
      assert_equal(true, m.errors[:creator].nil?, "Invalid model: #{m.errors}")
    end

    # Test the 'created' attribute of a GOO model
    # @note This method name cannot begin with 'test_' or it will be called as a test
    # @param [LinkedData::Models::Base] m a valid model instance with a 'created' attribute (without a value).
    def model_created_test(m)
      assert_equal(true, m.is_a?(LinkedData::Models::Base), 'Expected is_a?(LinkedData::Models::Base).')
      assert_equal(true, m.valid?, "Expected valid model: #{m.errors}")
      m.save if m.valid?
      # The default value is auto-generated (during save), it should be OK.
      assert_instance_of(DateTime, m.created, "The 'created' attribute is not a DateTime instance.")
      assert_equal(true, m.errors[:created].nil?, m.errors.to_s)

      begin
        m.created = 'this string shuld fail'
      rescue Exception => e
        # in ruby 2.3+, this generates a runtime exception, so we need to handle it
        assert_equal Date::Error, e.class
        assert_equal 'invalid date', e.message
      end

      # The value should be an XSD date time.
      m.created = DateTime.now
      assert m.valid?
      assert_instance_of(DateTime, m.created)
      assert_equal(true, m.errors[:created].nil?, m.errors.to_s)
    end

    # Test the save and delete methods on a GOO model
    # @param [LinkedData::Models::Base] m a valid model instance that can be saved and deleted
    def model_lifecycle_test(m)
      assert_equal(true, m.is_a?(LinkedData::Models::Base), 'Expected is_a?(LinkedData::Models::Base).')
      assert_equal(true, m.valid?, "Expected valid model: #{m.errors}")
      assert_equal(false, m.exist?(reload=true), 'Given model is already saved, expected one that is not.')
      m.save
      assert_equal(true, m.exist?(reload=true), 'Failed to save model.')
      m.delete
      assert_equal(false, m.exist?(reload=true), 'Failed to delete model.')
    end

    def self.count_pattern(pattern)
      q = "SELECT (count(DISTINCT ?s) as ?c) WHERE { #{pattern} }"
      rs = Goo.sparql_query_client.query(q)
      rs.each_solution do |sol|
        return sol[:c].object
      end
      return 0
    end

    def self.backend_4s_delete
      raise StandardError, 'Too many triples in KB, does not seem right to run tests' unless
            count_pattern('?s ?p ?o') < 400000

      Goo.sparql_update_client.update('DELETE {?s ?p ?o } WHERE { ?s ?p ?o }')
      LinkedData::Models::SubmissionStatus.init_enum
      LinkedData::Models::OntologyType.init_enum
      LinkedData::Models::OntologyFormat.init_enum
      LinkedData::Models::Users::Role.init_enum
      LinkedData::Models::Users::NotificationType.init_enum
    end
  end
end
