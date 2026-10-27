require 'minitest/autorun'
require 'mocha/minitest'
require 'logger'
require 'stringio'
require_relative '../../lib/ontologies_linked_data'

class TestSubmissionMetadataExtractor < Minitest::Test
  def setup
    ontology = LinkedData::Models::Ontology.new(acronym: 'VERSIONTEST')
    format = LinkedData::Models::OntologyFormat.new(acronym: 'OBO')
    contact = LinkedData::Models::Contact.new(name: 'Test', email: 'test@example.org')
    [ontology, format, contact].each { |resource| resource.stubs(:persistent?).returns(true) }

    @submission = LinkedData::Models::OntologySubmission.new(
      id: RDF::URI.new('http://data.bioontology.org/ontologies/VERSIONTEST/submissions/2'),
      submissionId: 2, ontology: ontology, hasOntologyLanguage: format,
      contact: [contact], released: DateTime.now, version: '4.1.195',
      uploadFilePath: File.expand_path('../data/ontology_files/SBO.obo', __dir__)
    )
    # Keep persistence and SPARQL out of these tests, but use real model validation
    # and the real heavy metadata extraction / assignment code.
    @submission.stubs(:exist?).returns(false)
    @submission.stubs(:save).returns(@submission)
    @submission.modified_attributes.clear
    @extractor = LinkedData::Services::SubmissionMetadataExtractor.new(@submission)
    @extractor.stubs(:extract_ontology_iri).returns(nil)
    @extractor.stubs(:extract_each_metadata).returns({})
    @extractor.stubs(:extract_version).returns('4.2.11')
    @log = StringIO.new
    @logger = Logger.new(@log)
    assert @submission.valid?, @submission.errors.inspect
  end

  [true, false].each do |heavy|
    define_method("test_refreshes_inherited_version_with_heavy_extraction_#{heavy}") do
      extract(heavy: heavy)
      assert_equal '4.2.11', @submission.version
    end

    define_method("test_preserves_explicit_version_with_heavy_extraction_#{heavy}") do
      @submission.version = 'User release'
      @extractor.expects(:extract_version).never
      heavy_version('Ontology release')

      extract(heavy: heavy, user_params: {version: 'User release'})
      assert_equal 'User release', @submission.version
    end

    define_method("test_preserves_string_keyed_version_with_heavy_extraction_#{heavy}") do
      @submission.version = 'User release'
      @extractor.expects(:extract_version).never
      heavy_version('Ontology release')

      extract(heavy: heavy, user_params: {'version' => 'User release'})
      assert_equal 'User release', @submission.version
    end

    define_method("test_blank_user_versions_allow_extraction_with_heavy_extraction_#{heavy}") do
      [nil, '', '   ', []].each do |version|
        @submission.version = '4.1.195'
        extract(heavy: heavy, user_params: {version: version})
        assert_equal '4.2.11', @submission.version
      end
    end

    define_method("test_missing_or_blank_parser_version_preserves_existing_with_heavy_extraction_#{heavy}") do
      [nil, '', '   '].each do |version|
        @extractor.stubs(:extract_version).returns(version)
        extract(heavy: heavy)
        assert_equal '4.1.195', @submission.version
      end
    end

    define_method("test_invalid_parser_version_preserves_existing_with_heavy_extraction_#{heavy}") do
      ["invalid\nversion", '<invalid>', 'v' * 1025].each do |version|
        @extractor.stubs(:extract_version).returns(version)
        extract(heavy: heavy)
        assert_equal '4.1.195', @submission.version
      end
      assert_match(/extracted submission version.*invalid/m, @log.string)
    end
  end

  def test_valid_heavy_version_takes_precedence_over_parser_version
    heavy_version('Mapped release', property: 'owl:versionInfo')
    extract
    assert_equal 'Mapped release', @submission.version
  end

  def test_invalid_parser_version_does_not_prevent_valid_heavy_extraction
    @extractor.stubs(:extract_version).returns("invalid\nversion")
    heavy_version('Mapped release')
    extract
    assert_equal 'Mapped release', @submission.version
  end

  def test_heavy_version_equal_to_inherited_version_still_takes_precedence
    heavy_version('4.1.195')
    extract
    assert_equal '4.1.195', @submission.version
  end

  def test_invalid_heavy_version_preserves_new_parser_version
    heavy_version("invalid\nversion")
    extract
    assert_equal '4.2.11', @submission.version
    assert_match(/Error while extracting metadata for the attribute version/, @log.string)
  end

  def test_blank_heavy_version_preserves_new_parser_version
    heavy_version('   ')
    extract
    assert_equal '4.2.11', @submission.version
  end

  def test_invalid_versions_from_both_sources_preserve_existing_version
    @extractor.stubs(:extract_version).returns("invalid\nparser version")
    heavy_version("invalid\nheavy version")
    extract
    assert_equal '4.1.195', @submission.version
  end

  def test_missing_existing_version_is_populated
    @submission.version = nil
    extract
    assert_equal '4.2.11', @submission.version
  end

  def test_invalid_parser_version_leaves_missing_version_unset
    @submission.version = nil
    @extractor.stubs(:extract_version).returns("invalid\nversion")
    extract
    assert_nil @submission.version
    assert_match(/extracted submission version.*invalid/m, @log.string)
  end

  def test_false_user_params_allow_extraction
    extract(user_params: false)
    assert_equal '4.2.11', @submission.version
  end

  def test_other_metadata_is_still_extracted
    @extractor.stubs(:extract_each_metadata)
              .with(anything, :description, 'omv:description', anything)
              .returns({RDF::Literal.new('Updated description') => 'Updated description'})
    extract
    assert_equal 'Updated description', @submission.description
  end

  def test_heavy_extraction_failure_preserves_parser_version
    @extractor.stubs(:extract_ontology_metadata).raises(StandardError, 'metadata query failed')
    extract
    assert_equal '4.2.11', @submission.version
    assert_match(/Error while extracting additional metadata/, @log.string)
  end

  def test_invalid_submission_is_not_extracted_or_saved
    @submission.released = nil
    @extractor.expects(:extract_version).never
    @extractor.expects(:extract_ontology_iri).never
    @submission.expects(:save).never
    assert_nil @extractor.process(@logger, user_params: nil, heavy_extraction: true)
  end

  private

  def heavy_version(version, property: 'omv:version')
    @extractor.stubs(:extract_each_metadata)
              .with(anything, :version, property, anything)
              .returns({RDF::Literal.new(version) => version})
  end

  def extract(heavy: true, user_params: nil)
    result = @extractor.process(@logger, user_params: user_params, heavy_extraction: heavy)
    assert_same @submission, result
    assert @submission.valid?, @submission.errors.inspect
  end
end
