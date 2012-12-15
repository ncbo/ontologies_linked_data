require_relative "../test_case"
require "logger"

class TestOntologySubmission < LinkedData::TestCase
  def setup
    @acronym = "SNOMED-TST"
    @name = "SNOMED-CT TEST"
    @ontologyFile = "./test/data/ontology_files/BRO_v3.2.owl"
    @id = 10
  end

  def teardown
    l = LinkedData::Models::OntologySubmission.where(:acronym => @acronym, :submissionId => @id)
    l.each do |o|
      os.delete
      o = os.ontology
      o.load
      o.delete
    end
  end
  
  def submission_dependent_objects(format,acronym,user_name,status_code)
    #ontology format
    LinkedData::Models::OntologyFormat.init
    owl = LinkedData::Models::OntologyFormat.where(:acronym => format)[0]
    assert_instance_of LinkedData::Models::OntologyFormat, owl

    #ontology
    LinkedData::Models::OntologyFormat.init
    ont = LinkedData::Models::Ontology.where(:acronym => acronym)
    LinkedData::Models::OntologyFormat.init
    assert(ont.length < 2)
    if ont.length == 0
      ont = LinkedData::Models::Ontology.new({:acronym => acronym})
    else
      ont = ont[0]
    end
    
    #user test_linked_models
    users = LinkedData::Models::User.where(:username => user_name)
    assert(users.length < 2)
    if users.length == 0
      user = LinkedData::Models::User.new({:username => user_name})
    else
      user = users[0]
    end

        #user test_linked_models
    status = LinkedData::Models::SubmissionStatus.where(:code => status_code)
    assert(status.length < 2)
    if status.length == 0
      status = LinkedData::Models::SubmissionStatus.new({:code => status_code})
    else
      status = status[0]
    end

    #Submission Status
    return owl, ont, user, status 
  end

  def test_valid_ontology

    owl, bogus, user, status =  submission_dependent_objects("OWL", "bogus", "test_linked_models", "UPLOADED")

    os = LinkedData::Models::OntologySubmission.new
    assert (not os.valid?)

    os.acronym = @acronym
    os.submissionId = @id
    os.name = @name
    o = LinkedData::Models::Ontology.find(@acronym)
    if o.nil?
      os.ontology = LinkedData::Models::Ontology.new(:acronym => @acronym)
    else
      os.ontology = o 
    end
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(@acronym, @id, @ontologyFile) 
    os.uploadFilePath = uploadFilePath
    os.ontologyFormat = owl
    os.administeredBy = user
    os.ontology = bogus
    os.status = status
    assert os.valid?
  end
  
  def test_sanity_check_single_file_submission
    owl, bro, user, status =  submission_dependent_objects("OWL", "BRO", "test_linked_models", "UPLOADED")

    ont_submision =  LinkedData::Models::OntologySubmission.new({:acronym => "BRO", :submissionId => 1, :name => "Biomedical Resource Ontology"})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository("BRO", 1, @ontologyFile) 
    ont_submision.uploadFilePath = uploadFilePath
    ont_submision.status = status
    assert (not ont_submision.valid?)
    assert_equal 3, ont_submision.errors.length
    assert_instance_of Array, ont_submision.errors[:ontology]
    assert_instance_of Array, ont_submision.errors[:administeredBy]
    assert_instance_of Array, ont_submision.errors[:ontologyFormat]
    ont_submision.ontologyFormat = owl
    ont_submision.administeredBy = user
    ont_submision.ontology = bro
    assert ont_submision.valid?
    assert_equal 0, ont_submision.errors.length
  end


  def test_sanity_check_zip
    
    owl, fma, user, status =  submission_dependent_objects("OWL", "FMA", "test_linked_models", "UPLOADED")

    ont_submision =  LinkedData::Models::OntologySubmission.new({:acronym => "FMA", :submissionId => 1, :name => "FMA Bla"})
    ontologyFile = "./test/data/ontology_files/fma_3.1_owl_file_v3.1.zip"
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(@acronym, @id,ontologyFile) 
    ont_submision.uploadFilePath = uploadFilePath
    ont_submision.ontologyFormat = owl
    ont_submision.administeredBy = user
    ont_submision.ontology = fma
    ont_submision.status = status
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
    owl, dup, user, status =  submission_dependent_objects("OWL", "DUP", "test_linked_models", "UPLOADED")
    ont_submision =  LinkedData::Models::OntologySubmission.new({ :acronym => "Bogus", :submissionId => 1, :name => "Bogus bla blu" })
    ontologyFile = "./test/data/ontology_files/ont_dup_names.zip"
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository("Bogus", 1, ontologyFile) 
    ont_submision.ontologyFormat = owl
    ont_submision.administeredBy = user
    ont_submision.ontology = dup
    assert (!ont_submision.valid?)
    assert_equal 2, ont_submision.errors.length
    assert_instance_of String, ont_submision.errors[:uploadFilePath][0]
    assert_instance_of String, ont_submision.errors[:status][0]
  end

  def test_submission_parse
    bro = LinkedData::Models::Ontology.find("BRO")
    if not bro.nil?
      sub = bro.submissions || []
      sub.each do |s|
        s.load
        s.delete
      end
    end
    ont_submision =  LinkedData::Models::OntologySubmission.new({ :acronym => "BRO", :submissionId => 1, :name => "Some Name" })
    assert (not ont_submision.valid?)
    assert_equal 5, ont_submision.errors.length
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository("BRO", 1, @ontologyFile) 
    ont_submision.uploadFilePath = uploadFilePath
    owl, bro, user, status =  submission_dependent_objects("OWL", "BRO", "test_linked_models", "UPLOADED")
    ont_submision.ontologyFormat = owl
    ont_submision.administeredBy = user
    ont_submision.ontology = bro
    ont_submision.status = status
    assert (ont_submision.valid?)
    ont_submision.save
    assert_equal true, ont_submision.exist?(reload=true)
    assert_equal 1,  LinkedData::Models::OntologySubmission.all.length
    uploaded = LinkedData::Models::SubmissionStatus.find("UPLOADED")
    uploded_ontologies = uploaded.submissions
    assert_equal 1, uploded_ontologies.length
    uploaded_ont = uploded_ontologies[0]
    if uploaded_ont.loaded?
      uploaded_ont.load
    end
    uploaded_ont.process_submission Logger.new(STDOUT)
  end
end

