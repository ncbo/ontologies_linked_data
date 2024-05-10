module LinkedData
  module Services

    class MissingLabelsHandler < OntologySubmissionProcess

      def process(logger, options = {})
        handle_missing_labels(options[:file_path], logger)
      end

      private

      def handle_missing_labels(file_path, logger)
        callbacks = {
          missing_labels: {
            op_name: 'Missing Labels Generation',
            required: true,
            status: LinkedData::Models::SubmissionStatus.find('RDF_LABELS').first,
            artifacts: {
              file_path: file_path
            },
            caller_on_pre: :generate_missing_labels_pre,
            caller_on_pre_page: :generate_missing_labels_pre_page,
            caller_on_each: :generate_missing_labels_each,
            caller_on_post_page: :generate_missing_labels_post_page,
            caller_on_post: :generate_missing_labels_post
          }
        }

        raw_paging = LinkedData::Models::Class.in(@submission).include(:prefLabel, :synonym, :label)
        loop_classes(logger, raw_paging, @submission, callbacks)
      end

      def process_callbacks(logger, callbacks, action_name)
        callbacks.delete_if do |_, callback|
          begin
            if callback[action_name]
              callable = self.method(callback[action_name])
              yield(callable, callback)
            end
            false
          rescue Exception => e
            logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
            logger.flush

            if callback[:status]
              @submission.add_submission_status(callback[:status].get_error_status)
              @submission.save
            end

            # halt the entire processing if :required is set to true
            raise e if callback[:required]
            # continue processing of other callbacks, but not this one
            true
          end
        end
      end

      def loop_classes(logger, raw_paging, submission, callbacks)
        page = 1
        size = 2500
        count_classes = 0
        acr = submission.id.to_s.split("/")[-1]
        operations = callbacks.values.map { |v| v[:op_name] }.join(", ")

        time = Benchmark.realtime do
          paging = raw_paging.page(page, size)
          cls_count_set = false
          cls_count = submission.class_count(logger)

          if cls_count > -1
            # prevent a COUNT SPARQL query if possible
            paging.page_count_set(cls_count)
            cls_count_set = true
          else
            cls_count = 0
          end

          iterate_classes = false
          # 1. init artifacts hash if not explicitly passed in the callback
          # 2. determine if class-level iteration is required
          callbacks.each { |_, callback| callback[:artifacts] ||= {};
          if callback[:caller_on_each]
            iterate_classes = true
          end }

          process_callbacks(logger, callbacks, :caller_on_pre) {
            |callable, callback| callable.call(callback[:artifacts], logger, paging) }

          page_len = -1
          prev_page_len = -1

          begin
            t0 = Time.now
            page_classes = paging.page(page, size).all
            total_pages = page_classes.total_pages
            page_len = page_classes.length

            # nothing retrieved even though we're expecting more records
            if total_pages > 0 && page_classes.empty? && (prev_page_len == -1 || prev_page_len == size)
              j = 0
              num_calls = LinkedData.settings.num_retries_4store

              while page_classes.empty? && j < num_calls do
                j += 1
                logger.error("Empty page encountered. Retrying #{j} times...")
                sleep(2)
                page_classes = paging.page(page, size).all
                unless page_classes.empty?
                  logger.info("Success retrieving a page of #{page_classes.length} classes after retrying #{j} times...")
                end
              end

              if page_classes.empty?
                msg = "Empty page #{page} of #{total_pages} persisted after retrying #{j} times. #{operations} of #{acr} aborted..."
                logger.error(msg)
                raise msg
              end
            end

            if page_classes.empty?
              if total_pages > 0
                logger.info("The number of pages reported for #{acr} - #{total_pages} is higher than expected #{page - 1}. Completing #{operations}...")
              else
                logger.info("Ontology #{acr} contains #{total_pages} pages...")
              end
              break
            end

            prev_page_len = page_len
            logger.info("#{acr}: page #{page} of #{total_pages} - #{page_len} ontology terms retrieved in #{Time.now - t0} sec.")
            logger.flush
            count_classes += page_classes.length

            process_callbacks(logger, callbacks, :caller_on_pre_page) {
              |callable, callback| callable.call(callback[:artifacts], logger, paging, page_classes, page) }

            page_classes.each { |c|
              process_callbacks(logger, callbacks, :caller_on_each) {
                |callable, callback| callable.call(callback[:artifacts], logger, paging, page_classes, page, c) }
            } if iterate_classes

            process_callbacks(logger, callbacks, :caller_on_post_page) {
              |callable, callback| callable.call(callback[:artifacts], logger, paging, page_classes, page) }
            cls_count += page_classes.length unless cls_count_set

            page = page_classes.next? ? page + 1 : nil
          end while !page.nil?

          callbacks.each { |_, callback| callback[:artifacts][:count_classes] = cls_count }
          process_callbacks(logger, callbacks, :caller_on_post) {
            |callable, callback| callable.call(callback[:artifacts], logger, paging) }
        end

        logger.info("Completed #{operations}: #{acr} in #{time} sec. #{count_classes} classes.")
        logger.flush

        # set the status on actions that have completed successfully
        callbacks.each do |_, callback|
          if callback[:status]
            @submission.add_submission_status(callback[:status])
            @submission.save
          end
        end
      end

      def generate_missing_labels_pre(artifacts = {}, logger, paging)
        file_path = artifacts[:file_path]
        artifacts[:save_in_file] = File.join(File.dirname(file_path), "labels.ttl")
        artifacts[:save_in_file_mappings] = File.join(File.dirname(file_path), "mappings.ttl")
        property_triples = LinkedData::Utils::Triples.rdf_for_custom_properties(@submission)
        Goo.sparql_data_client.append_triples(@submission.id, property_triples, mime_type = "application/x-turtle")
        fsave = File.open(artifacts[:save_in_file], "w")
        fsave.write(property_triples)
        fsave_mappings = File.open(artifacts[:save_in_file_mappings], "w")
        artifacts[:fsave] = fsave
        artifacts[:fsave_mappings] = fsave_mappings
      end

      def generate_missing_labels_pre_page(artifacts = {}, logger, paging, page_classes, page)
        artifacts[:label_triples] = []
        artifacts[:mapping_triples] = []
      end

      def generate_missing_labels_each(artifacts = {}, logger, paging, page_classes, page, c)
        prefLabel = nil

        if c.prefLabel.nil?
          rdfs_labels = c.label

          if rdfs_labels && rdfs_labels.length > 1 && c.synonym.length > 0
            rdfs_labels = (Set.new(c.label) - Set.new(c.synonym)).to_a.first

            rdfs_labels = c.label if rdfs_labels.nil? || rdfs_labels.length == 0
          end

          rdfs_labels = [rdfs_labels] if rdfs_labels and not (rdfs_labels.instance_of? Array)
          label = nil

          if rdfs_labels && rdfs_labels.length > 0
            label = rdfs_labels[0]
          else
            label = LinkedData::Utils::Triples.last_iri_fragment c.id.to_s
          end
          artifacts[:label_triples] << LinkedData::Utils::Triples.label_for_class_triple(
            c.id, Goo.vocabulary(:metadata_def)[:prefLabel], label)
          prefLabel = label
        else
          prefLabel = c.prefLabel
        end

        if @submission.ontology.viewOf.nil?
          loomLabel = LinkedData::Models::OntologySubmission.loom_transform_literal(prefLabel.to_s)

          if loomLabel.length > 2
            artifacts[:mapping_triples] << LinkedData::Utils::Triples.loom_mapping_triple(
              c.id, Goo.vocabulary(:metadata_def)[:mappingLoom], loomLabel)
          end
          artifacts[:mapping_triples] << LinkedData::Utils::Triples.uri_mapping_triple(
            c.id, Goo.vocabulary(:metadata_def)[:mappingSameURI], c.id)
        end
      end

      def generate_missing_labels_post_page(artifacts = {}, logger, paging, page_classes, page)
        rest_mappings = LinkedData::Mappings.migrate_rest_mappings(@submission.ontology.acronym)
        artifacts[:mapping_triples].concat(rest_mappings)

        if artifacts[:label_triples].length > 0
          logger.info("Asserting #{artifacts[:label_triples].length} labels in " +
                        "#{@submission.id.to_ntriples}")
          logger.flush
          artifacts[:label_triples] = artifacts[:label_triples].join("\n")
          artifacts[:fsave].write(artifacts[:label_triples])
          t0 = Time.now
          Goo.sparql_data_client.append_triples(@submission.id, artifacts[:label_triples], mime_type = "application/x-turtle")
          t1 = Time.now
          logger.info("Labels asserted in #{t1 - t0} sec.")
          logger.flush
        else
          logger.info("No labels generated in page #{page}.")
          logger.flush
        end

        if artifacts[:mapping_triples].length > 0
          logger.info("Asserting #{artifacts[:mapping_triples].length} mappings in " +
                        "#{@submission.id.to_ntriples}")
          logger.flush
          artifacts[:mapping_triples] = artifacts[:mapping_triples].join("\n")
          artifacts[:fsave_mappings].write(artifacts[:mapping_triples])

          t0 = Time.now
          Goo.sparql_data_client.append_triples(@submission.id, artifacts[:mapping_triples], mime_type = "application/x-turtle")
          t1 = Time.now
          logger.info("Mapping labels asserted in #{t1 - t0} sec.")
          logger.flush
        end
      end

      def generate_missing_labels_post(artifacts = {}, logger, pagging)
        logger.info("end generate_missing_labels traversed #{artifacts[:count_classes]} classes")
        logger.info("Saved generated labels in #{artifacts[:save_in_file]}")
        artifacts[:fsave].close()
        artifacts[:fsave_mappings].close()
        logger.flush
      end

    end

    class SubmissionRDFGenerator < OntologySubmissionProcess

      def process(logger, options)
        process_rdf(logger, options[:reasoning])
      end

      private

      def process_rdf(logger, reasoning)
        # Remove processing status types before starting RDF parsing etc.
        @submission.submissionStatus = nil
        status = LinkedData::Models::SubmissionStatus.find('UPLOADED').first
        @submission.add_submission_status(status)
        @submission.save

        # Parse RDF
        begin
          unless @submission.valid?
            error = 'Submission is not valid, it cannot be processed. Check errors.'
            raise ArgumentError, error
          end
          unless @submission.uploadFilePath
            error = 'Submission is missing an ontology file, cannot parse.'
            raise ArgumentError, error
          end
          status = LinkedData::Models::SubmissionStatus.find('RDF').first
          @submission.remove_submission_status(status) #remove RDF status before starting
          zip_dst = @submission.unzip_submission(logger)
          file_path = zip_dst ? zip_dst.to_s : @submission.uploadFilePath.to_s
          generate_rdf(logger, file_path, reasoning: reasoning)
          @submission.extract_metadata
          @submission.add_submission_status(status)
          @submission.save
        rescue Exception => e
          logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
          @submission.save
          # If RDF generation fails, no point of continuing
          raise e
        end

        MissingLabelsHandler.new(@submission).process(logger, file_path: file_path)

        status = LinkedData::Models::SubmissionStatus.find('OBSOLETE').first
        begin
          generate_obsolete_classes(logger, @submission.uploadFilePath.to_s)
          @submission.add_submission_status(status)
          @submission.save
        rescue Exception => e
          logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
          @submission.save
          # if obsolete fails the parsing fails
          raise e
        end
      end

      def generate_rdf(logger, file_path, reasoning: true)
        mime_type = nil

        if @submission.hasOntologyLanguage.umls?
          triples_file_path = @submission.triples_file_path
          logger.info("Using UMLS turtle file found, skipping OWLAPI parse")
          logger.flush
          mime_type = LinkedData::MediaTypes.media_type_from_base(LinkedData::MediaTypes::TURTLE)
          SubmissionMetricsCalculator.new(@submission).generate_umls_metrics_file(triples_file_path)
        else
          output_rdf = @submission.rdf_path

          if File.exist?(output_rdf)
            logger.info("deleting old owlapi.xrdf ..")
            deleted = FileUtils.rm(output_rdf)

            if deleted.length > 0
              logger.info("deleted")
            else
              logger.info("error deleting owlapi.rdf")
            end
          end
          owlapi = LinkedData::Parser::OWLAPICommand.new(
            File.expand_path(file_path),
            File.expand_path(@submission.data_folder.to_s),
            master_file: @submission.masterFileName)

          if !reasoning
            owlapi.disable_reasoner
          end
          triples_file_path, missing_imports = owlapi.parse

          if missing_imports && missing_imports.length > 0
            @submission.missingImports = missing_imports

            missing_imports.each do |imp|
              logger.info("OWL_IMPORT_MISSING: #{imp}")
            end
          else
            @submission.missingImports = nil
          end
          logger.flush
        end

        begin
          delete_and_append(triples_file_path, logger, mime_type)
        rescue => e
          logger.error("Error sending data to triple store - #{e.response.code} #{e.class}: #{e.response.body}") if e.response&.body
          raise e
        end
        version_info = extract_version

        if version_info
          @submission.version = version_info
        end
      end



      def delete_and_append(triples_file_path, logger, mime_type = nil)
        Goo.sparql_data_client.delete_graph(@submission.id)
        Goo.sparql_data_client.put_triples(@submission.id, triples_file_path, mime_type)
        logger.info("Triples #{triples_file_path} appended in #{@submission.id.to_ntriples}")
        logger.flush
      end




      def extract_version

        query_version_info = <<eos
SELECT ?versionInfo
FROM #{@submission.id.to_ntriples}
WHERE {
<http://bioportal.bioontology.org/ontologies/versionSubject>
 <http://www.w3.org/2002/07/owl#versionInfo> ?versionInfo .
}
eos
        Goo.sparql_query_client.query(query_version_info).each_solution do |sol|
          return sol[:versionInfo].to_s
        end
        return nil
      end

      def process_callbacks(logger, callbacks, action_name, &block)
        callbacks.delete_if do |_, callback|
          begin
            if callback[action_name]
              callable = @submission.method(callback[action_name])
              yield(callable, callback)
            end
            false
          rescue Exception => e
            logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
            logger.flush

            if callback[:status]
              add_submission_status(callback[:status].get_error_status)
              @submission.save
            end

            # halt the entire processing if :required is set to true
            raise e if callback[:required]
            # continue processing of other callbacks, but not this one
            true
          end
        end
      end

      def loop_classes(logger, raw_paging, callbacks)
        page = 1
        size = 2500
        count_classes = 0
        acr = @submission.id.to_s.split("/")[-1]
        operations = callbacks.values.map { |v| v[:op_name] }.join(", ")

        time = Benchmark.realtime do
          paging = raw_paging.page(page, size)
          cls_count_set = false
          cls_count = class_count(logger)

          if cls_count > -1
            # prevent a COUNT SPARQL query if possible
            paging.page_count_set(cls_count)
            cls_count_set = true
          else
            cls_count = 0
          end

          iterate_classes = false
          # 1. init artifacts hash if not explicitly passed in the callback
          # 2. determine if class-level iteration is required
          callbacks.each { |_, callback| callback[:artifacts] ||= {}; iterate_classes = true if callback[:caller_on_each] }

          process_callbacks(logger, callbacks, :caller_on_pre) {
            |callable, callback| callable.call(callback[:artifacts], logger, paging) }

          page_len = -1
          prev_page_len = -1

          begin
            t0 = Time.now
            page_classes = paging.page(page, size).all
            total_pages = page_classes.total_pages
            page_len = page_classes.length

            # nothing retrieved even though we're expecting more records
            if total_pages > 0 && page_classes.empty? && (prev_page_len == -1 || prev_page_len == size)
              j = 0
              num_calls = LinkedData.settings.num_retries_4store

              while page_classes.empty? && j < num_calls do
                j += 1
                logger.error("Empty page encountered. Retrying #{j} times...")
                sleep(2)
                page_classes = paging.page(page, size).all
                logger.info("Success retrieving a page of #{page_classes.length} classes after retrying #{j} times...") unless page_classes.empty?
              end

              if page_classes.empty?
                msg = "Empty page #{page} of #{total_pages} persisted after retrying #{j} times. #{operations} of #{acr} aborted..."
                logger.error(msg)
                raise msg
              end
            end

            if page_classes.empty?
              if total_pages > 0
                logger.info("The number of pages reported for #{acr} - #{total_pages} is higher than expected #{page - 1}. Completing #{operations}...")
              else
                logger.info("Ontology #{acr} contains #{total_pages} pages...")
              end
              break
            end

            prev_page_len = page_len
            logger.info("#{acr}: page #{page} of #{total_pages} - #{page_len} ontology terms retrieved in #{Time.now - t0} sec.")
            logger.flush
            count_classes += page_classes.length

            process_callbacks(logger, callbacks, :caller_on_pre_page) {
              |callable, callback| callable.call(callback[:artifacts], logger, paging, page_classes, page) }

            page_classes.each { |c|
              process_callbacks(logger, callbacks, :caller_on_each) {
                |callable, callback| callable.call(callback[:artifacts], logger, paging, page_classes, page, c) }
            } if iterate_classes

            process_callbacks(logger, callbacks, :caller_on_post_page) {
              |callable, callback| callable.call(callback[:artifacts], logger, paging, page_classes, page) }
            cls_count += page_classes.length unless cls_count_set

            page = page_classes.next? ? page + 1 : nil
          end while !page.nil?

          callbacks.each { |_, callback| callback[:artifacts][:count_classes] = cls_count }
          process_callbacks(logger, callbacks, :caller_on_post) {
            |callable, callback| callable.call(callback[:artifacts], logger, paging) }
        end

        logger.info("Completed #{operations}: #{acr} in #{time} sec. #{count_classes} classes.")
        logger.flush

        # set the status on actions that have completed successfully
        callbacks.each do |_, callback|
          if callback[:status]
            add_submission_status(callback[:status])
            @submission.save
          end
        end
      end

      def generate_missing_labels_pre(artifacts = {}, logger, paging)
        file_path = artifacts[:file_path]
        artifacts[:save_in_file] = File.join(File.dirname(file_path), "labels.ttl")
        artifacts[:save_in_file_mappings] = File.join(File.dirname(file_path), "mappings.ttl")
        property_triples = LinkedData::Utils::Triples.rdf_for_custom_properties(@submission)
        Goo.sparql_data_client.append_triples(@submission.id, property_triples, mime_type = "application/x-turtle")
        fsave = File.open(artifacts[:save_in_file], "w")
        fsave.write(property_triples)
        fsave_mappings = File.open(artifacts[:save_in_file_mappings], "w")
        artifacts[:fsave] = fsave
        artifacts[:fsave_mappings] = fsave_mappings
      end

      def generate_missing_labels_pre_page(artifacts = {}, logger, paging, page_classes, page)
        artifacts[:label_triples] = []
        artifacts[:mapping_triples] = []
      end

      def generate_missing_labels_each(artifacts = {}, logger, paging, page_classes, page, c)
        prefLabel = nil

        if c.prefLabel.nil?
          rdfs_labels = c.label

          if rdfs_labels && rdfs_labels.length > 1 && c.synonym.length > 0
            rdfs_labels = (Set.new(c.label) - Set.new(c.synonym)).to_a.first

            if rdfs_labels.nil? || rdfs_labels.length == 0
              rdfs_labels = c.label
            end
          end

          if rdfs_labels and not (rdfs_labels.instance_of? Array)
            rdfs_labels = [rdfs_labels]
          end
          label = nil

          if rdfs_labels && rdfs_labels.length > 0
            label = rdfs_labels[0]
          else
            label = LinkedData::Utils::Triples.last_iri_fragment c.id.to_s
          end
          artifacts[:label_triples] << LinkedData::Utils::Triples.label_for_class_triple(
            c.id, Goo.vocabulary(:metadata_def)[:prefLabel], label)
          prefLabel = label
        else
          prefLabel = c.prefLabel
        end

        if @submission.ontology.viewOf.nil?
          loomLabel = OntologySubmission.loom_transform_literal(prefLabel.to_s)

          if loomLabel.length > 2
            artifacts[:mapping_triples] << LinkedData::Utils::Triples.loom_mapping_triple(
              c.id, Goo.vocabulary(:metadata_def)[:mappingLoom], loomLabel)
          end
          artifacts[:mapping_triples] << LinkedData::Utils::Triples.uri_mapping_triple(
            c.id, Goo.vocabulary(:metadata_def)[:mappingSameURI], c.id)
        end
      end

      def generate_missing_labels_post_page(artifacts = {}, logger, paging, page_classes, page)
        rest_mappings = LinkedData::Mappings.migrate_rest_mappings(@submission.ontology.acronym)
        artifacts[:mapping_triples].concat(rest_mappings)

        if artifacts[:label_triples].length > 0
          logger.info("Asserting #{artifacts[:label_triples].length} labels in " +
                        "#{@submission.id.to_ntriples}")
          logger.flush
          artifacts[:label_triples] = artifacts[:label_triples].join("\n")
          artifacts[:fsave].write(artifacts[:label_triples])
          t0 = Time.now
          Goo.sparql_data_client.append_triples(@submission.id, artifacts[:label_triples], mime_type = "application/x-turtle")
          t1 = Time.now
          logger.info("Labels asserted in #{t1 - t0} sec.")
          logger.flush
        else
          logger.info("No labels generated in page #{page}.")
          logger.flush
        end

        if artifacts[:mapping_triples].length > 0
          logger.info("Asserting #{artifacts[:mapping_triples].length} mappings in " +
                        "#{@submission.id.to_ntriples}")
          logger.flush
          artifacts[:mapping_triples] = artifacts[:mapping_triples].join("\n")
          artifacts[:fsave_mappings].write(artifacts[:mapping_triples])

          t0 = Time.now
          Goo.sparql_data_client.append_triples(@submission.id, artifacts[:mapping_triples], mime_type = "application/x-turtle")
          t1 = Time.now
          logger.info("Mapping labels asserted in #{t1 - t0} sec.")
          logger.flush
        end
      end

      def generate_missing_labels_post(artifacts = {}, logger, paging)
        logger.info("end generate_missing_labels traversed #{artifacts[:count_classes]} classes")
        logger.info("Saved generated labels in #{artifacts[:save_in_file]}")
        artifacts[:fsave].close()
        artifacts[:fsave_mappings].close()
        logger.flush
      end

      def generate_obsolete_classes(logger, file_path)
        @submission.bring(:obsoleteProperty) if @submission.bring?(:obsoleteProperty)
        @submission.bring(:obsoleteParent) if @submission.bring?(:obsoleteParent)
        classes_deprecated = []
        if @submission.obsoleteProperty &&
          @submission.obsoleteProperty.to_s != "http://www.w3.org/2002/07/owl#deprecated"

          predicate_obsolete = RDF::URI.new(@submission.obsoleteProperty.to_s)
          query_obsolete_predicate = <<eos
SELECT ?class_id ?deprecated
FROM #{@submission.id.to_ntriples}
WHERE { ?class_id #{predicate_obsolete.to_ntriples} ?deprecated . }
eos
          Goo.sparql_query_client.query(query_obsolete_predicate).each_solution do |sol|
            unless ["0", "false"].include? sol[:deprecated].to_s
              classes_deprecated << sol[:class_id].to_s
            end
          end
          logger.info("Obsolete found #{classes_deprecated.length} for property #{@submission.obsoleteProperty.to_s}")
        end
        if @submission.obsoleteParent.nil?
          #try to find oboInOWL obsolete.
          obo_in_owl_obsolete_class = LinkedData::Models::Class
                                        .find(LinkedData::Utils::Triples.obo_in_owl_obsolete_uri)
                                        .in(@submission).first
          if obo_in_owl_obsolete_class
            @submission.obsoleteParent = LinkedData::Utils::Triples.obo_in_owl_obsolete_uri
          end
        end
        if @submission.obsoleteParent
          class_obsolete_parent = LinkedData::Models::Class
                                    .find(@submission.obsoleteParent)
                                    .in(@submission).first
          if class_obsolete_parent
            descendents_obsolete = class_obsolete_parent.descendants
            logger.info("Found #{descendents_obsolete.length} descendents of obsolete root #{@submission.obsoleteParent.to_s}")
            descendents_obsolete.each do |obs|
              classes_deprecated << obs.id
            end
          else
            logger.error("Submission #{@submission.id.to_s} obsoleteParent #{@submission.obsoleteParent.to_s} not found")
          end
        end
        if classes_deprecated.length > 0
          classes_deprecated.uniq!
          logger.info("Asserting owl:deprecated statement for #{classes_deprecated} classes")
          save_in_file = File.join(File.dirname(file_path), "obsolete.ttl")
          fsave = File.open(save_in_file, "w")
          classes_deprecated.each do |class_id|
            fsave.write(LinkedData::Utils::Triples.obselete_class_triple(class_id) + "\n")
          end
          fsave.close()
          result = Goo.sparql_data_client.append_triples_from_file(
            @submission.id,
            save_in_file,
            mime_type = "application/x-turtle")
        end
      end

    end
  end
end

