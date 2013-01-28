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
require "test/unit"

module LinkedData
  class TestCase < Test::Unit::TestCase
    def submission_dependent_objects(format,acronym,user_name,status_code)
      #ontology format
      LinkedData::Models::OntologyFormat.init
      owl = LinkedData::Models::OntologyFormat.where(:acronym => format)[0]
      assert_instance_of LinkedData::Models::OntologyFormat, owl

      #ontology
      LinkedData::Models::OntologyFormat.init
      ont = LinkedData::Models::Ontology.where(:acronym => acronym)
      LinkedData::Models::OntologyFormat.init
      assert(ont.length < 2)
      if ont.length == 0
        ont = LinkedData::Models::Ontology.new({:acronym => acronym})
      else
        ont = ont[0]
      end

      #user test_linked_models
      users = LinkedData::Models::User.where(:username => user_name)
      assert(users.length < 2)
      if users.length == 0
        user = LinkedData::Models::User.new({:username => user_name})
      else
        user = users[0]
      end

          #user test_linked_models
      LinkedData::Models::SubmissionStatus.init
      status = LinkedData::Models::SubmissionStatus.where(:code => status_code)
      assert(status.length < 2)
      if status.length == 0
        status = LinkedData::Models::SubmissionStatus.new({:code => status_code})
      else
        status = status[0]
      end

      #Submission Status
      return owl, ont, user, status
    end

    def teardown
      delete_ontologies_and_submissions
    end

    ##
    # Creates a set of Ontology and OntologySubmission objects and stores them in the triplestore
    # @param [Hash] options the options to create ontologies with
    # @option options [Fixnum] :ont_count Number of ontologies to create
    # @option options [Fixnum] :submission_count How many submissions each ontology should have (acts as max number when random submission count is used)
    # @option options [TrueClass, FalseClass] :random_submission_count Use a random number of submissions between 1 and :submission_count
    def create_ontologies_and_submissions(options = {})
      ont_count = options[:ont_count] || 5
      submission_count = options[:submission_count] || 5
      random_submission_count = options[:random_submission_count].nil? ? true : options[:random_submission_count]

      u = LinkedData::Models::User.new(username: "tim", email: "tim@example.org")
      u.save unless u.exist? || !u.valid?

      of = LinkedData::Models::OntologyFormat.new(acronym: "OWL")
      of.save unless u.exist? || !u.valid?

      ont_acronyms = []
      ontologies = []
      ont_count.to_i.times do |count|
        acronym = "TST-ONT-#{count}"
        ont_acronyms << acronym

        o = LinkedData::Models::Ontology.new({
          acronym: acronym,
          name: "Test Ontology ##{count}",
          administeredBy: u
        })

        if o.valid?
          o.save
          ontologies << o
        end

        # Random submissions (between 1 and max)
        max = random_submission_count ? (1..submission_count.to_i).to_a.shuffle.first : submission_count
        max.times do
          os = LinkedData::Models::OntologySubmission.new({
            acronym: "TST-ONT-#{count}",
            ontology: o,
            hasOntologyLanguage: of,
            pullLocation: RDF::IRI.new("http://example.com"),
            submissionStatus: LinkedData::Models::SubmissionStatus.new(:code => "UPLOADED"),
            submissionId: o.next_submission_id
          })
          os.save if os.valid?
        end
      end

      # Get ontology objects if empty
      if ontologies.empty?
        ont_acronyms.each do |ont_id|
          ontologies << LinkedData::Models::Ontology.find(ont_id)
        end
      end

      return ont_count, ont_acronyms, ontologies
    end

    ##
    # Delete all ontologies and their submissions. This will look for all ontologies starting with TST-ONT- and ending in a Fixnum
    def delete_ontologies_and_submissions
      ont = LinkedData::Models::Ontology.find("TST-ONT-0")
      count = 0
      while ont
        ont.delete
        ont = LinkedData::Models::Ontology.find("TST-ONT-#{count+1}")
      end

      u = LinkedData::Models::User.find("tim")
      u.delete unless u.nil?

      of = LinkedData::Models::OntologyFormat.find("OWL")
      of.delete unless u.nil?
    end

  end
end
