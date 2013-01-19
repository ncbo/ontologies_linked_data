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
  end
end
