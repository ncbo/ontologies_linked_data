require_relative '../test_case'

class TestSearch < LinkedData::TestCase

  def self.after_suite
    backend_4s_delete
    LinkedData::Models::Ontology.indexClear
    Goo.search_client(:ontology_data)&.clear_all_data
  end

  def setup
    self.class.after_suite
  end

  def test_search_ontology
    _, _, created_ontologies = create_ontologies_and_submissions({
                                                                    process_submission: true,
                                                                    process_options: {
                                                                      process_rdf: true,
                                                                      generate_missing_labels: false,
                                                                      extract_metadata: false, run_metrics: true
                                                                    },
                                                                    acronym: 'BROTEST',
                                                                    name: 'ontTEST Bla',
                                                                    file_path: '../../../../test/data/ontology_files/BRO_v3.2.owl',
                                                                    ont_count: 2,
                                                                    submission_count: 2
                                                                 })
    ontologies = LinkedData::Models::Ontology.search('*:*', { fq: 'resource_model: "ontology"' })['response']['docs']

    assert_equal 2, ontologies.size
    ontologies.each do |ont|
      select_ont = created_ontologies.select { |ont_created| ont_created.id.to_s.eql?(ont['id']) }.first
      refute_nil select_ont
      select_ont.bring_remaining
      assert_equal ont['name_text'], select_ont.name
      assert_equal ont['acronym_text'], select_ont.acronym
      assert_equal ont['viewingRestriction_t'], select_ont.viewingRestriction
      assert_equal ont['ontologyType_t'], select_ont.ontologyType.id
    end

    submissions = LinkedData::Models::Ontology.search('*:*', { fq: 'resource_model: "ontology_submission"' })['response']['docs']
    assert_equal 4, submissions.size
    submissions.each do |sub|
      created_sub = LinkedData::Models::OntologySubmission.find(RDF::URI.new(sub['id'])).first&.bring_remaining
      refute_nil created_sub
      assert_equal sub['description_text'], created_sub.description
      assert_equal sub['submissionId_i'], created_sub.submissionId
      assert_equal sub['uri_text'], created_sub.uri
      assert_equal sub['status_t'], created_sub.status
      assert_equal sub['deprecated_b'], created_sub.deprecated
      assert_equal sub['hasOntologyLanguage_t'], created_sub.hasOntologyLanguage.id.to_s
      assert_equal sub['released_dt'], created_sub.released.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      assert_equal sub['creationDate_dt'], created_sub.creationDate.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      assert_equal(sub['contact_txt'], created_sub.contact.map { |x| x.bring_remaining.embedded_doc })
      assert_equal sub['dataDump_t'], created_sub.dataDump
      assert_equal sub['csvDump_t'], created_sub.csvDump
      assert_equal sub['uriLookupEndpoint_t'], created_sub.uriLookupEndpoint
      assert_equal sub['openSearchDescription_t'], created_sub.openSearchDescription
      assert_equal sub['uploadFilePath_t'], created_sub.uploadFilePath
      assert_equal sub['submissionStatus_txt'].sort, created_sub.submissionStatus.map { |x| x.id.to_s }.sort

      created_sub.metrics.bring_remaining

      assert_equal sub['metrics_classes_i'], created_sub.metrics.classes
      assert_equal sub['metrics_individuals_i'], created_sub.metrics.individuals
      assert_equal sub['metrics_properties_i'], created_sub.metrics.properties
      assert_equal sub['metrics_maxDepth_i'], created_sub.metrics.maxDepth
      assert_equal sub['metrics_maxChildCount_i'], created_sub.metrics.maxChildCount
      assert_equal sub['metrics_averageChildCount_i'], created_sub.metrics.averageChildCount
      assert_equal sub['metrics_classesWithOneChild_i'], created_sub.metrics.classesWithOneChild
      assert_equal sub['metrics_classesWithMoreThan25Children_i'], created_sub.metrics.classesWithMoreThan25Children
      assert_equal sub['metrics_classesWithNoDefinition_i'], created_sub.metrics.classesWithNoDefinition

      embed_doc = created_sub.ontology.bring_remaining.embedded_doc
      embed_doc.each do |k, v|
        if v.is_a?(Array)
          assert_equal v, Array(sub["ontology_#{k}"])
        else
          assert_equal v, sub["ontology_#{k}"]
        end
      end
    end
  end

  def test_search_ontology_data
    create_ontologies_and_submissions({
                                        process_submission: true,
                                        process_options: {
                                          process_rdf: true,
                                          extract_metadata: false,
                                          generate_missing_labels: false,
                                          index_all_data: true
                                        },
                                        acronym: 'BROTEST',
                                        name: 'ontTEST Bla',
                                        file_path: 'test/data/ontology_files/thesaurusINRAE_nouv_structure.skos',
                                        ont_count: 1,
                                        submission_count: 1,
                                        ontology_format: 'SKOS'
                                      })
    ont_sub = LinkedData::Models::Ontology.find('BROTEST-0').first
    ont_sub = ont_sub.latest_submission

    refute_empty(ont_sub.submissionStatus.select { |x| x.id['INDEXED_ALL_DATA'] })

    conn = Goo.search_client(:ontology_data)

    count_ids = Goo.sparql_query_client.query("SELECT  (COUNT( DISTINCT ?id) as ?c)  FROM <#{ont_sub.id}> WHERE {?id ?p ?v}")
                   .first[:c]
                   .to_i

    total_triples = Goo.sparql_query_client.query("SELECT  (COUNT(*) as ?c)  FROM <#{ont_sub.id}> WHERE {?s ?p ?o}").first[:c].to_i

    response = conn.search('*', rows: count_ids + 100)
    index_total_triples = response['response']['docs'].map do |doc|
      count = 0
      doc.each_value do |v|
        count += Array(v).size
      end
      count -= 6
      count
    end.sum

    # TODO: fix maybe in future sometime randomly don't index excactly all the triples
    assert_in_delta total_triples, index_total_triples, 100
    assert_in_delta count_ids, response['response']['numFound'], 100

    response = conn.search('*', fq: ' resource_id:"http://opendata.inrae.fr/thesaurusINRAE/c_10065"')

    assert_equal 1, response['response']['numFound']
    doc = response['response']['docs'].first

    expected_doc = {
      'id' => 'http://opendata.inrae.fr/thesaurusINRAE/c_10065_BROTEST-0',
      'submission_id_t' => 'http://data.bioontology.org/ontologies/BROTEST-0/submissions/1',
      'ontology_t' => 'BROTEST-0',
      'resource_id' => 'http://opendata.inrae.fr/thesaurusINRAE/c_10065',
      'type_txt' => %w[http://www.w3.org/2004/02/skos/core#Concept http://www.w3.org/2002/07/owl#NamedIndividual],
      'http___www.w3.org_2004_02_skos_core_inScheme_txt' => %w[http://opendata.inrae.fr/thesaurusINRAE/thesaurusINRAE http://opendata.inrae.fr/thesaurusINRAE/mt_53],
      'http___www.w3.org_2004_02_skos_core_broader_t' => 'http://opendata.inrae.fr/thesaurusINRAE/c_9937',
      'http___www.w3.org_2004_02_skos_core_altLabel_txt' => ['GMO food',
                                                             'aliment transgénique',
                                                             'aliment OGM',
                                                             'transgenic food'],
      'http___www.w3.org_2004_02_skos_core_prefLabel_txt' => ['genetically modified food',
                                                              'aliment génétiquement modifié'],
      'resource_model' => 'ontology_submission'
    }

    doc.delete('_version_')

    assert_equal expected_doc['id'], doc['id']
    assert_equal expected_doc['submission_id_t'], doc['submission_id_t']
    assert_equal expected_doc['ontology_t'], doc['ontology_t']
    assert_equal expected_doc['resource_id'], doc['resource_id']
    assert_equal expected_doc['type_txt'].sort, doc['type_txt'].sort
    assert_equal expected_doc['http___www.w3.org_2004_02_skos_core_inScheme_txt'].sort, doc['http___www.w3.org_2004_02_skos_core_inScheme_txt'].sort
    assert_equal expected_doc['http___www.w3.org_2004_02_skos_core_broader_t'], doc['http___www.w3.org_2004_02_skos_core_broader_t']
    assert_equal expected_doc['http___www.w3.org_2004_02_skos_core_altLabel_txt'].sort, doc['http___www.w3.org_2004_02_skos_core_altLabel_txt'].sort
    assert_equal expected_doc['http___www.w3.org_2004_02_skos_core_prefLabel_txt'].sort, doc['http___www.w3.org_2004_02_skos_core_prefLabel_txt'].sort
    assert_equal expected_doc['resource_model'], doc['resource_model']
  end

end

