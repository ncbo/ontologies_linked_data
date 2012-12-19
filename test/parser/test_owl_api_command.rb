require_relative "../test_case"
require 'logger'

class TestOWLApi < LinkedData::TestCase

  def test_command_owl_api_single_file
    output_repo =  "test/data/ontology_files/repo/bro/10/output"
    input_file = "test/data/ontology_files/BRO_v3.2.owl"
    LinkedData::Parser.logger =  Logger.new(STDOUT)
    owlapi = LinkedData::Parser::OWLAPICommand.new(input_file,output_repo,nil)
    owlapi.parse
    assert(File.exist?(output_repo))
    assert(File.exist?(input_file))
    assert(File.exist?(owlapi.file_triples_path))
  end

  def test_command_KO_output
    output_repo =  "/var/log/xxxxx"
    input_file = "test/data/ontology_files/"
    owlapi = LinkedData::Parser::OWLAPICommand.new(input_file,output_repo,nil)
    begin
      owlapi.parse
      assert(false)
    rescue LinkedData::Parser::ParserException => e
      assert(e.kind_of? LinkedData::Parser::MkdirException)
    end
  end
  def test_command_KO_input
    output_repo =  "/var/log/xxxxx"
    input_file = "test/data/ontology_files/aaaa"
    owlapi = LinkedData::Parser::OWLAPICommand.new(input_file,output_repo,nil)
    begin
      owlapi.parse
      assert(false)
    rescue LinkedData::Parser::ParserException => e
      assert(e.kind_of? LinkedData::Parser::InputFileNotFoundError)
    end
  end

  def test_command_KO_master
    output_repo =  "/var/log/xxxxx"
    input_file = "test/data/ontology_files/radlex_owl_v3.0.1.zip"
    owlapi = LinkedData::Parser::OWLAPICommand.new(input_file,output_repo,nil)
    begin
      owlapi.parse
      assert(false)
    rescue LinkedData::Parser::ParserException => e
      assert(e.kind_of? LinkedData::Parser::MasterFileMissingException)
    end
  end

end
