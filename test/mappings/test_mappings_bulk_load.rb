require_relative '../models/test_ontology_common'
require 'logger'

class TestMappingBulkLoad < LinkedData::TestOntologyCommon

  ONT_ACR1 = 'MAPPING_TEST1'
  ONT_ACR2 = 'MAPPING_TEST2'

  def self.before_suite
    LinkedData::TestCase.backend_4s_delete
    self.ontologies_parse
  end

  def self.ontologies_parse
    helper = LinkedData::TestOntologyCommon.new(self)
    helper.submission_parse(ONT_ACR1,
                            'MappingOntTest1',
                            './test/data/ontology_files/BRO_v3.3.owl', 11,
                            process_rdf: true, index_search: true,
                            run_metrics: false, reasoning: true)
    helper.submission_parse(ONT_ACR2,
                            'MappingOntTest2',
                            './test/data/ontology_files/CNO_05.owl', 22,
                            process_rdf: true, index_search: true,
                            run_metrics: false, reasoning: true)
  end

  def test_mapping_classes_found
    ontology_id = 'http://bioontology.org/ontologies/BiomedicalResources.owl'
    mapping_hash = {
      "classes": %w[http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Image_Algorithm
                    http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000202],

      "name": 'This is the mappings produced to test the bulk load',
      "source": 'https://w3id.org/semapv/LexicalMatching',
      "comment": 'mock data',
      "relation": [
        'http://www.w3.org/2002/07/owl#subClassOf'
      ],
      "subject_source_id": 'http://bioontology.org/ontologies/BiomedicalResources.owl',
      "object_source_id": 'http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl',
      "source_name": 'https://w3id.org/sssom/mapping/tests/data/basic.tsv',
      "source_contact_info": 'orcid:1234,orcid:5678',
      "date": '2020-05-30'

    }
    commun_test(mapping_hash, ontology_id)
  end

  def test_mapping_classes_not_found
    ontology_id = 'http://bioontology.org/ontologies/BiomedicalResources.owl'
    mapping_hash = {
      "classes": %w[http://bioontology.org/ontologies/test_1
                    http://purl.org/incf/ontology/Computational_Neurosciences/test_2],

      "name": 'This is the mappings produced to test the bulk load',
      "source": 'https://w3id.org/semapv/LexicalMatching',
      "comment": 'mock data',
      "relation": [
        'http://www.w3.org/2002/07/owl#subClassOf'
      ],
      "subject_source_id": 'http://bioontology.org/ontologies/BiomedicalResources.owl',
      "object_source_id": 'http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl',
      "source_name": 'https://w3id.org/sssom/mapping/tests/data/basic.tsv',
      "source_contact_info": 'orcid:1234,orcid:5678',
      "date": '2020-05-30'

    }
    assert_raises ArgumentError do
      mapping_load(mapping_hash, ontology_id)
    end
  end

  def test_mapping_ontologies_not_found
    ontology_id = 'http://bioontology.org/ontologies/BiomedicalResources.owl'
    mapping_hash = {
      "classes": %w[http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Image_Algorithm
                    http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#test2],

      "name": 'This is the mappings produced to test the bulk load',
      "source": 'https://w3id.org/semapv/LexicalMatching',
      "comment": 'mock data',
      "relation": [
        'http://www.w3.org/2002/07/owl#subClassOf'
      ],
      "source_name": 'https://w3id.org/sssom/mapping/tests/data/basic.tsv',
      "source_contact_info": 'orcid:1234,orcid:5678',
      "date": '2020-05-30'

    }
    assert_raises ArgumentError do
      commun_test(mapping_hash, ontology_id)
    end

  end

  private

  def delete_rest_mappings
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
  end

  def commun_test(mapping_hash, ontology_id)
    mappings = mapping_load(mapping_hash, ontology_id)
    selected = mappings.select do |m|
      m.source == 'REST' &&
        m.classes.first.id.to_s['Image_Algorithm'] &&
        m.classes.last.id.to_s['cno_0000202']
    end
    selected = selected.first
    refute_nil selected
    assert_equal Array(selected.process.relation),
                 ['http://www.w3.org/2002/07/owl#subClassOf']

    assert_equal selected.process.subject_source_id.to_s,
                 'http://bioontology.org/ontologies/BiomedicalResources.owl'

    assert_equal selected.process.object_source_id.to_s,
                 'http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl'

  end

  def mapping_load(mapping_hash, ontology_id)
    delete_rest_mappings
    user_name = 'test_mappings_user'
    user = LinkedData::Models::User.where(username: user_name).include(:username).first
    if user.nil?
      user = LinkedData::Models::User.new(username: user_name, email: 'some@email.org')
      user.passwordHash = 'some random pass hash'
      user.save
    end
    loaded, errors = LinkedData::Mappings.bulk_load_mappings([mapping_hash], user, check_exist: true)

    raise ArgumentError, errors unless errors.empty?

    LinkedData::Mappings.create_mapping_counts(Logger.new(TestLogFile.new))
    ct = LinkedData::Models::MappingCount.where.all.length
    assert ct > 2
    o = LinkedData::Models::Ontology.where(submissions: { uri: ontology_id })
                                    .include(submissions: %i[submissionId submissionStatus])
                                    .first
    latest_sub = o.nil? ? nil : o.latest_submission
    LinkedData::Mappings.mappings_ontology(latest_sub, 1, 1000)

  end
end

