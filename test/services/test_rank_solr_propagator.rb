require_relative '../models/test_ontology_common'
require 'mocha/minitest'

class TestRankSolrPropagator < LinkedData::TestOntologyCommon
  ACRONYM = 'BRO'

  def self.after_suite
    backend_4s_delete
    LinkedData::Models::Class.indexClear
    LinkedData::Models::Class.indexCommit(nil)
  end

  def setup
    self.class.after_suite
    # Index a small ontology's terms into the real local term_search collection.
    submission_parse(ACRONYM, 'BRO Ontology',
                     './test/data/ontology_files/BRO_v3.5.owl', 1,
                     process_rdf: true, extract_metadata: false,
                     generate_missing_labels: false,
                     index_search: true, index_properties: false)
  end

  def teardown
    self.class.after_suite
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

    LinkedData::Models::Ontology.stubs(:rank).returns(
      { ACRONYM => { bioportalScore: 0.5, umlsScore: 0.0, normalizedScore: 0.642 } }
    )

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

    LinkedData::Models::Ontology.stubs(:rank).returns(
      { ACRONYM => { bioportalScore: 0.5, umlsScore: 0.0, normalizedScore: 0.642 } }
    )
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
end
