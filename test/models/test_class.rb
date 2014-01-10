require_relative "./test_ontology_common"
require "logger"

class TestClassModel < LinkedData::TestOntologyCommon

  def test_class_parents
    return if ENV["SKIP_PARSING"]

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ], 
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_7"

    cls = LinkedData::Models::Class.find(class_id).in(os).include(:parents).to_a[0]
    pp = cls.parents[0]
    assert_equal(os.id,pp.submission.id)
    pp.bring(:parents)
    assert pp.parents.length == 1
    assert_equal(os.id, pp.parents.first.submission.id)

    #read_only
    cls = LinkedData::Models::Class.find(class_id).in(os).include(:parents).read_only.all[0]
    pp = cls.parents[0]
    assert_equal(os.id,pp.submission.id)

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    cls = LinkedData::Models::Class.find(class_id).in(os).include(:parents).first
    parents = cls.parents
    assert_equal(parents, cls.parents)
    assert_equal(3, cls.parents.length)
    parent_ids = [ "http://bioportal.bioontology.org/ontologies/msotes#class2",
      "http://bioportal.bioontology.org/ontologies/msotes#class4",
       "http://bioportal.bioontology.org/ontologies/msotes#class3" ]
    parent_id_db = cls.parents.map { |x| x.id.to_s }
    assert_equal(parent_id_db.sort, parent_ids.sort)

    assert !cls.parents[0].submission.nil?
    #they should have the same submission
    assert_equal(cls.parents[0].submission, os)

    #transitive
    cls.bring(:ancestors)
    ancestors = cls.ancestors.dup
    ancestors.each do |a|
      assert !a.submission.nil?
    end
    assert ancestors.length == cls.ancestors.length
    ancestors.map! { |a| a.id.to_s }
    data_ancestors = ["http://bioportal.bioontology.org/ontologies/msotes#class1",
 "http://bioportal.bioontology.org/ontologies/msotes#class2",
 "http://bioportal.bioontology.org/ontologies/msotes#class4",
 "http://bioportal.bioontology.org/ontologies/msotes#class3"]
    assert ancestors.sort == data_ancestors.sort

  end

  def test_class_children
    return if ENV["SKIP_PARSING"]

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ], 
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class1"

    cls = LinkedData::Models::Class.find(class_id).in(os)
                .include(:parents)
                .include(:children)
                .to_a[0]
    children = cls.children
    assert_equal(1, cls.children.length)
    children_id = "http://bioportal.bioontology.org/ontologies/msotes#class2"
    assert_equal(children_id,cls.children[0].id.to_s)

    #they should have the same submission
    assert_equal(cls.children[0].submission, os)

    #transitive
    cls.bring(:descendants)
    descendants = cls.descendants.dup
    descendants.map! { |a| a.id.to_s }
    data_descendants = ["http://bioportal.bioontology.org/ontologies/msotes#class_5",
 "http://bioportal.bioontology.org/ontologies/msotes#class2",
    "http://bioportal.bioontology.org/ontologies/msotes#class_7"]
    assert descendants.sort == data_descendants.sort

  end

  def test_path_to_root
    return if ENV["SKIP_PARSING"]

    acr = "CSTPROPS"
    init_test_ontology_msotest acr

    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ], 
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_7"

    cls = LinkedData::Models::Class.find(class_id).in(os).first

    paths = cls.paths_to_root
    assert paths.length == 1
    path = paths[0]
    assert path.length == 3
    assert path[2].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class_7"
    assert path[1].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class2"
    assert path[0].id.to_s  == "http://bioportal.bioontology.org/ontologies/msotes#class1"

  end

  def test_path_to_root_with_multiple_parents
    return if ENV["SKIP_PARSING"]

    acr = "CSTPROPS"
    init_test_ontology_msotest acr

    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ], 
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    cls = LinkedData::Models::Class.find(class_id).in(os).first

    paths = cls.paths_to_root
    assert paths.length == 7
    paths = paths.select { |x| x.length == 3 }
    path = paths[0]
    assert path.length == 3
    assert path[2].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    assert path[1].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class2"
    assert path[0].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class1"
    path = paths[1]
    assert path.length == 3
    assert path[2].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    assert path[1].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class4"
    assert path[0].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class3"

  end

  def test_class_all_attributes
    return if ENV["SKIP_PARSING"]

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ], 
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::URI.new "http://bioportal.bioontology.org/ontologies/msotes#class2"
    cls = LinkedData::Models::Class.find(class_id).in(os).include(:unmapped).first
    versionInfo = Goo.vocabulary(:owl)[:versionInfo]
    uris = cls.unmapped.keys.map {|k| k.to_s}
    assert uris.include?(versionInfo.to_s)

    cls.unmapped.each do |k,v|
      if k == versionInfo
        assert v[0].value == "some version info"
      end
    end
  end

  def test_children_count
    return if ENV["SKIP_PARSING"]

    acr = "CSTPROPS"
    init_test_ontology_msotest acr

    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ], 
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]
    clss = LinkedData::Models::Class.in(os)
                .include(:prefLabel)
                .aggregate(:count, :children)
                .all
    clss.each do |c|
      if c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class1"
        assert c.childrenCount == 1
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class2"
        assert c.childrenCount == 2
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class3"
        assert c.childrenCount == 2
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class4"
        assert c.childrenCount == 2
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class97"
        assert c.childrenCount == 1
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class98"
        assert c.childrenCount == 1
      else
        assert c.childrenCount == 0
      end
    end
  end

  def test_bro_tree
    #just one path with children
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    assert os
    cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os).first

    root_backend = cls.tree
    root_backend.id.to_s == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"
    tree_backend = root_backend
    root_backend.children.each do |c|
      assert c.childrenCount > 0
    end
    levels = 0
    while tree_backend and tree_backend.children.length > 0 do
      cc = 0
      next_tree = nil
      tree_backend.children.each do |c|
        assert c.childrenCount != nil
        assert c.prefLabel != nil
        next_tree = c if c.children.length > 0
      end
      assert cc < 2
      if next_tree.nil?
        tree_backend.children.select { |x| x.id.to_s == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis" }.length == 1
        assert tree_backend.children.length == 2
        assert tree_backend.children.first.childrenCount == 0
        assert tree_backend.children[1].childrenCount == 0
      end
      tree_backend = next_tree
      levels += 1
    end
  end


  def test_include_ancestors
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os)
                                      .include(:prefLabel,ancestors: [:prefLabel]).first
    assert cls.ancestors.length == 7
    cls.ancestors.each do |a|
      next if a.id["Thing"]
      assert_instance_of String, a.prefLabel
    end
    assert_instance_of String, cls.prefLabel
  end

  def test_bro_paths_to_root
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os).first

    paths_backend = cls.paths_to_root
    paths = []
    paths_backend.each do |pb|
      paths << pb.map { |x| x.id.to_s }
    end

    path_0 = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Text_Mining",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Mining_and_Inference",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Analysis_Software",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Software",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"].reverse

    path_1 = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Text_Mining",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Natural_Language_Processing",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Analysis_Software",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Software",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"].reverse

    path_2 = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Text_Mining",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Mining_and_Inference",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Analysis",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Analysis_Software",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Software",
 "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"].reverse

    paths.each do |path|
      assert (path == path_0 || path == path_1 || path == path_2)
    end
    assert paths.length == 3
    assert paths[0] != paths[1]
    assert paths[1] != paths[2]
    assert paths[0] != paths[2]

  end

end
