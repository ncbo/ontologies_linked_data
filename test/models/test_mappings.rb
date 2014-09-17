require_relative "./test_ontology_common"
require "logger"

class TestMapping < LinkedData::TestOntologyCommon


  ONT_ACR1 = 'MAPPING_TEST1'
  ONT_ACR2 = 'MAPPING_TEST2'
  ONT_ACR3 = 'MAPPING_TEST3'
  ONT_ACR4 = 'MAPPING_TEST4'


  def self.before_suite
    LinkedData::TestCase.backend_4s_delete
    ontologies_parse()
  end

  def self.ontologies_parse()
    return
    helper = LinkedData::TestOntologyCommon.new(self)
    helper.submission_parse(ONT_ACR1,
                     "MappingOntTest1",
                     "./test/data/ontology_files/BRO_v3.3.owl", 11,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
    helper.submission_parse(ONT_ACR2,
                     "MappingOntTest2",
                     "./test/data/ontology_files/CNO_05.owl", 22,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
    helper.submission_parse(ONT_ACR3,
                     "MappingOntTest3",
                     "./test/data/ontology_files/aero.owl", 33,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
    helper.submission_parse(ONT_ACR4,
                     "MappingOntTest4",
                     "./test/data/ontology_files/fake_for_mappings.owl", 44,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
  end

  def test_mapping_count_models
    LinkedData::Models::MappingCount.where.all do |x|
      x.delete
    end
    m = LinkedData::Models::MappingCount.new
    assert !m.valid?
    m.ontologies = ["BRO"]
    m.pair_count = false
    m.count = 123
    assert m.valid?
    m.save
    assert LinkedData::Models::MappingCount.where(ontologies: "BRO").all.count == 1
    m = LinkedData::Models::MappingCount.new
    assert !m.valid?
    m.ontologies = ["BRO","FMA"]
    m.count = 321
    m.pair_count = true
    assert m.valid?
    m.save
    assert LinkedData::Models::MappingCount.where(ontologies: "BRO").all.count == 2
    result = LinkedData::Models::MappingCount.where(ontologies: "BRO")
                                      .and(ontologies: "FMA").include(:count).all
    assert result.length == 1
    assert result.first.count == 321
    result = LinkedData::Models::MappingCount.where(ontologies: "BRO")
                                                .and(pair_count: true)
                                                .include(:count)
                                                .all
    assert result.length == 1
    assert result.first.count == 321
  end

  def validate_mapping(map)
    prop = map.source.downcase.to_sym
    prop = :prefLabel if map.source == "LOOM"
    prop = nil if map.source == "SAME_URI"

    classes = []
    map.classes.each do |t|
      sub = LinkedData::Models::Ontology.find(t.submission.ontology.id)
                .first.latest_submission
      cls = LinkedData::Models::Class.find(t.id).in(sub)
      unless prop.nil?
        cls.include(prop)
      end
      cls = cls.first
      classes << cls unless cls.nil?
    end
    if map.source == "SAME_URI"
      return classes[0].id.to_s == classes[1].id.to_s
    end
    if map.source == "LOOM"
      ldOntSub = LinkedData::Models::OntologySubmission
      label0 = ldOntSub.loom_transform_literal(classes[0].prefLabel)
      label1 = ldOntSub.loom_transform_literal(classes[1].prefLabel)
      return label0 == label1
    end
    if map.source == "CUI"
      return classes[0].cui == classes[1].cui
    end
    return false
  end

  def test_mappings_ontology
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
    #bro
    ont1 = LinkedData::Models::Ontology.where({ :acronym => ONT_ACR1 }).to_a[0]

    latest_sub = ont1.latest_submission
    latest_sub.bring(ontology: [:acronym])
    keep_going = true
    mappings = []
    size = 10
    page_no = 1
    while keep_going
      page = LinkedData::Mappings.mappings_ontology(latest_sub,page_no, size)
      assert_instance_of(Goo::Base::Page, page)
      keep_going = (page.length == size)
      mappings += page
      page_no += 1
    end
    cui = 0
    same_uri = 0
    loom = 0
    mappings.each do |map|
      assert_equal(map.classes[0].submission.ontology.acronym,
                   latest_sub.ontology.acronym)
      if map.source == "CUI"
        cui += 1
      elsif map.source == "SAME_URI"
        same_uri += 1
      elsif map.source == "LOOM"
        loom += 1
      else
        assert 1 == 0, "unknown source for this ontology #{map.source}"
      end
      assert validate_mapping(map), "mapping is not valid"
    end
    by_ont_counts = LinkedData::Mappings.mapping_ontologies_count(latest_sub,nil)
    total = 0
    by_ont_counts.each do |k,v|
      total += v
    end
    assert_equal(by_ont_counts.length, 3)
    ["MAPPING_TEST2", "MAPPING_TEST3", "MAPPING_TEST4"].each do |x|
      assert(by_ont_counts.include?(x))
    end
    assert_equal(by_ont_counts["MAPPING_TEST2"], 10)
    assert_equal(by_ont_counts["MAPPING_TEST3"], 9)
    assert_equal(by_ont_counts["MAPPING_TEST4"], 8)
    assert_equal(total, 27)
    assert_equal(mappings.length, 27)
    assert_equal(same_uri,10)
    assert_equal(cui, 3)
    assert_equal(loom,14)
    mappings.each do |map|
      class_mappings = LinkedData::Mappings.mappings_ontology(
                        latest_sub,1,100,map.classes[0].id)
      assert class_mappings.length > 0
      class_mappings.each do |cmap|
        assert validate_mapping(map)
      end
    end
  end

  def test_mappings_two_ontologies
    #bro
    ont1 = LinkedData::Models::Ontology.where({ :acronym => ONT_ACR1 }).to_a[0]
    #fake ont
    ont2 = LinkedData::Models::Ontology.where({ :acronym => ONT_ACR4 }).to_a[0]

    latest_sub1 = ont1.latest_submission
    latest_sub1.bring(ontology: [:acronym])
    latest_sub2 = ont2.latest_submission
    latest_sub2.bring(ontology: [:acronym])
    keep_going = true
    mappings = []
    size = 5 
    page_no = 1
    while keep_going
      page = LinkedData::Mappings.mappings_ontologies(latest_sub1,latest_sub2,
                                                    page_no, size)
      assert_instance_of(Goo::Base::Page, page)
      keep_going = (page.length == size)
      mappings += page
      page_no += 1
    end
    cui = 0
    same_uri = 0
    loom = 0
    mappings.each do |map|
      assert_equal(map.classes[0].submission.ontology.acronym, 
                   latest_sub1.ontology.acronym)
      assert_equal(map.classes[1].submission.ontology.acronym,
                  latest_sub2.ontology.acronym)
      if map.source == "CUI"
        cui += 1
      elsif map.source == "SAME_URI"
        same_uri += 1
      elsif map.source == "LOOM"
        loom += 1
      else
        assert 1 == 0, "unknown source for this ontology #{map.source}"
      end
      assert validate_mapping(map), "mapping is not valid"
    end
    count = LinkedData::Mappings.mapping_ontologies_count(latest_sub1,
                                                          latest_sub2)

    assert_equal(mappings.length, count)
    assert_equal(same_uri,5)
    assert_equal(cui, 1)
    assert_equal(loom,2)
  end

  def test_mappings_rest
    mapping_term_a = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Image_Algorithm",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Image",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Integration_and_Interoperability_Tools" ]
    submissions_a = [
"http://data.bioontology.org/ontologies/MAPPING_TEST1/submissions/latest",
"http://data.bioontology.org/ontologies/MAPPING_TEST1/submissions/latest",
"http://data.bioontology.org/ontologies/MAPPING_TEST1/submissions/latest" ]



    mapping_term_b = ["http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000202",
      "http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000203",
      "http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000205" ]
    submissions_b = [
"http://data.bioontology.org/ontologies/MAPPING_TEST2/submissions/latest",
"http://data.bioontology.org/ontologies/MAPPING_TEST2/submissions/latest",
"http://data.bioontology.org/ontologies/MAPPING_TEST2/submissions/latest" ]

    relations = [ "http://www.w3.org/2004/02/skos/core#exactMatch",
                  "http://www.w3.org/2004/02/skos/core#closeMatch",
                  "http://www.w3.org/2004/02/skos/core#relatedMatch" ]
    user = LinkedData::Models::User.where.include(:username).all[0]
    assert user != nil
    3.times do |i|
      process = LinkedData::Models::MappingProcess.new
      process.name = "proc#{i}"
      process.relation = RDF::URI.new(relations[i])
      process.creator= user
      process.save
      classes = []
      classes << LinkedData::Mappings.read_only_class(
                    mapping_term_a[i], submissions_a[i])
      classes << LinkedData::Mappings.read_only_class(
                    mapping_term_b[i], submissions_b[i])
      LinkedData::Mappings.create_rest_mapping(classes,process)
    end
    ont_id = submissions_a.first.split("/")[0..-3].join("/")
    latest_sub = LinkedData::Models::Ontology
                    .find(RDF::URI.new(ont_id))
                    .first
                    .latest_submission
    mappings = LinkedData::Mappings.mappings_ontology(latest_sub,1,1000)
    rest_mapping_count = 0
    mappings.each do |m|
      if m.source == "REST"
        rest_mapping_count += 1
        assert_equal m.classes.length, 2
        c1 =  m.classes.select { 
                        |c| c.submission.id.to_s["TEST1"] }.first
        c2 = m.classes.select { 
                        |c| c.submission.id.to_s["TEST2"] }.first
        assert c1 != nil
        assert c2 != nil
        ia = mapping_term_a.index c1.id.to_s
        ib = mapping_term_b.index c2.id.to_s
        assert ia != nil
        assert ib != nil
        assert ia == ib
      end
    end
    assert_equal rest_mapping_count, 3
    
    #in a new submission we should have moved the rest mappings

    helper = LinkedData::TestOntologyCommon.new(self)
    helper.submission_parse(ONT_ACR1,
                     "MappingOntTest1",
                     "./test/data/ontology_files/BRO_v3.3.owl", 12,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
    latest_sub = LinkedData::Models::Ontology
                    .find(RDF::URI.new(ont_id))
                    .first
                    .latest_submission
    mappings = LinkedData::Mappings.mappings_ontology(latest_sub,1,1000)
    rest_mapping_count = 0
    mappings.each do |m|
      if m.source == "REST"
        rest_mapping_count += 1
      end
    end
    assert rest_mapping_count == 3
  end

end
