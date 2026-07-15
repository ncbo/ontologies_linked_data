require_relative "./test_ontology_common"
require "logger"

class TestClassModel < LinkedData::TestOntologyCommon

  def test_class_parents

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_7"

    cls = LinkedData::Models::Class.find(class_id).in(os).include(:parents).to_a[0]
    pp = cls.parents[0]
    assert_equal(os.id, pp.submission.id)
    pp.bring(:parents)
    assert pp.parents.length == 1
    assert_equal(os.id, pp.parents.first.submission.id)

    # read_only
    cls = LinkedData::Models::Class.find(class_id).in(os).include(:parents).read_only.all[0]
    pp = cls.parents[0]
    assert_equal(os.id, pp.submission.id)

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    cls = LinkedData::Models::Class.find(class_id).in(os).include(:parents).first
    parents = cls.parents
    assert_equal(parents, cls.parents)
    assert_equal(3, cls.parents.length)
    parent_ids = ["http://bioportal.bioontology.org/ontologies/msotes#class2",
                  "http://bioportal.bioontology.org/ontologies/msotes#class4",
                  "http://bioportal.bioontology.org/ontologies/msotes#class3"]
    parent_id_db = cls.parents.map { |x| x.id.to_s }
    assert_equal(parent_id_db.sort, parent_ids.sort)

    assert !cls.parents[0].submission.nil?
    # they should have the same submission
    assert_equal(cls.parents[0].submission, os)

    # transitive
    cls.bring(:ancestors)
    assert_includes cls.loaded_attributes.to_a, :ancestors
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

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr],
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
    assert_equal(children_id, cls.children[0].id.to_s)

    # they should have the same submission
    assert_equal(cls.children[0].submission, os)

    # transitive
    cls.bring(:descendants)
    assert_includes cls.loaded_attributes.to_a, :descendants
    descendants = cls.descendants.dup
    descendants.map! { |a| a.id.to_s }
    data_descendants = ["http://bioportal.bioontology.org/ontologies/msotes#class_5",
                        "http://bioportal.bioontology.org/ontologies/msotes#class2",
                        "http://bioportal.bioontology.org/ontologies/msotes#class_7"]
    assert descendants.sort == data_descendants.sort
    page = cls.retrieve_descendants(page = 2, size = 2)
    assert page.total_pages == 2
    assert page.prev_page == 1
    assert page.next_page == nil
    assert page.aggregate == 3
    assert page[0].id.to_s == data_descendants[2]

    cls = LinkedData::Models::Class.find(class_id).in(os)
                                   .to_a[0]
    cls.load_has_children
    has_c = cls.hasChildren
    assert_equal(has_c, true)
    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_7"
    cls = LinkedData::Models::Class.find(class_id).in(os)
                                   .to_a[0]
    cls.load_has_children
    has_c = cls.hasChildren
    assert_equal(has_c, false)
  end

  def test_path_to_root

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
    # sort the array by the 0s element id
    paths = paths.sort {|a, b| a[0].nil? ? -1 : b[0].nil? ? 1 : a[0].id.to_s <=> b[0].id.to_s}.select { |x| x.length == 3 }
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

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::URI.new "http://bioportal.bioontology.org/ontologies/msotes#class2"
    cls = LinkedData::Models::Class.find(class_id).in(os).include(:unmapped).first
    versionInfo = Goo.vocabulary(:owl)[:versionInfo]
    uris = cls.properties.keys.map {|k| k.to_s}
    assert uris.include?(versionInfo.to_s)

    bad_property = "http://data.bioontology.org/metadata/def/mappingLoom"
    assert !uris.include?(bad_property)

    cls.properties.each do |k,v|
      if k == versionInfo
        assert v[0].value == "some version info"
      end
    end
  end

  def test_children_count

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
    assert root_backend.id.to_s == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"
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
        assert tree_backend.children.select { |x| x.id.to_s == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis" }.length == 1
        assert tree_backend.children.length == 2
        assert tree_backend.children.first.childrenCount == 0
        assert tree_backend.children[1].childrenCount == 0
      end
      tree_backend = next_tree
      levels += 1
    end
  end

  # Guards the hasChildren <-> childrenCount contract on every node of a built
  # tree. The batched hasChildren optimization derives hasChildren from the
  # child-count aggregate, so this asserts the two stay consistent and that
  # hasChildren is always loaded (never raises) on tree nodes.
  def test_bro_tree_has_children
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os).first

    tree_root = cls.tree

    checked = 0
    stack = [tree_root]
    until stack.empty?
      node = stack.pop

      hc = node.hasChildren
      assert_includes [true, false], hc, "hasChildren not a boolean for #{node.id}"

      cc = node.aggregates ? node.childrenCount : nil
      unless cc.nil?
        assert_equal((cc > 0), hc, "hasChildren/childrenCount mismatch for #{node.id}")
        checked += 1
      end

      stack.concat(node.children)
    end

    assert checked > 0, "expected at least one node with a child-count aggregate"
  end

  # N+1 guard for the class-tree endpoint (OWL). Serializing a tree must resolve
  # the submission's languages once, not once per node -- before the get_languages
  # `bring?` guard (ncbo/ontologies_linked_data#302) serialization issued extra
  # naturalLanguage queries per serialized node.
  def test_bro_tree_serialize_no_n_plus_1
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    # The hypermedia links serialized per node need submission.ontology.acronym,
    # exactly as the controller has it loaded; preload so serialization runs.
    os.bring(:ontology) if os.bring?(:ontology)
    os.ontology.bring(:acronym) if os.ontology.bring?(:acronym)

    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    display_attrs = [:prefLabel, :hasChildren, :children, :obsolete, :subClassOf]
    cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os).include(display_attrs).first
    tree_root = cls.tree

    node_count = 0
    stack = [tree_root]
    until stack.empty?
      n = stack.pop
      node_count += 1
      stack.concat(n.children)
    end
    assert_operator node_count, :>=, 3, "tree too small to be a meaningful N+1 guard"

    serialize_queries = count_sparql_queries do
      LinkedData::Serializers::JSON.serialize([tree_root], only: display_attrs)
    end

    # Constant bound, calibrated by mutation testing: with the #302 guard this is
    # 1 query; with the guard reverted it is 8 on this 29-node fixture. A
    # node-count-relative bound (`< node_count`) passes BOTH ways on OWL and
    # guards nothing.
    assert_operator serialize_queries, :<=, 2,
      "serialization issued #{serialize_queries} SPARQL queries for #{node_count} tree nodes -- " \
      "looks like a per-node N+1 (see get_languages guard in ncbo/ontologies_linked_data#302)"
  end

  # Regression guard for the build-phase fix of #302 (fixes #303): for a non-SKOS
  # (OWL) submission, load_is_in_scheme must not run the ConceptScheme query at
  # all -- isInActiveScheme is SKOS-only, and pre-#302 every tree node issued a
  # scheme query that always returned nothing. Also pins the intended value
  # change: [] rather than [nil] (serialized [null]) for non-SKOS.
  # Mutation-verified: pre-#302 this counts one scheme query per call.
  def test_owl_load_is_in_scheme_skips_scheme_query
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os).first
    # Hoist the one legitimate load (hasOntologyLanguage, used by submission.skos?)
    # so the counter isolates the scheme query itself.
    os.bring(:hasOntologyLanguage) if os.bring?(:hasOntologyLanguage)

    queries = count_sparql_queries { 2.times { cls.load_is_in_scheme([]) } }
    assert_equal 0, queries,
      "load_is_in_scheme on a non-SKOS submission issued #{queries} SPARQL queries -- " \
      'the skos? gate (#302/#303) regressed'
    assert_equal [], cls.isInActiveScheme,
      'non-SKOS isInActiveScheme must be [] (not [nil]) per #302'
  end


  def test_include_ancestors
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    assert_raises ArgumentError do
      cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os)
                                      .include(:prefLabel,ancestors: [:prefLabel]).first
    end
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

    #xref test in bro
    classId = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource"
    classIR = LinkedData::Models::Class.find(RDF::URI.new(classId))
      .in(os).include(:xref,:prefLabel).first
    assert_equal(classIR.xref, "hasDbXref0000001")
    assert_equal(classIR.prefLabel, "Information Resource")

  end

  def test_xml_literal_serialization
    comment = "A form of cancer that begins in melanocytes (cells that make the pigment melanin). It may begin in a mole (skin melanoma), but can also begin in other pigmented tissues, such as in the eye or in the intestines.NCI-GLOSS"
    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class6"

    cls = LinkedData::Models::Class.find(class_id).in(os).include(:unmapped).to_a[0]

    cls_hash = cls.to_flex_hash(only: [:properties])
    xml_comment = cls_hash[:properties]["http://www.w3.org/2000/01/rdf-schema#comment"].first
    assert_equal String, xml_comment.class
    assert_equal comment, xml_comment
  end
end
