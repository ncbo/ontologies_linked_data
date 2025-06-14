require_relative '../test_ontology_common'
require 'logger'

class TestCollections < LinkedData::TestOntologyCommon


  def self.before_suite
    LinkedData::TestCase.backend_4s_delete
  end

  def test_collections_all
    submission_parse('INRAETHES', 'Testing skos',
                     'test/data/ontology_files/thesaurusINRAE_nouv_structure.rdf',
                     1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: false)
    ont = 'INRAETHES'
    sub = LinkedData::Models::Ontology.find(ont).first.latest_submission
    collections = LinkedData::Models::SKOS::Collection.in(sub).include(:members, :prefLabel).all

    assert_equal 2, collections.size
    collections_test = test_data

    collections.each_with_index do |x, i|
      collection_test = collections_test[i]
      assert_equal collection_test[:id], x.id.to_s
      assert_equal collection_test[:prefLabel], x.prefLabel
      assert_equal collection_test[:memberCount], x.memberCount
    end
  end

  def test_collection_members
    submission_parse('INRAETHES', 'Testing skos',
                     'test/data/ontology_files/thesaurusINRAE_nouv_structure.rdf',
                     1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: false)
    ont = 'INRAETHES'
    sub = LinkedData::Models::Ontology.find(ont).first.latest_submission
    collection_test = test_data.first
    collection = LinkedData::Models::SKOS::Collection.find(collection_test[:id]).in(sub).include(:member, :prefLabel).first

    refute_nil collection
    members = collection.member
    assert_equal collection_test[:memberCount], members.size
  end

  private

  def test_data
    [
      {
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/gr_6c79e7c5',
        "prefLabel": 'GR. DEFINED CONCEPTS',
        "memberCount": 295
      },
      {
        "prefLabel": 'GR. DISCIPLINES',
        "memberCount": 233,
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/skosCollection_e25f9c62'
      }
    ]
  end
end
