require_relative "./test_ontology_common"

class TestProvisionalClass < LinkedData::TestOntologyCommon

  def self.before_suite
    @@user = LinkedData::Models::User.new({username: "Test User", email: "tester@example.org", password: "password"})
    @@user.save

    ont_count, ont_names, ont_models = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 1,
                                                                                                          submission_count: 1)
    @@ontology = ont_models.first
    @@ontology.bring(:name)
    @@ontology.bring(:acronym)
    @@submission = @@ontology.bring(:submissions).submissions.first

    @@provisional_class = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Class", creator: @@user})
    @@provisional_class.save
  end

  def self.after_suite
    pc = LinkedData::Models::ProvisionalClass.find(@@provisional_class.id).first
    pc.delete unless pc.nil?

    LinkedData::Models::ProvisionalClass.indexClear
    LinkedData::Models::ProvisionalClass.indexCommit
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    user = LinkedData::Models::User.find("Test User").first
    user.delete unless user.nil?

  end


  def test_provisional_class_lifecycle
    label = "Test Provisional Class Lifecycle"
    pc = LinkedData::Models::ProvisionalClass.new({label: label, :creator => @@user})

    # Before save
    assert_equal LinkedData::Models::ProvisionalClass.where(label: label).all.count, 0
    assert_equal false, pc.exist?

    pc.save

    # After save
    assert_equal LinkedData::Models::ProvisionalClass.where(label: label).all.count, 1
    assert_equal true, pc.exist?

    pc.delete

    # After delete
    assert_equal LinkedData::Models::ProvisionalClass.where(label: label).all.count, 0
    assert_equal false, pc.exist?
  end

  def test_provisional_class_valid
    pc = LinkedData::Models::ProvisionalClass.new
    assert (not pc.valid?)

    # Not valid (missing required attributes).
    pc.definition = ["Definition 1", "Definition 2"]
    assert (not pc.valid?), "#{pc.errors}"

    # Valid (required attributes initialized).
    pc.label = "Test Provisional Class"
    pc.creator = @@user
    assert pc.valid?, "#{pc.errors}"
  end

  def test_provisional_class_retrieval
    creators = ["Test User 0", "Test User 1", "Test User 2"]
    pc_array = Array.new(3) { LinkedData::Models::ProvisionalClass.new }
    pc_array.each_with_index do |pc, i|
      pc.label = "Test PC #{i}"
      pc.creator = LinkedData::Models::User.new({username: creators[i], email: "tester#{i}@example.org", password: "password"}).save
      pc.save
      assert pc.valid?, "#{pc.errors}"
    end

    # Retrieve a particular ProvisionalClass
    pc1 = LinkedData::Models::ProvisionalClass.where(label: "Test PC 2").all
    assert_equal pc1.length, 1

    # Retrieve the same ProvisionalClass another way
    pc2 = LinkedData::Models::ProvisionalClass.where(creator: [username: "Test User 2"]).all
    assert_equal pc1.first.id.to_s, pc2.first.id.to_s

    pc_array.each do |pc|
      pc.delete
    end
  end

  def test_provisional_class_filter_by_creator
    username = "User Testing Filtering"
    user = LinkedData::Models::User.new({username: username, email: "tester#{rand}@example.org", password: "password"})
    user.save
    assert user.valid?, "#{user.errors}"

    pc_array = Array.new(3) { LinkedData::Models::ProvisionalClass.new }
    pc_array.each_with_index do |pc, i|
      pc.label = "PC Testing Filtering #{i}"
      pc.creator = user
      pc.save
      assert pc.valid?, "#{pc.errors}"
    end

    user = LinkedData::Models::User.find(username).include(:provisionalClasses).first
    assert_equal user.provisionalClasses.count, 3

    pcs = LinkedData::Models::ProvisionalClass.where(creator: [username: username]).all
    assert_equal pcs.count, 3

    pc_array.each do |pc|
      pc.delete
    end
    user.delete
  end

  def test_provisional_class_synonym
    syns = ["Test Synonym 1", "Test Synonym 2", "Test Synonym 3"]
    pc = @@provisional_class
    pc.synonym = syns
    assert pc.valid?, "#{pc.errors}"
    pc.save
    assert pc.synonym.length == 3
    assert_equal(pc.synonym.first, syns.first)
  end

  def test_provisional_class_description
    defs = ["Some definition", "Some other definition"]
    pc = @@provisional_class
    pc.definition = defs
    assert pc.valid?, "#{pc.errors}"
    pc.save
    assert pc.definition.length == 2
    assert_equal(pc.definition.first, defs.first)
  end

  def test_provisional_class_subclass_of
    pc = @@provisional_class

    # Invalid URI
    pc.subclassOf = "Invalid subclassOf URI"
    assert (not pc.valid?)
    assert_equal(false, pc.errors[:subclassOf].nil?)

    # Valid URI
    pc.subclassOf = RDF::IRI.new("http://valid.uri.com")
    assert pc.valid?
    assert_equal(true, pc.errors[:subclassOf].nil?)
  end

  def test_provisional_class_hierarchy
    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    o = LinkedData::Models::Ontology.find(acr).first
    os = LinkedData::Models::OntologySubmission.where(ontology: o, submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id1 = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class1"
    class_id2 = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class2"
    class_id3 = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class3"
    class_id4 = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class4"
    class_id5 = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_5"

    pc1 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Root", creator: @@user})
    pc1.save
    pc1 = LinkedData::Models::ProvisionalClass.find(pc1.id).include(:label).first

    pc2 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Leaf Parent", subclassOf: pc1.id, creator: @@user})
    pc2.save
    pc2 = LinkedData::Models::ProvisionalClass.find(pc2.id).include(:label).first

    pc3 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Leaf", subclassOf: pc2.id, creator: @@user})
    pc3.save
    pc3 = LinkedData::Models::ProvisionalClass.find(pc3.id).include(:label).first
    path = pc3.paths_to_root
    assert_equal 1, path.length
    assert_equal 3, path[0].length

    # test for a regular class as a parent
    pc1.bring_remaining
    pc1.ontology = o
    pc1.subclassOf = class_id5
    pc1.save
    path = pc3.paths_to_root

    ctr_class1 = 0
    ctr_class2 = 0
    ctr_class3 = 0
    ctr_class4 = 0
    ctr_class5 = 0
    ctr_pc1 = 0

    path.each do |p|
      ids = p.map { |one| one.id}
      ctr_class1 += 1 if ids.include?(class_id1)
      ctr_class2 += 1 if ids.include?(class_id2)
      ctr_class3 += 1 if ids.include?(class_id3)
      ctr_class4 += 1 if ids.include?(class_id4)
      ctr_class5 += 1 if ids.include?(class_id5)
      ctr_pc1 += 1 if ids.include?(pc1.id)
    end

    assert_equal 1, ctr_class1
    assert_equal 1, ctr_class2
    assert_equal 5, ctr_class3
    assert_equal 5, ctr_class4
    assert_equal 7, ctr_class5
    assert_equal 8, ctr_pc1

    # test for non-existent class
    pc1.subclassOf = RDF::IRI.new("http://www.yahoo.com")
    pc1.save
    path = pc3.paths_to_root
    assert_equal 1, path.length
    assert_equal 3, path[0].length

    # test for circular recursion
    pc1.subclassOf = pc3.id
    pc1.save
    path = pc3.paths_to_root
    assert_equal 1, path.length
    assert_equal 3, path[0].length

    # cleanup
    pc3.delete
    pc3 = LinkedData::Models::ProvisionalClass.find(pc3.id).first
    assert_nil pc3
    pc2.delete
    pc2 = LinkedData::Models::ProvisionalClass.find(pc2.id).first
    assert_nil pc2
    pc1.delete
    pc1 = LinkedData::Models::ProvisionalClass.find(pc1.id).first
    assert_nil pc1
  end

  def test_provisional_class_created
    pc = @@provisional_class

    # created should have a default value.
    assert (not pc.created.nil?)
    assert pc.valid?, "#{pc.errors}"
    pc.save
    assert pc.created.instance_of?(DateTime)
  end

  def test_provisional_class_permanent_id
    pc = @@provisional_class

    # Invalid URI
    pc.permanentId = "Invalid permanentId URI"
    assert (not pc.valid?)
    assert_equal(false, pc.errors[:permanentId].nil?)

    # Valid URI
    pc.permanentId = RDF::IRI.new("http://valid.uri.com")
    assert pc.valid?
    assert_equal(true, pc.errors[:permanentId].nil?)
  end

  def test_provisional_class_note_id
    pc = @@provisional_class

    # Invalid URI
    pc.noteId = "Invalid noteId URI"
    assert (not pc.valid?)
    assert_equal(false, pc.errors[:noteId].nil?)

    # Valid URI
    pc.noteId = RDF::IRI.new("http://valid.uri.com")
    assert pc.valid?
    assert_equal(true, pc.errors[:noteId].nil?)
  end

  def test_provisional_class_ontology
    pc = @@provisional_class
    pc.ontology = @@ontology
    assert pc.valid?, "#{pc.errors}"
    assert_equal(true, pc.ontology.acronym == "TEST-ONT-0")
    assert_equal(true, pc.ontology.name == "TEST-ONT-0 Ontology")
  end

  def test_provisional_class_search_indexing
    params = {"fq" => "provisional:true"}
    pc = @@provisional_class
    pc.ontology = @@ontology
    pc.unindex
    resp = LinkedData::Models::Ontology.search("\"#{pc.label}\"", params)
    assert_equal 0, resp["response"]["numFound"]

    pc.index
    resp = LinkedData::Models::Ontology.search("\"#{pc.label}\"", params)
    assert_equal 1, resp["response"]["numFound"]
    assert_equal pc.label, resp["response"]["docs"][0]["prefLabel"].first
    pc.unindex

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    o = LinkedData::Models::Ontology.find(acr).first
    os = LinkedData::Models::OntologySubmission.where(ontology: o, submissionId: 1).all
    assert(os.length == 1)
    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    pc1 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Subclass of Real Class", creator: @@user, ontology: o, subclassOf: class_id})
    pc1.save
    pc1 = LinkedData::Models::ProvisionalClass.find(pc1.id).include(:label).first

    pc2 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Parent of Leaf", subclassOf: pc1.id, creator: @@user, ontology: o})
    pc2.save
    pc2 = LinkedData::Models::ProvisionalClass.find(pc2.id).include(:label).first

    pc3 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Leaf", subclassOf: pc2.id, creator: @@user, ontology: o})
    pc3.save
    pc3 = LinkedData::Models::ProvisionalClass.find(pc3.id).include(:label).first

    resp = LinkedData::Models::Ontology.search("\"#{pc1.label}\"", params)
    assert_equal 1, resp["response"]["numFound"]
    assert_equal pc1.label, resp["response"]["docs"][0]["prefLabel"].first
    par_len = resp["response"]["docs"][0]["parents"].length
    assert_equal 5, par_len
    assert_equal 1, (resp["response"]["docs"][0]["parents"].select { |x| x == class_id.to_s }).length

    resp = LinkedData::Models::Ontology.search("\"#{pc2.label}\"", params)
    assert_equal par_len + 1, resp["response"]["docs"][0]["parents"].length
    assert_equal 1, (resp["response"]["docs"][0]["parents"].select { |x| x == pc1.id.to_s }).length

    resp = LinkedData::Models::Ontology.search("\"#{pc3.label}\"", params)
    assert_equal par_len + 2, resp["response"]["docs"][0]["parents"].length
    assert_equal 1, (resp["response"]["docs"][0]["parents"].select { |x| x == pc1.id.to_s }).length
    assert_equal 1, (resp["response"]["docs"][0]["parents"].select { |x| x == pc2.id.to_s }).length

    # cleanup
    pc3.delete
    pc3 = LinkedData::Models::ProvisionalClass.find(pc3.id).first
    assert_nil pc3
    pc2.delete
    pc2 = LinkedData::Models::ProvisionalClass.find(pc2.id).first
    assert_nil pc2
    pc1.delete
    pc1 = LinkedData::Models::ProvisionalClass.find(pc1.id).first
    assert_nil pc1
  end

end
