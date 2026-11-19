require_relative "../test_case"
require "logger"
require "tmpdir"

class TestOWLApi < LinkedData::TestCase
  def test_command_owl_api_single_file
    return if ENV["SKIP_PARSING"]

    output_repo = "test/data/ontology_files/repo/bro/10/output"
    input_file = "test/data/ontology_files/BRO_v3.2.owl"
    begin
      tmp_log = Logger.new(TestLogFile.new)
      LinkedData::Parser.logger = tmp_log
    rescue Exception => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end

    owlapi = LinkedData::Parser::OWLAPICommand.new(input_file, output_repo)
    owlapi.parse
    assert(File.exist?(output_repo))
    assert(File.exist?(input_file))
    assert(File.exist?(owlapi.file_triples_path))
  end

  def test_command_KO_output
    return if ENV["SKIP_PARSING"]

    # raise error when creatting a directory on a read only file system
    output_repo = "/sys/cant_create_such_dir_on_a_read_only_file_system"
    input_file = "test/data/ontology_files/BRO_v3.1.owl"
    owlapi = LinkedData::Parser::OWLAPICommand.new(input_file, output_repo)
    assert_raises(LinkedData::Parser::MkdirException) { owlapi.parse }
  end

  def test_command_KO_input
    return if ENV["SKIP_PARSING"]

    output_repo = "/var/log/xxxxx"
    input_file = "test/data/ontology_files/aaaa"
    owlapi = LinkedData::Parser::OWLAPICommand.new(input_file, output_repo)
    assert_raises(LinkedData::Parser::InputFileNotFoundError) { owlapi.parse }
  end

  def test_command_KO_master
    return if ENV["SKIP_PARSING"]

    output_repo = "/var/log/xxxxx"
    input_file = "test/data/ontology_files/radlex_owl_v3.0.1.zip"
    owlapi = LinkedData::Parser::OWLAPICommand.new(input_file, output_repo)
    assert_raises(LinkedData::Parser::MasterFileMissingException) { owlapi.parse }
  end

  def test_command_timeout_raises_and_removes_partial_output
    return if ENV["SKIP_PARSING"]

    Dir.mktmpdir("owlapi_timeout") do |output_repo|
      # Stands in for a file a killed run started writing
      output_rdf = File.join(output_repo, "owlapi.xrdf")
      File.write(output_rdf, "partial")
      input_file = File.expand_path("test/data/ontology_files/BRO_v3.2.owl")
      owlapi = LinkedData::Parser::OWLAPICommand.new(input_file, output_repo,
                                                     logger: Logger.new(StringIO.new), timeout: 0.01)

      error = assert_raises(LinkedData::Parser::OWLAPITimeoutException) { owlapi.parse }
      assert_kind_of LinkedData::Parser::OWLAPIParserException, error
      refute File.exist?(output_rdf), "a timed-out parse must not leave owlapi.xrdf behind"
      assert_nil owlapi.file_triples_path
      assert_empty `pgrep -f #{Shellwords.escape(output_repo)}`.strip, "the killed JVM is still running"
    end
  end

  def test_command_input_path_with_spaces
    return if ENV["SKIP_PARSING"]

    # owlapi_wrapper itself cannot write to an output folder with a space,
    # so only the input path has them
    Dir.mktmpdir("owlapi_spaces") do |dir|
      input_file = File.join(dir, "input dir", "BRO v3.2.owl")
      FileUtils.mkdir_p(File.dirname(input_file))
      FileUtils.cp("test/data/ontology_files/BRO_v3.2.owl", input_file)
      output_repo = File.join(dir, "output")

      owlapi = LinkedData::Parser::OWLAPICommand.new(input_file, output_repo, logger: Logger.new(StringIO.new))
      triples_file_path, _missing_imports = owlapi.parse
      assert_equal File.join(output_repo, "owlapi.xrdf"), triples_file_path
      assert File.size?(triples_file_path)
    end
  end
end
