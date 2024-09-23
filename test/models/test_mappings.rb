require_relative "./test_ontology_common"
require "logger"

class TestMapping < LinkedData::TestOntologyCommon


  ONT_ACR1 = 'MAPPING_TEST1'
  ONT_ACR2 = 'MAPPING_TEST2'
  ONT_ACR3 = 'MAPPING_TEST3'
  ONT_ACR4 = 'MAPPING_TEST4'


  def self.before_suite
    backend_4s_delete
    ontologies_parse
  end

  def self.ontologies_parse
    helper = LinkedData::TestOntologyCommon.new(self)
    helper.submission_parse(ONT_ACR1,
                     "MappingOntTest1",
                     "./test/data/ontology_files/BRO_v3.3.owl", 11,
                     process_rdf: true, extract_metadata: false)
    helper.submission_parse(ONT_ACR2,
                     "MappingOntTest2",
                     "./test/data/ontology_files/CNO_05.owl", 22,
                     process_rdf: true, extract_metadata: false)
    helper.submission_parse(ONT_ACR3,
                     "MappingOntTest3",
                     "./test/data/ontology_files/aero.owl", 33,
                     process_rdf: true, extract_metadata: false)
    helper.submission_parse(ONT_ACR4,
                     "MappingOntTest4",
                     "./test/data/ontology_files/fake_for_mappings.owl", 44,
                     process_rdf: true, extract_metadata: false)
  end

  def test_mapping_count_models
    LinkedData::Models::MappingCount.where.all(&:delete)

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
    LinkedData::Models::MappingCount.where.all(&:delete)
  end



  def test_mappings_ontology
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end

    assert create_count_mapping > 2
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
    assert mappings.length > 0
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
    assert create_count_mapping > 2

    by_ont_counts = LinkedData::Mappings.mapping_ontologies_count(latest_sub,nil)
    total = 0
    by_ont_counts.each do |k,v|
      total += v
    end
    assert(by_ont_counts.length == 2)
    ["MAPPING_TEST2", "MAPPING_TEST4"].each do |x|
      assert(by_ont_counts.include?(x))
    end
    assert_equal(by_ont_counts["MAPPING_TEST2"], 10)
    assert_equal(by_ont_counts["MAPPING_TEST4"], 8)
    assert_equal(total, 18)
    assert_equal(mappings.length, 18)
    assert_equal(same_uri,10)
    assert_equal(cui, 3)
    assert_equal(loom,5)
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
    assert create_count_mapping > 2, "Mapping count should exceed the value of 2"
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

    assert_equal(count, mappings.length)
    assert_equal(5, same_uri)
    assert_equal(1, cui)
    assert_equal(2, loom)
  end

  def test_mappings_rest
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
    mapping_term_a, mapping_term_b, submissions_a, submissions_b, relations, user = rest_mapping_data

    mappings_created = []

    3.times do |i|
      classes = get_mapping_classes(term_a:mapping_term_a[i], term_b: mapping_term_b[i],
                                    submissions_a: submissions_a[i], submissions_b: submissions_b[i])

      mappings_created << create_rest_mapping(relation: RDF::URI.new(relations[i]),
                                              user: user,
                                              classes: classes,
                                              name: "proc#{i}")
    end

    ont_id = submissions_a.first.split("/")[0..-3].join("/")
    latest_sub = LinkedData::Models::Ontology.find(RDF::URI.new(ont_id)).first.latest_submission
    LinkedData::Mappings.create_mapping_counts(Logger.new(TestLogFile.new))
    ct = LinkedData::Models::MappingCount.where.all.length
    assert_operator 2, :<, ct
    mappings = LinkedData::Mappings.mappings_ontology(latest_sub, 1, 1000)
    rest_mapping_count = 0

    mappings.each do |m|
      if m.source == "REST"
        rest_mapping_count += 1
        assert_equal 2, m.classes.length
        c1 = m.classes.select {
                        |c| c.submission.id.to_s["TEST1"] }.first
        c2 = m.classes.select {
                        |c| c.submission.id.to_s["TEST2"] }.first
        refute_nil c1
        refute_nil c2
        ia = mapping_term_a.index c1.id.to_s
        ib = mapping_term_b.index c2.id.to_s
        refute_nil ia
        refute_nil ib
        assert_equal ia, ib
      end
    end
    assert_equal 3, rest_mapping_count
    # in a new submission we should have moved the rest mappings
    helper = LinkedData::TestOntologyCommon.new(self)
    helper.submission_parse(ONT_ACR1,
                     "MappingOntTest1",
                     "./test/data/ontology_files/BRO_v3.3.owl", 12,
                     process_rdf: true, extract_metadata: false)

    assert create_count_mapping > 2

    latest_sub1 = LinkedData::Models::Ontology.find(RDF::URI.new(ont_id)).first.latest_submission
    LinkedData::Mappings.create_mapping_counts(Logger.new(TestLogFile.new))
    ct1 = LinkedData::Models::MappingCount.where.all.length
    assert_operator 2, :<, ct1
    mappings = LinkedData::Mappings.mappings_ontology(latest_sub1, 1, 1000)
    rest_mapping_count = 0
    mappings.each do |m|
      rest_mapping_count += 1 if m.source == "REST"
    end
    assert_equal 3, rest_mapping_count

    mappings_created.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
  end

  def test_get_rest_mapping
    mapping_term_a, mapping_term_b, submissions_a, submissions_b, relations, user = rest_mapping_data

    classes = get_mapping_classes(term_a:mapping_term_a[0], term_b: mapping_term_b[0],
                                  submissions_a: submissions_a[0], submissions_b: submissions_b[0])

    mappings_created = []
    mappings_created << create_rest_mapping(relation: RDF::URI.new(relations[0]),
                                            user: user,
                                            classes: classes,
                                            name: "proc#{0}")

    assert_equal 1, mappings_created.size
    created_mapping_id = mappings_created.first.id

    refute_nil LinkedData::Mappings.get_rest_mapping(created_mapping_id)

    old_replace = LinkedData.settings.replace_url_prefix
    LinkedData.settings.replace_url_prefix = true

    old_rest_url = LinkedData.settings.rest_url_prefix
    LinkedData.settings.rest_url_prefix = 'data.test.org'

    refute_nil LinkedData::Mappings.get_rest_mapping(LinkedData::Models::Base.replace_url_id_to_prefix(created_mapping_id))

    LinkedData.settings.rest_url_prefix = old_rest_url
    LinkedData.settings.replace_url_prefix = old_replace

    mappings_created.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
  end

  private

  def get_mapping_classes(term_a:, term_b:, submissions_a:, submissions_b:)
    classes = []
    classes << LinkedData::Mappings.read_only_class(
      term_a, submissions_a)
    classes << LinkedData::Mappings.read_only_class(
      term_b, submissions_b)
    classes
  end

  def rest_mapping_data
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
    refute_nil user

    [mapping_term_a, mapping_term_b, submissions_a, submissions_b, relations, user]
  end

  def create_rest_mapping(relation:, user:, name:, classes:)
    process = LinkedData::Models::MappingProcess.new
    process.name = name
    process.relation = relation
    process.creator = user
    process.save
    LinkedData::Mappings.create_rest_mapping(classes, process)
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
end
