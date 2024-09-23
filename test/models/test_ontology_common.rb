require_relative "../test_case"
require 'rack'

module LinkedData
  class TestOntologyCommon < LinkedData::TestCase
    def create_count_mapping
      count = LinkedData::Models::MappingCount.where.all.length
      unless count > 2
        LinkedData::Mappings.create_mapping_counts(Logger.new(TestLogFile.new))
        count = LinkedData::Models::MappingCount.where.all.length
      end
      count
    end
    def submission_dependent_objects(format, acronym, user_name, name_ont)
      #ontology format
      owl = LinkedData::Models::OntologyFormat.where(:acronym => format).first
      assert_instance_of LinkedData::Models::OntologyFormat, owl

      #user test_linked_models
      user = LinkedData::Models::User.where(:username => user_name).first
      if user.nil?
        user = LinkedData::Models::User.new(:username => user_name, :email => "some@email.org" )
        user.passwordHash = "some random pass hash"
        user.save
      end
      #
      #ontology
      ont = LinkedData::Models::Ontology.where(:acronym => acronym).first
      if ont.nil?

        ont = LinkedData::Models::Ontology.new(:acronym => acronym, :name => name_ont, administeredBy: [user])
        ont.flat = !acronym["ISFLAT"].nil?
        ont.save
      end

      # contact
      contact_name = "Peter"
      contact_email = "peter@example.org"
      contact = LinkedData::Models::Contact.where(name: contact_name, email: contact_email).first
      contact = LinkedData::Models::Contact.new(name: contact_name, email: contact_email).save if contact.nil?

      #Submission Status
      return owl, ont, user, contact
    end

    ##############################################
    # Possible parse_options with their defaults:
    #   index_search      = true
    #   run_metrics       = true
    #   reasoning         = true
    #   diff              = false
    #   delete            = true  # delete any existing submissions
    ##############################################
    def submission_parse(acronym, name, ontologyFile, id, parse_options={})
      return if ENV["SKIP_PARSING"]
      parse_options[:process_rdf].nil? && parse_options[:process_rdf] = true
      parse_options[:index_search].nil? && parse_options[:index_search] = false
      parse_options[:extract_metadata].nil? && parse_options[:extract_metadata] = false
      parse_options[:delete].nil? && parse_options[:delete] = true
      if parse_options[:delete]
        ont = LinkedData::Models::Ontology.find(acronym).first
        if not ont.nil?
          ont.bring(:submissions)
          sub = ont.submissions || []
          sub.each do |s|
            s.delete
          end
        end
      end
      ont_submission =  LinkedData::Models::OntologySubmission.new({ :submissionId => id})
      ont_submission.uri = RDF::URI.new('https://test.com')
      ont_submission.description = 'description example'
      ont_submission.status = 'beta'
      assert (not ont_submission.valid?)
      assert_equal 4, ont_submission.errors.length
      uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
      ont_submission.uploadFilePath = uploadFilePath
      ontology_type = "OWL"

      if ontologyFile && ontologyFile.end_with?("obo")
        ontology_type = "OBO"
      elsif ontologyFile && ontologyFile["skos"]
        ontology_type = "SKOS"
      elsif ontologyFile && ontologyFile["ttl"]
        ontology_type = "UMLS"
      end

      ont_format, ont, user, contact = submission_dependent_objects(ontology_type, acronym, "test_linked_models", name)
      ont_submission.contact = [contact]
      ont_submission.released = DateTime.now - 4
      ont_submission.hasOntologyLanguage = ont_format
      ont_submission.ontology = ont
      masterFileName = parse_options.delete :masterFileName

      if masterFileName
        ont_submission.masterFileName = masterFileName
      end

      if ont_submission.valid?
        assert true
      else
        puts ont_submission.errors
        assert false
      end

      ont_submission.save

      assert_equal true, ont_submission.exist?
      begin
        tmp_log = Logger.new(TestLogFile.new)
        ont_submission.process_submission(tmp_log, parse_options)
      rescue Exception => e
        puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
        raise e
      end
    end

    def init_test_ontology_msotest(acr)
      ont = LinkedData::Models::Ontology.find(acr)
                .include(submissions: [:submissionStatus]).first
      if not ont.nil?
        return
        LinkedData::TestCase.backend_4s_delete
      end
      ont_submission =  LinkedData::Models::OntologySubmission.new({ :submissionId => 1 })
      ont_submission.uri = RDF::URI.new('https://test.com')
      ont_submission.description = 'description example'
      ont_submission.status = 'beta'

      assert (not ont_submission.valid?)
      assert_equal 4, ont_submission.errors.length
      if acr["OBS"]
        file_path = "./test/data/ontology_files/custom_obsolete.owl"
      else
        file_path = "./test/data/ontology_files/custom_properties.owl"
      end

      uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acr, 1, file_path)
      ont_submission.uploadFilePath = uploadFilePath
      owl, ont, user, contact = submission_dependent_objects("OWL", acr, "test_linked_models",
                                                             "%s ont created by mso for testing"%acr)
      ont.administeredBy = [user]
      ont_submission.contact = [contact]
      ont_submission.released = DateTime.now - 4
      ont_submission.hasOntologyLanguage = owl
      ont_submission.ontology = ont
      if acr["OBS"] && !acr["DISCOVER"]
        if acr["BRANCH"]
          ont_submission.obsoleteParent =
            RDF::URI.new("http://bioportal.bioontology.org/ontologies/msotes#class1")
        else
          ont_submission.obsoleteProperty =
            RDF::URI.new("http://bioportal.bioontology.org/ontologies/msotes#mydeprecated")
        end
      end
      ont_submission.prefLabelProperty = RDF::URI.new("http://bioportal.bioontology.org/ontologies/msotes#myPrefLabel")
      ont_submission.synonymProperty = RDF::URI.new("http://bioportal.bioontology.org/ontologies/msotes#mySynonymLabel")
      ont_submission.definitionProperty = RDF::URI.new("http://bioportal.bioontology.org/ontologies/msotes#myDefinition")
      ont_submission.authorProperty = RDF::URI.new("http://bioportal.bioontology.org/ontologies/msotes#myAuthor")
      assert (ont_submission.valid?)
      ont_submission.save
      assert_equal true, ont_submission.exist?
      parse_options = {process_rdf: true, extract_metadata: false}
      begin
        tmp_log = Logger.new(TestLogFile.new)
        ont_submission.process_submission(tmp_log, parse_options)
      rescue Exception => e
        puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
        raise e
      end

      roots = ont_submission.roots
      #class99 is equivalent to intersection of ...
      #it shouldnt be at the root
      if acr["OBSPROPSDISC"]
        assert roots.length == 5
      elsif acr["OBSPROPS"]
        assert roots.length == 4
      elsif acr["OBSBRANCH"]
        assert roots.length == 5
      else
        assert roots.length == 6
      end
      assert !roots.map { |x| x.id.to_s }
              .include?("http://bioportal.bioontology.org/ontologies/msotes#class99")

      #test to see if custom properties were saved in the graph
      custom_props = [ "http://bioportal.bioontology.org/ontologies/msotes#myPrefLabel",
        "http://bioportal.bioontology.org/ontologies/msotes#myDefinition",
        "http://bioportal.bioontology.org/ontologies/msotes#mySynonymLabel",
        "http://bioportal.bioontology.org/ontologies/msotes#myAuthor"]
      custom_props.each do |p|
        query = <<eos
SELECT * WHERE {
    GRAPH #{ont_submission.id.to_ntriples} {
        <#{p}> <http://www.w3.org/2000/01/rdf-schema#subPropertyOf> ?super .
    } }
eos
        count = 0
        Goo.sparql_query_client.query(query).each_solution do |sol|
          if (sol[:super].to_s.include? "skos") || (sol[:super].to_s.include? "elements") ||  (sol[:super].to_s.include? "metadata")
            count += 1
          end
        end
        assert (count > 0)
      end
    end

    def start_server
      max_retries = 5
      retries = 0
      server_port = Random.rand(55000..65535)

      while port_in_use?(server_port)
        retries += 1
        break if retries >= max_retries
        server_port = Random.rand(55000..65535)
      end

      raise "Could not find an available port after #{max_retries} retries" if retries >= max_retries

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

      [server_url, server_thread, server_port]
    end

    private
    def port_in_use?(port)
      begin
        server = TCPServer.new(port)
        server.close
        false
      rescue Errno::EADDRINUSE
        true
      end
    end
  end
end

