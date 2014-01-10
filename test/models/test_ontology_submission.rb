require_relative "./test_ontology_common"
require "logger"
require "rack"

class TestOntologySubmission < LinkedData::TestOntologyCommon

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

    owl, bogus, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)

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
    assert os.valid?
  end

  def test_sanity_check_zip
    return if ENV["SKIP_PARSING"]

    acronym = "RADTEST"
    name = "RADTEST Bla"
    ontologyFile = "./test/data/ontology_files/SDO.zip"
    id = 10

    teardown

    owl, rad, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    ont_submision.contact = [contact]
    ont_submision.released = DateTime.now - 4
    ont_submision.uploadFilePath = uploadFilePath
    ont_submision.hasOntologyLanguage = owl
    ont_submision.ontology = rad
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

    owl, dup, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => 1,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    ont_submision.contact = [contact]
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.ontology = dup
    assert (!ont_submision.valid?)
    assert_equal 1, ont_submision.errors.length
    assert_instance_of String, ont_submision.errors[:uploadFilePath][0]
  end

  def test_obo_part_of
    submission_parse("TAO-TEST", "TAO TEST Bla", "./test/data/ontology_files/tao.obo", 55,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)

    #test for version info
    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "TAO-TEST"],
                                                       submissionId: 55)
                                                     .include(:version)
                                                     .first
    assert sub.version == "2012-08-10"

    qthing = <<-eos
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT DISTINCT * WHERE {
  <http://purl.obolibrary.org/obo/TAO_0001044> rdfs:subClassOf ?x . }
eos
    count = 0
    Goo.sparql_query_client.query(qthing).each_solution do |sol|
      assert sol[:x].to_s["TAO_0000732"]
      assert !sol[:x].to_s["Thing"]
      count += 1
    end
    assert count == 1

    qcount = <<-eos
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT DISTINCT * WHERE {
<http://purl.obolibrary.org/obo/TAO_0001044>
  <http://data.bioontology.org/metadata/obo/part_of> ?x . }
eos
    count = 0
    Goo.sparql_query_client.query(qcount).each_solution do |sol|
      count += 1
      assert sol[:x].to_s["TAO_0000732"]
    end
    assert count == 1

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "TAO-TEST"]).first
    n_roots = sub.roots.length
    assert n_roots == 3 #just 3 with latest modifications.
    #strict comparison to be sure the merge with the tree_view branch goes fine

    LinkedData::Models::Class.where.in(sub).include(:prefLabel, :notation).each do |cls|
      assert_instance_of String,cls.prefLabel
      if cls.id.to_s["TAO"]
        assert_instance_of String,cls.notation
        assert cls.notation[-6..-1] == cls.id.to_s[-6..-1]
      end
    end

  end

  def test_submission_parse_subfolders_zip
    submission_parse("CTXTEST", "CTX Bla",
                     "test/data/ontology_files/XCTontologyvtemp2_vvtemp2.zip",
                     34,
                     masterFileName: "XCTontologyvtemp2/XCTontologyvtemp2.owl",
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "CTXTEST"]).first

    #test roots to ack parsing went well
    n_roots = sub.roots.length
    assert n_roots == 15

  end

  def test_submission_parse
    #This one has some nasty looking IRIS with slashes in the anchor
    submission_parse("MCCLTEST", "MCCLS TEST",
                     "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl", 11,
                     process_rdf: true, index_search: true,
                     run_metrics: false, reasoning: true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "MCCLTEST"],
                                                       submissionId: 11)
                                                     .include(:version)
                                                     .first
    assert sub.version == "3.0"

    #This one has resources wih accents.
    submission_parse("ONTOMATEST",
                     "OntoMA TEST",
                     "./test/data/ontology_files/OntoMA.1.1_vVersion_1.1_Date__11-2011.OWL", 15,
                     process_rdf: true, index_search: true,
                     run_metrics: false, reasoning: true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "ONTOMATEST"],
                                                       submissionId: 15)
                                                     .include(:version)
                                                     .first
    assert sub.version["Version 1.1"]
    assert sub.version["Date: 11-2011"]
  end

  def test_process_submission_diff
    #submission_parse( acronym, name, ontologyFile, id, parse_options={})
    acronym = 'BRO'
    # Create a 1st version for BRO
    submission_parse(acronym, "BRO",
                     "./test/data/ontology_files/BRO_v3.4.owl", 1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: false,
                     diff: true, delete: false)
    # Create a later version for BRO
    submission_parse(acronym, "BRO",
                     "./test/data/ontology_files/BRO_v3.5.owl", 2,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: false,
                     diff: true, delete: false)
    onts = LinkedData::Models::Ontology.find(acronym)
    bro = onts.first
    bro.bring(:submissions)
    submissions = bro.submissions
    submissions.each {|s| s.bring(:submissionId, :diffFilePath)}
    # Sort submissions in descending order of submissionId, extract last two submissions
    recent_submissions = submissions.sort {|a,b| b.submissionId <=> a.submissionId}[0..1]
    sub1 = recent_submissions.last  # descending order, so last is older submission
    sub2 = recent_submissions.first # descending order, so first is latest submission
    assert(sub1.submissionId < sub2.submissionId, 'submissionId is in the wrong order')
    assert(sub1.diffFilePath == nil, 'Should not create diff for older submission.')
    assert(sub2.diffFilePath != nil, 'Failed to create diff for the latest submission.')
    # Cleanup
    bro.submissions.each {|s| s.delete}
  end

  def test_submission_diff_across_ontologies
    #submission_parse( acronym, name, ontologyFile, id, parse_options={})
    # Create a 1st version for BRO
    submission_parse("BRO34", "BRO3.4",
                     "./test/data/ontology_files/BRO_v3.4.owl", 1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: false)
    onts = LinkedData::Models::Ontology.find('BRO34')
    bro34 = onts.first
    bro34.bring(:submissions)
    sub34 = bro34.submissions.first
    # Create a later version for BRO
    submission_parse("BRO35", "BRO3.5",
                     "./test/data/ontology_files/BRO_v3.5.owl", 1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: false)
    onts = LinkedData::Models::Ontology.find('BRO35')
    bro35 = onts.first
    bro35.bring(:submissions)
    sub35 = bro35.submissions.first
    # Calculate the ontology diff: bro35 - bro34
    tmp_log = Logger.new(TestLogFile.new)
    sub35.diff(tmp_log, sub34)
    assert(sub35.diffFilePath != nil, 'Failed to create submission diff file.')
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
    assert_equal 4, ont_submision.errors.length
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, bro, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.prefLabelProperty = RDF::URI.new("http://bioontology.org/projects/ontologies/radlex/radlexOwl#Preferred_name")
    ont_submision.ontology = bro
    ont_submision.contact = [contact]
    assert (ont_submision.valid?)
    ont_submision.save
    parse_options = {process_rdf: true, index_search: false, run_metrics: false, reasoning: true}
    begin
      tmp_log = Logger.new(TestLogFile.new)
      ont_submision.process_submission(tmp_log, parse_options)
    rescue Exception => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end

    assert ont_submision.ready?({status: [:uploaded, :rdf, :rdf_labels]})

    LinkedData::Models::Class.in(ont_submision).include(:prefLabel).read_only.each do |cls|
      assert(cls.prefLabel != nil, "Class #{cls.id.to_ntriples} does not have a label")
      assert_instance_of String, cls.prefLabel
    end
  end

  def test_download_ontology_file
    begin
      server_port = Random.rand(55000..65535) # http://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers#Dynamic.2C_private_or_ephemeral_ports
      server_url = 'http://localhost:' + server_port.to_s
      server_thread = Thread.new do
        Rack::Server.start(
            app: lambda do |e|
              [200, {'Content-Type' => 'text/plain'}, ['test file']]
            end,
            Port: server_port
        )
      end
      Thread.pass
      sleep 3  # Allow the server to startup
      assert(server_thread.alive?, msg="Rack::Server thread should be alive, it's not!")
      ont_count, ont_names, ont_models = create_ontologies_and_submissions(ont_count: 1, submission_count: 1)
      ont = ont_models.first
      assert(ont.instance_of?(LinkedData::Models::Ontology), "ont is not an ontology: #{ont}")
      sub = ont.bring(:submissions).submissions.first
      assert(sub.instance_of?(LinkedData::Models::OntologySubmission), "sub is not an ontology submission: #{sub}")
      sub.pullLocation = RDF::IRI.new(server_url)
      file, filename = sub.download_ontology_file
      sleep 2
      assert filename.nil?, "Test filename is not nil: #{filename}"
      assert file.is_a?(Tempfile), "Test file is not a Tempfile"
      file.open
      assert file.read.eql?("test file"), "Test file content error: #{file.read}"
    ensure
      delete_ontologies_and_submissions
      Thread.kill(server_thread)  # this will shutdown Rack::Server also
      sleep 3
      assert_equal(server_thread.alive?, false, msg="Rack::Server thread should be dead, it's not!")
    end
  end

  def test_semantic_types
    acronym = 'STY-TST'
    submission_parse(acronym, "STY Bla", "./test/data/ontology_files/umls_semantictypes.ttl", 1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
    ont_sub = LinkedData::Models::Ontology.find(acronym).first.latest_submission(status: [:rdf])
    classes = LinkedData::Models::Class.in(ont_sub).include(:prefLabel).read_only.to_a
    assert_equal 133, classes.length
    classes.each do |cls|
      assert(cls.prefLabel != nil, "Class #{cls.id.to_ntriples} does not have a label")
      assert_instance_of String, cls.prefLabel
    end
  end

  def test_custom_obsolete_property
    return if ENV["SKIP_PARSING"]

    acr = "OBSPROPS"
    init_test_ontology_msotest acr

    o = LinkedData::Models::Ontology.find(acr).first
    o.bring_remaining
    o.bring(:submissions)
    oss = o.submissions
    assert_equal 1, oss.length
    ont_sub = oss[0]
    ont_sub.bring_remaining
    assert ont_sub.ready?
    LinkedData::Models::Class.in(ont_sub).include(:prefLabel,:synonymm, :obsolete).each do |c|
      assert (not c.prefLabel.nil?)
      if c.id.to_s["#class6"] || c.id.to_s["#class1"] || c.id.to_s["#class99"]
        assert c.obsolete
      else
        assert c.obsolete.nil?
      end
    end
  end

  def test_custom_obsolete_branch
    return if ENV["SKIP_PARSING"]

    acr = "OBSBRANCH"
    init_test_ontology_msotest acr

    o = LinkedData::Models::Ontology.find(acr).first
    o.bring_remaining
    o.bring(:submissions)
    oss = o.submissions
    assert_equal 1, oss.length
    ont_sub = oss[0]
    ont_sub.bring_remaining
    assert ont_sub.ready?
    LinkedData::Models::Class.in(ont_sub).include(:prefLabel,:synonymm, :obsolete).each do |c|
      assert (not c.prefLabel.nil?)
      if c.id.to_s["#class2"] || c.id.to_s["#class6"] ||
         c.id.to_s["#class_5"] || c.id.to_s["#class_7"]
        assert c.obsolete
      else
        assert c.obsolete.nil?
      end
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
    assert ont_sub.ready?
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
    assert_equal(6, roots.length)
    root_ids = ["http://bioportal.bioontology.org/ontologies/msotes#class1",
     "http://bioportal.bioontology.org/ontologies/msotes#class4",
     "http://bioportal.bioontology.org/ontologies/msotes#class3",
     "http://bioportal.bioontology.org/ontologies/msotes#class6",
     "http://bioportal.bioontology.org/ontologies/msotes#class98",
     "http://bioportal.bioontology.org/ontologies/msotes#class97"]
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
    owl, sbo,user , contact = submission_dependent_objects("OBO", acronym, "test_linked_models", name)
    assert user != nil
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.contact = [contact]
    ont_submision.ontology = sbo
    assert (ont_submision.valid?)
    ont_submision.save
    assert_equal true, ont_submision.exist?(true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]
    parse_options = {process_rdf: true, index_search: false, run_metrics: false, reasoning: true}
    begin
      tmp_log = Logger.new(TestLogFile.new)
      sub.process_submission(tmp_log, parse_options)
    rescue Exception => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end
    assert sub.ready?({status: [:uploaded, :rdf, :rdf_labels]})

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

    cno = LinkedData::Models::Ontology.find(acronym)
    if not cno.nil?
      sub = cno.submissions || []
      sub.each do |s|
        s.load
        s.delete
      end
    end

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, cno, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.ontology = cno
    ont_submision.contact = [contact]
    assert (ont_submision.valid?)
    ont_submision.save

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]
    parse_options = {process_rdf: true, index_search: false, run_metrics: false, reasoning: true}
    begin
      tmp_log = Logger.new(TestLogFile.new)
      sub.process_submission(tmp_log, parse_options)
    rescue Exception => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end
    assert sub.ready?({status: [:uploaded, :rdf, :rdf_labels]})
    assert sub.missingImports.length == 1
    assert sub.missingImports[0] == "http://purl.org/obo/owl/ro_bfo1-1_bridge"

    LinkedData::Models::Class.where.in(sub).include(:prefLabel, :notation, :prefixIRI).each do |cls|
      assert cls.prefixIRI.is_a?(String)
      assert cls.notation.nil?
      assert !cls.id.to_s.start_with?(":")
    end

    cno.bring(:submissions)
    sub = cno.submissions || []
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
    owl, aero, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.prefLabelProperty =  RDF::URI.new "http://www.w3.org/2000/01/rdf-schema#label"
    ont_submision.synonymProperty = RDF::URI.new "http://purl.obolibrary.org/obo/IAO_0000118"
    ont_submision.definitionProperty = RDF::URI.new "http://purl.obolibrary.org/obo/IAO_0000115"
    ont_submision.authorProperty = RDF::URI.new "http://purl.obolibrary.org/obo/IAO_0000117"
    ont_submision.hasOntologyLanguage = owl
    ont_submision.contact = [contact]
    ont_submision.ontology = aero
    assert (ont_submision.valid?)
    ont_submision.save
    assert_equal true, ont_submision.exist?(reload=true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]
    parse_options = {process_rdf: true, index_search: false, run_metrics: false, reasoning: true}
    begin
      tmp_log = Logger.new(TestLogFile.new)
      sub.process_submission(tmp_log, parse_options)
    rescue Exception => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end
    assert sub.ready?({status: [:uploaded, :rdf, :rdf_labels]})

    #test for ontology headers added to the graph
    sparql_query = <<eos
SELECT * WHERE {
GRAPH <http://data.bioontology.org/ontologies/AERO-TST/submissions/10>
{ <http://purl.obolibrary.org/obo/aero.owl> ?p ?o .}}
eos
    count_headers = 0
    Goo.sparql_query_client.query(sparql_query).each_solution do |sol|
      count_headers += 1
      assert sol[:p].to_s["contributor"] || sol[:p].to_s["comment"] || sol[:p].to_s["definition"]
    end
    assert count_headers == 4

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
        syns += c.synonym.length
        defs += c.definition.length
      end
      paging.page(page.next_page) if page.next?
    end while(page.next?)
    assert syns == 26
    assert defs == 285
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
                     process_rdf: true, index_search: false,
                     run_metrics: true, reasoning: true)
    sub = LinkedData::Models::Ontology.find("CDAOTEST").first.latest_submission(status: [:rdf, :metrics])
    sub.bring(:metrics)

    metrics = sub.metrics
    metrics.bring_remaining
    assert_instance_of LinkedData::Models::Metric, metrics

    assert metrics.classes == 143
    assert metrics.properties == 78
    assert metrics.individuals == 27
    assert metrics.classesWithOneChild == 11
    assert metrics.classesWithNoDefinition == 137
    assert metrics.classesWithMoreThan25Children == 0
    assert metrics.maxChildCount == 10
    assert metrics.averageChildCount == 2
    assert metrics.maxDepth == 5

    submission_parse("BROTEST-METRICS", "BRO testing metrics",
                     "./test/data/ontology_files/BRO_v3.2.owl", 33,
                     process_rdf: true, index_search: false,
                     run_metrics: true, reasoning: true)
    sub = LinkedData::Models::Ontology.find("BROTEST-METRICS").first.latest_submission(status: [:rdf, :metrics])
    sub.bring(:metrics)

    LinkedData::Models::Class.where.in(sub).include(:prefixIRI).each do |cls|
      assert !cls.prefixIRI.nil?
      assert cls.prefixIRI.is_a?(String)
      assert (!cls.prefixIRI.start_with?(":")) || (cls.prefixIRI[":"] != nil)
      cindex = (cls.prefixIRI.index ":") || 0
      assert cls.id.end_with?(cls.prefixIRI[cindex+1..-1])
    end

    metrics = sub.metrics
    metrics.bring_remaining
    assert_instance_of LinkedData::Models::Metric, metrics

    assert metrics.classes == 486
    assert metrics.properties == 63
    assert metrics.individuals == 82
    assert metrics.classesWithOneChild == 14
    #cause it has not the subproperty added
    assert metrics.classesWithNoDefinition == 474
    assert metrics.classesWithMoreThan25Children == 2
    assert metrics.maxChildCount == 65
    assert metrics.averageChildCount == 5
    assert metrics.maxDepth == 8
  end

end
