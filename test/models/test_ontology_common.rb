require_relative "../test_case"

module LinkedData
  class TestOntologyCommon < LinkedData::TestCase
    def submission_dependent_objects(format,acronym,user_name,status_code, name_ont)
      #ontology format
      LinkedData::Models::OntologyFormat.init
      owl = LinkedData::Models::OntologyFormat.where(:acronym => format)[0]
      assert_instance_of LinkedData::Models::OntologyFormat, owl

      #ontology
      LinkedData::Models::OntologyFormat.init
      ont = LinkedData::Models::OntologyContainer.where(:acronym => acronym)
      LinkedData::Models::OntologyFormat.init
      assert(ont.length < 2)
      if ont.length == 0
        ont = LinkedData::Models::OntologyContainer.new({:acronym => acronym, :name => name_ont})
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
      LinkedData::Models::SubmissionStatus.init
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



    def init_test_ontology_msotest(acr)
      ont = LinkedData::Models::OntologyContainer.find(acr)
      if not ont.nil?
        sub = ont.submissions || []
        sub.each do |s|
          s.load
          s.delete
        end
        ont.delete
      end
      ont_submision =  LinkedData::Models::OntologySubmission.new({ :acronym => acr, :submissionId => 1 })
      assert (not ont_submision.valid?)
      assert_equal 5, ont_submision.errors.length
      file_path = "./test/data/ontology_files/custom_properties.owl"
      uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acr, 1, file_path)
      ont_submision.uploadFilePath = uploadFilePath
      owl, ont, user, status =  submission_dependent_objects("OWL", acr, "test_linked_models", "UPLOADED", "some ont created by mso for testing")
      ont_submision.ontologyFormat = owl
      ont_submision.administeredBy = user
      ont_submision.ontology = ont
      ont_submision.status = status
      ont_submision.prefLabelProperty = RDF::IRI.new("http://bioportal.bioontology.org/ontologies/msotes#myPrefLabel")
      ont_submision.synonymProperty = RDF::IRI.new("http://bioportal.bioontology.org/ontologies/msotes#mySynonymLabel")
      ont_submision.definitionProperty = RDF::IRI.new("http://bioportal.bioontology.org/ontologies/msotes#myDefinition")
      ont_submision.authorProperty = RDF::IRI.new("http://bioportal.bioontology.org/ontologies/msotes#myAuthor")
      assert (ont_submision.valid?)
      ont_submision.save
      assert_equal true, ont_submision.exist?(reload=true)
      uploaded = LinkedData::Models::SubmissionStatus.find("UPLOADED")
      uploded_ontologies = uploaded.submissions
      uploaded_ont = nil
      uploded_ontologies.each do |ont|
        ont.load
        if ont.acronym == acr
          uploaded_ont = ont
        end
      end
      assert (not uploaded_ont.nil?)
      if not uploaded_ont.ontology.loaded?
        uploaded_ont.ontology.load
      end
      uploaded_ont.process_submission Logger.new(STDOUT)

      #test to see if custom properties were saved in the graph
      custom_props = [ "http://bioportal.bioontology.org/ontologies/msotes#myPrefLabel",
        "http://bioportal.bioontology.org/ontologies/msotes#myDefinition",
        "http://bioportal.bioontology.org/ontologies/msotes#mySynonymLabel",
        "http://bioportal.bioontology.org/ontologies/msotes#myAuthor"]
      custom_props.each do |p|
        query = <<eos
SELECT * WHERE {
    GRAPH <#{uploaded_ont.resource_id.value}> {
        <#{p}> <http://www.w3.org/2000/01/rdf-schema#subPropertyOf> ?super .
    } }
eos
        count = 0
        Goo.store.query(query).each_solution do |sol|
          if (sol.get(:super).value.include? "skos") || (sol.get(:super).value.include? "elements") ||  (sol.get(:super).value.include? "metadata")
            count += 1
          end
        end
        assert (count > 0)
      end
    end
  end
end

