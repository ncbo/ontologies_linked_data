require_relative '../../../test/test_log_file.rb'

module LinkedData
  module SampleData
    class Ontology

      ##
      # Creates a set of Ontology and OntologySubmission objects and stores them in the triplestore
      # @param [Hash] options the options to create ontologies with
      # @option options [Fixnum] :ont_count Number of ontologies to create
      # @option options [Fixnum] :submission_count How many submissions each ontology should have (acts as max number when random submission count is used)
      # @option options [Fixnum] :submissions_to_process Which submission ids to parse
      # @option options [TrueClass, FalseClass] :random_submission_count Use a random number of submissions between 1 and :submission_count
      # @option options [TrueClass, FalseClass] :process_submission Parse the test ontology file
      def self.create_ontologies_and_submissions(options = {})
        # Default options
        ont_count = options[:ont_count] || 5
        submission_count = options[:submission_count] || 5
        random_submission_count = options[:random_submission_count] || false
        process_submission = options[:process_submission] || false
        process_options = options[:process_options] || { process_rdf: true, index_search: true, index_properties: true,
                                                         run_metrics: true, reasoning: true }

        submissions_to_process = options[:submissions_to_process]
        acronym = options[:acronym] || "TEST-ONT"
        pref_label_property = options[:pref_label_property] || false
        synonym_property = options[:synonym_property] || false
        definition_property = options[:synonym_property] || false
        name = options[:name]
        # set ontology type
        ontology_type = nil
        ontology_type_rec = nil
        ontology_type_rec = LinkedData::Models::OntologyType.find(options[:ontology_type]) if options[:ontology_type]
        ontology_type = ontology_type_rec.include(:code).first if ontology_type_rec
        file_path = options[:file_path]
        acr_suffix = options[:acronym_suffix]
        u, of, contact = ontology_objects()
        of = LinkedData::Models::OntologyFormat.find(options[:ontology_format]).include(:acronym).first if options[:ontology_format]
        contact.save if contact.modified?

        ont_acronyms = []
        ontologies = []
        ont_count.to_i.times do |count|
          acronym_suffix = acr_suffix || "-#{count}"
          acronym_count = "#{acronym}#{acronym_suffix}"
          ont_acronyms << acronym_count

          o = LinkedData::Models::Ontology.new({
                                                 acronym: acronym_count,
                                                 name: name ? "#{name}#{count > 0 ? count : ''}" : "#{acronym_count} Ontology",
                                                 administeredBy: [u],
                                                 summaryOnly: false,
                                                 ontologyType: ontology_type
                                               })

          if o.exist?
            o = LinkedData::Models::Ontology.find(acronym_count).include(LinkedData::Models::Ontology.attributes(:all)).first
            o.bring(:submissions)
            o.submissions.each {|s| s.delete}
          else
            o.save
          end

          # Random submissions (between 1 and max)
          max = random_submission_count ? (1.submission_count.to_i).to_a.shuffle.first : submission_count
          max.times do
            #refresh submission to get new next submission ID after saving in a loop
            o.bring(:submissions)
            sub_options = {
              ontology: o,
              hasOntologyLanguage: of,
              submissionId: o.next_submission_id,
              definitionProperty: (RDF::IRI.new "http://bioontology.org/ontologies/biositemap.owl#definition"),
              contact: [contact],
              released: DateTime.now - 3
            }
            sub_options[:prefLabelProperty] = RDF::IRI.new(pref_label_property) if pref_label_property
            sub_options[:synonymProperty] = RDF::IRI.new(synonym_property) if synonym_property
            sub_options[:definitionProperty] = RDF::IRI.new(definition_property) if definition_property
            os = LinkedData::Models::OntologySubmission.new(sub_options)

            if (submissions_to_process.nil? || submissions_to_process.include?(os.submissionId))
              file_path = options[:file_path]
              file_path = "../../../../test/data/ontology_files/BRO_v3.#{os.submissionId}.owl" if file_path.nil?
              if File.exist?(file_path)
                file_path = File.expand_path(file_path)
              else
                file_path = File.expand_path(file_path, __FILE__)
              end
              raise ArgumentError, "File located at #{file_path} does not exist" unless File.exist?(file_path)
              if os.submissionId > 5
                raise ArgumentError, "create_ontologies_and_submissions does not support process submission with more than 5 versions"
              end
              o.bring(:acronym) if o.bring?(:acronym)
              uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(o.acronym, os.submissionId, file_path)
              os.uploadFilePath = uploadFilePath
            else
              o.summaryOnly = true
              o.save
            end
            os.save unless os.exist?
          end
        end

        # Get ontology objects if empty
        ont_acronyms.each do |ont_id|
          ontologies << LinkedData::Models::Ontology.find(ont_id).first
        end

        if process_submission
          ontologies.each do |o|
            o.bring(:submissions)
            o.submissions.each do |ss|
              ss.bring(:submissionId) if ss.bring?(:submissionId)
              next if (!submissions_to_process.nil? && !submissions_to_process.include?(ss.submissionId))

              test_log_file = TestLogFile.new
              tmp_log = Logger.new(test_log_file)

              begin
                ss.process_submission(tmp_log, process_options)
              rescue Exception => e
                puts "Error processing submission: #{ss.id.to_s}"
                puts "See test log for errors: #{test_log_file.path}"
                raise
              end
            end
          end
        end

        return ont_count, ont_acronyms, ontologies
      end

      def self.load_semantic_types_ontology(options = {})
        file_path = options[:file_path]
        file_path = "../../../../test/data/ontology_files/umls_semantictypes.ttl" if file_path.nil?

        count, acronyms, sty = create_ontologies_and_submissions({
                                                                   ont_count: 1,
                                                                   submission_count: 1,
                                                                   process_submission: true,
                                                                   acronym: "STY",
                                                                   ontology_format: "UMLS",
                                                                   name: "Semantic Types Ontology",
                                                                   acronym_suffix: "",
                                                                   file_path: file_path
                                                                 })
        sty
      end

      def self.ontology_objects
        u = LinkedData::Models::User.new(username: "tim", email: "tim@example.org", password: "password")
        if u.exist?
          u = LinkedData::Models::User.find("tim").first
        else
          u.save
        end

        of = LinkedData::Models::OntologyFormat.find("OWL").include(:acronym).first

        contact_name = "Sheila"
        contact_email = "sheila@example.org"
        contact = LinkedData::Models::Contact.where(name: contact_name, email: contact_email).to_a
        contact = contact.empty? ? LinkedData::Models::Contact.new(name: contact_name, email: contact_email).save : contact.first

        return u, of, contact
      end

      ##
      # Delete all ontologies and their submissions. This will look for all ontologies starting with TST-ONT- and ending in a Fixnum
      def self.delete_ontologies_and_submissions
        LinkedData::Models::Ontology.all.each do |ont|
          ont.delete
        end

        u = LinkedData::Models::User.find("tim").first
        u.delete unless u.nil?
      end

      def self.sample_owl_ontologies(process_submission: false, process_options: nil)
        process_options ||= {process_rdf: true, extract_metadata: false, index_search: false}
        count, acronyms, bro = create_ontologies_and_submissions({
                                                                   process_submission: process_submission,
                                                                   process_options: process_options,
                                                                   acronym: "BROTEST",
                                                                   name: "ontTEST Bla",
                                                                   file_path: "../../../../test/data/ontology_files/BRO_v3.2.owl",
                                                                   ont_count: 1,
                                                                   submission_count: 1
                                                                 })

        # This one has some nasty looking IRIS with slashes in the anchor
        count, acronyms, mccl = create_ontologies_and_submissions({
                                                                    process_submission: process_submission,
                                                                    process_options: process_options,
                                                                    acronym: "MCCLTEST",
                                                                    name: "MCCLS TEST",
                                                                    file_path: "../../../../test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl",
                                                                    ont_count: 1,
                                                                    submission_count: 1
                                                                  })

        # This one has resources wih accents.
        count, acronyms, onto_matest = create_ontologies_and_submissions({
                                                                           process_submission: process_submission,
                                                                           process_options: process_options,
                                                                           acronym: "ONTOMATEST",
                                                                           name: "OntoMA TEST",
                                                                           file_path: "../../../../test/data/ontology_files/OntoMA.1.1_vVersion_1.1_Date__11-2011.OWL",
                                                                           ont_count: 1,
                                                                           submission_count: 1
                                                                         })

        return bro.concat(mccl).concat(onto_matest)
      end

    end
  end
end
