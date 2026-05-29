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

  def test_term_search_exact_fields_are_case_insensitive
    schema_generator = SOLR::SolrSchemaGenerator.new
    LinkedData::Models::Class.index_schema(schema_generator)

    exact_fields = schema_generator.fields_to_add.select { |field| %w[prefLabelExact synonymExact].include?(field[:name]) }
    exact_dynamic_fields = schema_generator.dynamic_fields_to_add.select { |field| %w[prefLabelExact_* synonymExact_*].include?(field[:name]) }
    ontology_rank_field = schema_generator.fields_to_add.find { |field| field[:name] == 'ontologyRank' }

    assert_equal %w[prefLabelExact synonymExact], exact_fields.map { |field| field[:name] }.sort
    assert_equal %w[prefLabelExact_* synonymExact_*], exact_dynamic_fields.map { |field| field[:name] }.sort
    assert exact_fields.all? { |field| field[:type] == 'string_ci' }
    assert exact_dynamic_fields.all? { |field| field[:type] == 'string_ci' }
    refute_nil ontology_rank_field
    assert_equal 'pfloat', ontology_rank_field[:type]
    assert_equal '0.0', ontology_rank_field[:default]
  end

  def test_ontology_rank_for_index_uses_normalized_score
    begin
      LinkedData::Models::Class.instance_variable_set(:@ontology_rank_cache, {
        'RANKED' => { normalizedScore: 0.884 }
      })

      assert_equal 0.884, LinkedData::Models::Class.ontology_rank_for_index('RANKED')
      assert_equal 0.0, LinkedData::Models::Class.ontology_rank_for_index('UNRANKED')
    ensure
      LinkedData::Models::Class.reset_ontology_rank_cache
    end
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
    submission_fq = "submission_id_t:\"#{ont_sub.id}\""

    count_ids = Goo.sparql_query_client.query("SELECT  (COUNT( DISTINCT ?id) as ?c)  FROM <#{ont_sub.id}> WHERE {?id ?p ?v}")
                   .first[:c]
                   .to_i

    total_triples = Goo.sparql_query_client.query("SELECT  (COUNT(*) as ?c)  FROM <#{ont_sub.id}> WHERE {?s ?p ?o}").first[:c].to_i

    response = conn.search('*', fq: submission_fq, rows: count_ids + 100)
    # Count only RDF predicate-derived fields:
    # - `type_t` / `type_txt`
    # - escaped URI predicate fields (e.g., `http___..._t` / `http___..._txt`)
    # This avoids counting Solr metadata/copy fields whose presence varies by schema.
    rdf_field = lambda do |field_name|
      field_name == 'type_t' ||
        field_name == 'type_txt' ||
        (field_name.end_with?('_t', '_txt') && field_name.match?(/\A[a-z]+___/))
    end
    index_total_triples = response['response']['docs'].sum do |doc|
      doc.sum do |k, v|
        rdf_field.call(k) ? Array(v).size : 0
      end
    end

    # TODO: fix maybe in future sometime randomly don't index excactly all the triples
    assert_in_delta total_triples, index_total_triples, 200
    assert_in_delta count_ids, response['response']['numFound'], 100

    response = conn.search('*', fq: [submission_fq, 'resource_id:"http://opendata.inrae.fr/thesaurusINRAE/c_10065"'])

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
