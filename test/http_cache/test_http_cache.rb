require_relative "../test_case"

class DummyCacheSetup
  include LinkedData::HTTPCache::CacheableResource
  cache_segment_keys [:test_key]
end

class TestHTTPCache < LinkedData::TestCase

  def self.before_suite
    @@cache_setting = LinkedData.settings.enable_http_cache
    LinkedData.settings.enable_http_cache = true
    @@ontology, @@cls = self.new("before_suite")._ontology_and_class
  end

  def self.after_suite
    begin
      LinkedData::HTTPCache.invalidate_all
    ensure
      LinkedData.settings.enable_http_cache = @@cache_setting
    end
  end

  # Shared by the read-only tests; tests that save or delete use _standalone_ontology
  def _ontology_and_class
    results = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true,
                                                process_options: { process_rdf: true, extract_metadata: false })
    ontology = results[2].first
    cls = LinkedData::Models::Class.where.include(:prefLabel).in(ontology.latest_submission).first
    return ontology, cls
  end

  def _standalone_ontology(acronym)
    LinkedData::Models::Ontology.find(acronym).first&.delete
    user, = ontology_objects
    LinkedData::Models::Ontology.new(acronym: acronym, name: "#{acronym} Ontology", administeredBy: [user]).save
  end

  def setup
    LinkedData::HTTPCache.invalidate_all
  end

  def teardown
    LinkedData::HTTPCache.invalidate_all
  end

  def test_last_modified_valid
    @@ontology.cache_write
    assert @@ontology.last_modified
    assert @@ontology.last_modified_valid?(@@ontology.last_modified)
  end

  def test_cache_invalidate
    @@ontology.cache_write
    assert @@ontology.last_modified
    @@ontology.cache_invalidate
    assert_nil @@ontology.last_modified
  end

  def test_cache_segment_proper_setup
    dummy = DummyCacheSetup.new
    assert_raises(LinkedData::HTTPCache::CacheableResourceRequirementsError) do
      dummy.cache_segment
    end
  end

  def test_cache_segment_invalidate
    classes = LinkedData::Models::Class.where.include(:prefLabel).in(@@ontology.latest_submission).page(1, 100).to_a
    classes.each {|c| c.cache_write}
    last_modified_values = classes.map {|c| c.last_modified}
    assert last_modified_values.length == classes.length
    classes.first.cache_segment_invalidate
    last_modified_values = (classes.map {|c| c.last_modified}).compact
    assert last_modified_values.empty?
  end

  def test_cache_segment_invalidate_when_member_invalidates
    classes = LinkedData::Models::Class.where.include(:prefLabel).in(@@ontology.latest_submission).page(1, 100).to_a
    classes.each {|c| c.cache_write}
    last_modified_values = classes.map {|c| c.last_modified}
    assert last_modified_values.length == classes.length
    classes.first.cache_invalidate
    last_modified_values = (classes.map {|c| c.last_modified}).compact
    assert last_modified_values.empty?
  end

  def test_ld_save_invalidates
    ontology = _standalone_ontology("HTTPCACHE-SAVE")
    last_modified = ontology.cache_write
    ontology.name = "New name for save"
    sleep(1) # last_modified is an HTTP date, with one-second resolution
    ontology.save
    assert Time.httpdate(ontology.last_modified) > Time.httpdate(last_modified)
  ensure
    ontology&.delete
  end

  def test_ld_delete_invalidates
    ontology = _standalone_ontology("HTTPCACHE-DEL")
    ontology.cache_write
    assert ontology.last_modified
    ontology.delete
    refute ontology.last_modified
  end

  def test_segment_last_modified
    @@cls.cache_write
    assert @@cls.segment_last_modified
  end

  def test_cache_segment
    assert @@cls.cache_segment.eql?(":TEST-ONT-0:class")
  end

  def test_collection_last_modified_valid
    assert_nil LinkedData::Models::Ontology.collection_last_modified
    LinkedData::Models::Ontology.cache_collection_write
    assert LinkedData::Models::Ontology.collection_last_modified
    assert LinkedData::Models::Ontology.collection_last_modified_valid?(LinkedData::Models::Ontology.collection_last_modified)
  end

  def test_cache_collection_invalidate
    assert_nil LinkedData::Models::Ontology.collection_last_modified
    LinkedData::Models::Ontology.cache_collection_write
    assert LinkedData::Models::Ontology.collection_last_modified
    LinkedData::Models::Ontology.cache_collection_invalidate
    assert_nil LinkedData::Models::Ontology.collection_last_modified
  end

  def test_cache_invalidate_all
    LinkedData::Models::Ontology.cache_collection_write
    LinkedData::Models::Class.cache_collection_write
    assert LinkedData::Models::Ontology.collection_last_modified
    assert LinkedData::Models::Class.collection_last_modified
    classes = LinkedData::Models::Class.where.include(:prefLabel).in(@@ontology.latest_submission).page(1, 100).to_a
    classes.each {|c| c.cache_write}
    last_modified_values = classes.map {|c| c.last_modified}
    assert last_modified_values.length == classes.length
    LinkedData::HTTPCache.invalidate_all
    assert_nil LinkedData::Models::Ontology.collection_last_modified
    assert_nil LinkedData::Models::Class.collection_last_modified
    last_modified_values = (classes.map {|c| c.last_modified}).compact
    assert last_modified_values.empty?
    assert_equal [], LinkedData::HTTPCache.keys_for_invalidate_all
  end

end
