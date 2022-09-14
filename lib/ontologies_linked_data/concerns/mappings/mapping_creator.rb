module LinkedData
  module Concerns
    module Mappings
      module Creator

        def create_mapping(mapping_hash:, user_creator:, check_exist: false)
          object_class, object_submission,
            subject_class, subject_submission = get_mapping_classes(subject_id: mapping_hash[:subject_source_id],
                                                                    object_id: mapping_hash[:object_source_id],
                                                                    classes: mapping_hash[:classes])

          process = create_mapping_process(mapping_hash, subject_submission&.uri, object_submission&.uri, user_creator)
          classes = [subject_class, object_class]

          if check_exist && LinkedData::Mappings.check_mapping_exist(classes, process.relation)
            raise ArgumentError, 'Mapping already exists'
          end

          save_process(process)
          save_rest_mapping(classes, process)
        end

        def create_rest_mapping(classes, process)
          begin
            backup_mapping = LinkedData::Models::RestBackupMapping.new
            backup_mapping.uuid = UUID.new.generate
            backup_mapping.process = process
            class_urns = generate_class_urns(classes)
            backup_mapping.class_urns = class_urns
            # Insert backup into 4store

            raise StandardError, backup_mapping.errors unless backup_mapping.valid?

            backup_mapping.save

          rescue StandardError => e
            raise IOError, "Saving backup mapping has failed. Message: #{e.message.to_s}"
          end

          #second add the mapping id to current submission graphs
          rest_predicate = mapping_predicates()['REST'][0]
          begin
            classes.each do |c|
              sub = c.submission
              unless sub.id.to_s['latest'].nil?
                #the submission in the class might point to latest
                sub = LinkedData::Models::Ontology.find(c.submission.ontology.id).first.latest_submission
              end
              c_id = c.id
              graph_id = sub.id
              graph_insert = RDF::Graph.new
              graph_insert << [c_id, RDF::URI.new(rest_predicate), backup_mapping.id]
              Goo.sparql_update_client.insert_data(graph_insert, graph: graph_id)
            end
          rescue StandardError => e
            # Remove the created backup if the following steps of the mapping fail
            backup_mapping.delete
            raise StandardError, "Inserting the mapping ID in the submission graphs has failed. Message: #{e.message.to_s}"
          end

          LinkedData::Models::Mapping.new(classes, 'REST', process, backup_mapping.id)
        end

        def create_mapping_process(mapping_process_hash, source_uri, object_uri, user)
          process = LinkedData::Models::MappingProcess.new
          relations_array = Array(mapping_process_hash[:relation]).map { |r| RDF::URI.new(r) }
          process.relation = relations_array.first
          process.creator = user
          process.subject_source_id = RDF::URI.new(source_uri || mapping_process_hash[:subject_source_id])
          process.object_source_id = RDF::URI.new(object_uri || mapping_process_hash[:object_source_id])
          process.date = mapping_process_hash[:date] ? DateTime.parse(mapping_process_hash[:date]) : DateTime.now
          process_fields = %i[source source_name comment name source_contact_info]
          process_fields.each do |att|
            process.send("#{att}=", mapping_process_hash[att]) if mapping_process_hash[att]
          end
          process
        end

        private

        def save_rest_mapping(classes, process)
          LinkedData::Mappings.create_rest_mapping(classes, process)
        rescue StandardError => e
          # Remove the created process if the following steps of the mapping fail
          process.delete
          raise ArgumentError, "Loading mapping has failed. Message: #{e.message.to_s}"
        end

        def save_process(process)
          process.save
        rescue StandardError => e
          raise ArgumentError, "Loading mapping has failed. Message: #{e.message.to_s} : #{process.errors}"
        end

        def get_mapping_classes(classes:, subject_id:, object_id:)
          subject_submission = find_submission_by_ontology_id(subject_id)
          subject_class, subject_submission = find_class(classes.first, subject_submission)

          object_submission = find_submission_by_ontology_id(object_id)
          object_class, object_submission = find_class(classes.last, object_submission)

          [object_class, object_submission, subject_class, subject_submission]
        end

        # Generate URNs for class mapping (urn:ONT_ACRO:CLASS_URI)
        def generate_class_urns(classes)
          class_urns = []
          classes.each do |c|
            next if c.nil?

            if c.instance_of? LinkedData::Models::Class
              acronym = c.submission.id.to_s.split('/')[-3]
              class_urns << RDF::URI.new(LinkedData::Models::Class.urn_id(acronym, c.id.to_s))
            else
              class_urns << RDF::URI.new(c.urn_id())
            end
          end
          class_urns
        end

        def find_submission_by_ontology_id(ontology_id)
          return nil if ontology_id.nil?

          o = LinkedData::Models::Ontology.where(submissions: { uri: ontology_id })
                                          .include(submissions: %i[submissionId submissionStatus uri])
                                          .first
          o.nil? ? nil : o.latest_submission
        end

        def find_ontology_by_class(class_instance)
          class_instance.submission.bring :ontology
          class_instance.submission.ontology
        end

        def find_submission_by_class_id(class_id)
          params = {
            require_exact_match: true,
            defType: 'edismax',
            qf: 'resource_id'
          }
          query = class_id
          search_response = LinkedData::Models::Class.search(query, params)
          search_response = search_response['response']['docs']
          search_response.each do |resp|
            submission_id = resp['ontologyId']
            class_instance = LinkedData::Models::OntologySubmission.find(RDF::URI.new(submission_id)).include(:uri).first
            return class_instance unless class_instance.nil?
          end
          nil
        end

        def find_class(class_id, submission)
          submission = find_submission_by_class_id(class_id) if submission.nil?
          c = nil
          unless submission.nil?
            c = LinkedData::Models::Class.find(RDF::URI.new(class_id))
                                         .in(submission)
                                         .first
            if c
              c.submission.bring :ontology if c.submission.bring?(:ontology)
              c.submission.ontology.bring :acronym if c.submission.ontology.bring?(:acronym)
            end

          end
          [c, submission]
        end
      end
    end
  end
end

