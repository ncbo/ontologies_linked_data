require_relative '../models/test_ontology_common'
require 'mocha/minitest'
require 'stringio'

class TestRankSolrPropagator < LinkedData::TestOntologyCommon
  ACRONYM = 'BRO'

  def self.after_suite
    backend_4s_delete
    LinkedData::Models::Class.indexClear
    LinkedData::Models::Class.indexCommit(nil)
  end

  def setup
    self.class.after_suite
    clear_propagation_cache
    # Index a small ontology's terms into the real local term_search collection.
    submission_parse(ACRONYM, 'BRO Ontology',
                     './test/data/ontology_files/BRO_v3.5.owl', 1,
                     process_rdf: true, extract_metadata: false,
                     generate_missing_labels: false,
                     index_search: true, index_properties: false)
  end

  def teardown
    self.class.after_suite
    clear_propagation_cache
  end

  def clear_propagation_cache
    Redis.new(host: LinkedData.settings.ontology_analytics_redis_host,
              port: LinkedData.settings.ontology_analytics_redis_port)
         .del(LinkedData::Services::RankSolrPropagator::LAST_PROPAGATED_REDIS_FIELD)
  end

  def stub_rank(score)
    LinkedData::Models::Ontology.stubs(:rank).returns(
      { ACRONYM => { bioportalScore: 0.5, umlsScore: 0.0, normalizedScore: score } }
    )
  end

  def term_docs
    LinkedData::Models::Class.search(
      '*:*',
      { fq: "submissionAcronym:#{ACRONYM}", fl: 'id,ontologyRank', rows: 10_000 }
    )['response']['docs']
  end

  def test_propagate_writes_normalized_score_to_all_term_docs
    docs_before = term_docs
    refute_empty docs_before, 'expected BRO terms to be indexed in term_search'

    stub_rank(0.642)

    updated = LinkedData::Services::RankSolrPropagator.new.propagate
    assert_equal 1, updated

    docs_after = term_docs
    assert_equal docs_before.size, docs_after.size
    docs_after.each do |doc|
      assert_in_delta 0.642, doc['ontologyRank'].to_f, 0.0001,
                      "doc #{doc['id']} should have the propagated rank"
    end
  end

  def test_propagate_preserves_searchable_fields
    # A real term search works before propagation.
    before = LinkedData::Models::Class.search(
      'prefLabel:Activity', { fq: "submissionAcronym:#{ACRONYM}", rows: 80 }
    )['response']['numFound']
    refute_equal 0, before, 'expected a prefLabel match before propagation'

    stub_rank(0.642)
    LinkedData::Services::RankSolrPropagator.new.propagate

    # The same search still works after atomic updates (copyField targets and
    # stored fields survived the partial update).
    after = LinkedData::Models::Class.search(
      'prefLabel:Activity', { fq: "submissionAcronym:#{ACRONYM}", rows: 80 }
    )['response']['numFound']
    assert_equal before, after,
                 'atomic update must not drop searchable content'
  end

  def test_propagate_returns_zero_for_empty_rank_map
    LinkedData::Models::Ontology.stubs(:rank).returns({})
    assert_equal 0, LinkedData::Services::RankSolrPropagator.new.propagate
  end

  def test_propagate_skips_unchanged_ontology_on_second_run
    stub_rank(0.642)

    first = LinkedData::Services::RankSolrPropagator.new.propagate
    assert_equal 1, first, 'first run should propagate the ontology'

    # Rank unchanged -> the second run should skip it entirely.
    second = LinkedData::Services::RankSolrPropagator.new.propagate
    assert_equal 0, second, 'unchanged ontology should be skipped on the second run'
  end

  def test_force_repropagates_even_when_unchanged
    stub_rank(0.642)

    LinkedData::Services::RankSolrPropagator.new.propagate
    # force: true ignores the skip cache and re-propagates.
    forced = LinkedData::Services::RankSolrPropagator.new.propagate(nil, force: true)
    assert_equal 1, forced, 'force should re-propagate even when rank is unchanged'
  end

  # Manifests the Solr-stall condition: the first atomic-update POST raises a
  # retryable error, and we assert the run recovers AND emits a visible signal
  # (a BACKPRESSURE warning plus a non-zero retry count in the summary).
  def test_backpressure_is_retried_and_logged
    stub_rank(0.642)

    log_io = StringIO.new
    propagator = LinkedData::Services::RankSolrPropagator.new(logger: Logger.new(log_io))
    propagator.stubs(:sleep) # skip the backoff wait in the test

    client = LinkedData::Models::Class.search_client
    client.stubs(:index_document)
          .raises(Errno::ECONNRESET.new('simulated Solr stall'))
          .then.returns(true)

    updated = propagator.propagate
    assert_equal 1, updated, 'run should recover from the transient error'

    log = log_io.string
    assert_match(/BACKPRESSURE/, log, 'a retry must emit a filterable BACKPRESSURE warning')
    assert_match(/Solr retries: 1/, log, 'summary must report the retry count')
  end

  # A clean run reports zero retries, so "Solr retries: 0" is the all-clear.
  def test_clean_run_reports_zero_retries
    stub_rank(0.642)

    log_io = StringIO.new
    LinkedData::Services::RankSolrPropagator.new(logger: Logger.new(log_io)).propagate

    assert_match(/Solr retries: 0/, log_io.string, 'clean run must report zero retries')
  end
end
