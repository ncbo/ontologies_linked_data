require_relative "./test_ontology_common"
require "logger"

class TestOntologySubmission < LinkedData::TestOntologyCommon
  def setup
  end

  def teardown
    l = LinkedData::Models::Ontology.all
    if l.length > 50
      raise ArgumentError, "Too many ontologies in triple store. TESTS WILL DELETE DATA"
    end
    l.each do |os|
      os.delete
    end
  end

  def test_valid_ontology
    return if ENV["SKIP_PARSING"]

    acronym = "BRO-TST"
    name = "SNOMED-CT TEST"
    ontologyFile = "./test/data/ontology_files/BRO_v3.2.owl"
    id = 10

    owl, bogus, user, status, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", "UPLOADED", name)

    os = LinkedData::Models::OntologySubmission.new
    assert (not os.valid?)

    assert_raises ArgumentError do
      bogus.acronym = acronym
    end
    os.submissionId = id
    os.contact = [contact]
    os.released = DateTime.now - 4
    bogus.name = name
    o = LinkedData::Models::Ontology.find(acronym)
    if o.nil?
      os.ontology = LinkedData::Models::Ontology.new(:acronym => acronym)
    else
      os.ontology = o
    end
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    os.uploadFilePath = uploadFilePath
    os.hasOntologyLanguage = owl
    os.ontology = bogus
    os.submissionStatus = status
    assert os.valid?
  end

  def test_sanity_check_zip
    return if ENV["SKIP_PARSING"]

    acronym = "RADTEST"
    name = "RADTEST Bla"
    ontologyFile = "./test/data/ontology_files/SDO.zip"
    id = 10

    teardown

    owl, rad, user, status, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", "UPLOADED", name)

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    ont_submision.contact = [contact]
    ont_submision.released = DateTime.now - 4
    ont_submision.uploadFilePath = uploadFilePath
    ont_submision.hasOntologyLanguage = owl
    ont_submision.ontology = rad
    ont_submision.submissionStatus = status
    assert (not ont_submision.valid?)
    assert_equal 1, ont_submision.errors.length
    assert_instance_of Hash, ont_submision.errors[:uploadFilePath][0]
    assert_instance_of Array, ont_submision.errors[:uploadFilePath][0][:options]
    assert_instance_of String, ont_submision.errors[:uploadFilePath][0][:message]
    assert (ont_submision.errors[:uploadFilePath][0][:options].length > 0)
    ont_submision.masterFileName = "does not exist"
    ont_submision.valid?
    assert_instance_of Hash, ont_submision.errors[:uploadFilePath][0]
    assert_instance_of Array, ont_submision.errors[:uploadFilePath][0][:options]
    assert_instance_of String, ont_submision.errors[:uploadFilePath][0][:message]

    #choose one from options.
    ont_submision.masterFileName = ont_submision.errors[:uploadFilePath][0][:options][0]
    assert ont_submision.valid?
    assert_equal 0, ont_submision.errors.length
  end

  def test_duplicated_file_names
    return if ENV["SKIP_PARSING"]

    acronym = "DUPTEST"
    name = "DUPTEST Bla"
    ontologyFile = "./test/data/ontology_files/ont_dup_names.zip"
    id = 10

    owl, dup, user, status, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", "UPLOADED", name)
    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => 1,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    ont_submision.contact = [contact]
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.ontology = dup
    ont_submision.submissionStatus = status
    assert (!ont_submision.valid?)
    assert_equal 1, ont_submision.errors.length
    assert_instance_of String, ont_submision.errors[:uploadFilePath][0]
  end

  def test_submission_parse
    submission_parse("BROTEST", "BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 10)

    #This one has some nasty looking IRIS with slashes in the anchor
    submission_parse("MCCLTEST", "MCCLS TEST", "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl", 10)

    #This one has resources wih accents.
    submission_parse("OntoMATEST", "OntoMA TEST", "./test/data/ontology_files/OntoMA.1.1_vVersion_1.1_Date__11-2011.OWL", 10)
  end

  def test_submission_parse_zip
    return if ENV["SKIP_PARSING"]

    acronym = "RADTEST"
    name = "RADTEST Bla"
    ontologyFile = "./test/data/ontology_files/radlex_owl_v3.0.1.zip"
    id = 10

    bro = LinkedData::Models::Ontology.find(acronym)
    if not bro.nil?
      sub = bro.submissions || []
      sub.each do |s|
        s.load
        s.delete
      end
    end

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    assert (not ont_submision.valid?)
    assert_equal 5, ont_submision.errors.length
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, bro, user, status, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", "UPLOADED", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.prefLabelProperty = RDF::URI.new("http://bioontology.org/projects/ontologies/radlex/radlexOwl#Preferred_name")
    ont_submision.ontology = bro
    ont_submision.submissionStatus = status
    ont_submision.contact = [contact]
    assert (ont_submision.valid?)
    ont_submision.save
    ont_submision.process_submission(Logger.new(STDOUT),index_search=false,run_metrics=false)
    assert ont_submision.submissionStatus.parsed?

    LinkedData::Models::Class.in(ont_submision).include(:prefLabel).read_only.each do |cls|
      assert(cls.prefLabel != nil, "Class #{cls.id.to_ntriples} does not have a label")
      assert_instance_of String, cls.prefLabel
    end
  end

  def test_semantic_types
    submission_parse("STY-Test", "STY Bla", "./test/data/ontology_files/umls_semantictypes.ttl", 1)
    ont_sub = LinkedData::Models::Ontology.find("STY-Test").first.latest_submission
    classes = LinkedData::Models::Class.in(ont_sub).include(:prefLabel).read_only.to_a
    assert_equal 133, classes.length
    classes.each do |cls|
      assert(cls.prefLabel != nil, "Class #{cls.id.to_ntriples} does not have a label")
      assert_instance_of String, cls.prefLabel
    end
  end

  def test_custom_property_generation
    return if ENV["SKIP_PARSING"]

    acr = "CSTPROPS"
    init_test_ontology_msotest acr

    o = LinkedData::Models::Ontology.find(acr).first
    o.bring_remaining
    o.bring(:submissions)
    oss = o.submissions
    assert_equal 1, oss.length
    ont_sub = oss[0]
    ont_sub.bring_remaining
    assert ont_sub.submissionStatus.parsed?
    LinkedData::Models::Class.in(ont_sub).include(:prefLabel,:synonym).read_only.each do |c|
      assert (not c.prefLabel.nil?)
      assert_instance_of String, c.prefLabel
      if c.id.to_s.include? "class6"
        #either the RDF label of the synonym
        assert ("rdfs label value" == c.prefLabel || "syn for class 6" == c.prefLabel)
      end
      if c.id.to_s.include? "class3"
        assert_equal "class3", c.prefLabel
      end
      if c.id.to_s.include? "class1"
        assert_equal "class 1 literal", c.prefLabel
      end
    end
  end

  def test_submission_root_classes
    return if ENV["SKIP_PARSING"]

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ], submissionId: 1)
            .include(LinkedData::Models::OntologySubmission.attributes).all
    assert(os.length == 1)
    os = os[0]

   roots = os.roots
    assert_instance_of(Array, roots)
    assert_equal(2, roots.length)
    root_ids = ["http://bioportal.bioontology.org/ontologies/msotes#class1",
      "http://bioportal.bioontology.org/ontologies/msotes#class6" ]
     # class 3 is now subClass of some anonymous thing.
     # "http://bioportal.bioontology.org/ontologies/msotes#class3"]
    roots.each do |r|
      assert(root_ids.include? r.id.to_s)
      root_ids.delete_at(root_ids.index(r.id.to_s))
    end
    #I have found them all
    assert(root_ids.length == 0)

    ontology = os.ontology
    os.delete
    ontology.delete
  end

  def test_submission_parse_emo
    return if ENV["SKIP_PARSING"]
    acronym = "EMO-TST"
    name = "EMO Bla"
    ontologyFile = "./test/data/ontology_files/emo_1.1.owl"
    id = 10

    emo = LinkedData::Models::Ontology.find(acronym)
    if not emo.nil?
      sub = emo.submissions || []
      sub.each do |s|
        s.delete
      end
    end

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, emo, user, status, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", "UPLOADED", name)
    ont_submision.contact = [contact]
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.ontology = emo
    ont_submision.submissionStatus = status
    assert (ont_submision.valid?)
    ont_submision.save

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]

    sub = LinkedData::Models::Ontology.find(acronym).first
    sub.bring(:submissions)
    if not sub.nil?
      sub = sub.submissions || []
      sub.each do |s|
        s.delete
      end
    end
  end

  #escaping sequences
  def test_submission_parse_sbo
    return if ENV["SKIP_PARSING"]
    acronym = "SBO-TST"
    name = "SBO Bla"
    ontologyFile = "./test/data/ontology_files/SBO.obo"
    id = 10

    sbo = LinkedData::Models::Ontology.find(acronym).first
    if not sbo.nil?
      sbo.bring(:submissions)
      sub = sbo.submissions || []
      sub.each do |s|
        s.delete
      end
    end

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, sbo, user, status, contact = submission_dependent_objects("OBO", acronym, "test_linked_models", "UPLOADED", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.contact = [contact]
    ont_submision.ontology = sbo
    ont_submision.submissionStatus = status
    assert (ont_submision.valid?)
    ont_submision.save
    assert_equal true, ont_submision.exist?(reload=true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]
    sub.process_submission(Logger.new(STDOUT),index_search=false,run_metrics=false)
    assert sub.submissionStatus.parsed?

    page_classes = LinkedData::Models::Class.in(sub)
                                             .page(1,1000)
                                             .include(:prefLabel, :synonym).all
    page_classes.each do |c|
      if c.id.to_s == "http://purl.obolibrary.org/obo/SBO_0000004"
        assert c.prefLabel == "modelling framework"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/SBO_0000011"
        assert c.prefLabel == "product"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/SBO_0000236"
        assert c.prefLabel == "physical entity representation"
        assert c.synonym[0] == "new synonym"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/SBO_0000306"
        assert c.prefLabel == "pK"
        assert c.synonym[0] == "dissociation potential"
      end
    end

    sbo.bring(:submissions)
    sub = sbo.submissions || []
    sub.each do |s|
        s.delete
    end
  end

  #ontology with import errors
  def test_submission_parse_cno
    return if ENV["SKIP_PARSING"]
    acronym = "CNO-TST"
    name = "CNO Bla"
    ontologyFile = "./test/data/ontology_files/CNO_05.owl"
    id = 10

    emo = LinkedData::Models::Ontology.find(acronym)
    if not emo.nil?
      sub = emo.submissions || []
      sub.each do |s|
        s.load
        s.delete
      end
    end

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, emo, user, status, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", "UPLOADED", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.ontology = emo
    ont_submision.contact = [contact]
    ont_submision.submissionStatus = status
    assert (ont_submision.valid?)
    ont_submision.save

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]
    sub.process_submission(Logger.new(STDOUT),index_search=false,run_metrics=false)
    assert sub.submissionStatus.parsed?

    assert sub.missingImports.length == 1
    assert sub.missingImports[0] == "http://purl.org/obo/owl/ro_bfo1-1_bridge"

    emo.bring(:submissions)
    sub = emo.submissions || []
    sub.each do |s|
      s.delete
    end
  end

  #multiple preflables
  def test_submission_parse_aero
    return if ENV["SKIP_PARSING"]
    acronym = "AERO-TST"
    name = "aero Bla"
    ontologyFile = "./test/data/ontology_files/aero.owl"
    id = 10

    aero = LinkedData::Models::Ontology.find(acronym).first
    if not aero.nil?
      sub = aero.submissions || []
      sub.each do |s|
        s.delete
      end
    end

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, aero, user, status, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", "UPLOADED", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.prefLabelProperty =  RDF::URI.new "http://www.w3.org/2000/01/rdf-schema#label"
    ont_submision.synonymProperty = RDF::URI.new "http://purl.obolibrary.org/obo/IAO_0000118"
    ont_submision.definitionProperty = RDF::URI.new "http://purl.obolibrary.org/obo/IAO_0000115"
    ont_submision.authorProperty = RDF::URI.new "http://purl.obolibrary.org/obo/IAO_0000117"
    ont_submision.hasOntologyLanguage = owl
    ont_submision.contact = [contact]
    ont_submision.ontology = aero
    ont_submision.submissionStatus = status
    assert (ont_submision.valid?)
    ont_submision.save
    assert_equal true, ont_submision.exist?(reload=true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]
    sub.process_submission(Logger.new(STDOUT),index_search=false,run_metrics=false)
    assert sub.submissionStatus.parsed?

    page_classes = LinkedData::Models::Class.in(sub)
                                             .page(1,1000)
                                             .read_only
                                             .include(:prefLabel, :synonym, :definition).all
    page_classes.each do |c|
      if c.id.to_s == "http://purl.obolibrary.org/obo/UBERON_0004535"
        assert c.prefLabel == "cardiovascular system"
        assert c.definition[0] == "Anatomical system that has as its parts the heart and blood vessels."
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/ogms/OMRE_0000105"
        assert c.prefLabel == "angioedema"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/ogms/OMRE_0000104"
        assert c.prefLabel == "generalized erythema"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/UBERON_0012125"
        assert c.prefLabel == "dermatological-mucosal system"
        assert c.definition == ["Anatomical system that consists of the integumental system plus all mucosae and submucosae."]
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/IAO_0000578"
        assert c.prefLabel == "CRID"
        assert c.synonym[0] == "Centrally Registered IDentifier"
      end
    end

    #for indexing in search
    paging = LinkedData::Models::Class.in(sub).page(1,100)
                                              .include(:unmapped)
    page = nil
    defs = 0
    syns = 0
    begin
      page = paging.all
      page.each do |c|
        LinkedData::Models::Class.map_attributes(c,paging.equivalent_predicates)
        assert_instance_of(String, c.prefLabel)
        defs += c.synonym.length
        syns += c.definition.length
      end
      paging.page(page.next_page) if page.next?
    end while(page.next?)
    assert defs == 26
    assert syns == 285
    aero = LinkedData::Models::Ontology.find(acronym).first
    aero.bring(:submissions)
    if not aero.nil?
      sub = aero.submissions || []
      sub.each do |s|
        s.delete
      end
    end
  end

  def test_submission_metrics
    submission_parse("CDAOTEST", "CDAOTEST testing metrics",
                     "./test/data/ontology_files/cdao_vunknown.owl", 22,
                    index_search=false,
                    run_metrics=true)

    sub = LinkedData::Models::Ontology.find("CDAOTEST").first.latest_submission
    sub.bring(:metrics)

    metrics = sub.metrics
    metrics.bring_remaining
    assert_instance_of LinkedData::Models::Metric, metrics

    assert metrics.classes == 143
    assert metrics.properties == 78
    assert metrics.individuals == 27
    assert metrics.classesWithOneChild == 10
    assert metrics.classesWithNoDefinition == 137
    assert metrics.classesWithMoreThan25Children == 0
    assert metrics.maxChildCount == 9
    assert metrics.averageChildCount == 2
    assert metrics.maxDepth == 5

    submission_parse("BROTEST-METRICS", "BRO testing metrics",
                     "./test/data/ontology_files/BRO_v3.2.owl", 33,
                    index_search=false,
                    run_metrics=true)

    sub = LinkedData::Models::Ontology.find("BROTEST-METRICS").first.latest_submission
    sub.bring(:metrics)

    metrics = sub.metrics
    metrics.bring_remaining
    assert_instance_of LinkedData::Models::Metric, metrics

    assert metrics.classes == 486
    assert metrics.properties == 63
    assert metrics.individuals == 80
    assert metrics.classesWithOneChild == 14
    #cause it has not the subproperty added
    assert metrics.classesWithNoDefinition == 478
    assert metrics.classesWithMoreThan25Children == 2
    assert metrics.maxChildCount == 65
    assert metrics.averageChildCount == 5
    assert metrics.maxDepth == 8

  end

end

