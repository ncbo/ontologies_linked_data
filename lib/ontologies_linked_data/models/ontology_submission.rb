require 'net/ftp'
require 'net/http'
require 'uri'
require 'open-uri'
require 'cgi'
require 'benchmark'

module LinkedData
  module Models

    class OntologySubmission < LinkedData::Models::Base
      model :ontology_submission, name_with: lambda { |s| submission_id_generator(s) }
      attribute :submissionId, enforce: [:integer, :existence]

      # Configurable properties for processing
      attribute :prefLabelProperty, enforce: [:uri]
      attribute :definitionProperty, enforce: [:uri]
      attribute :synonymProperty, enforce: [:uri]
      attribute :authorProperty, enforce: [:uri]
      attribute :classType, enforce: [:uri]
      attribute :hierarchyProperty, enforce: [:uri]
      attribute :obsoleteProperty, enforce: [:uri]
      attribute :obsoleteParent, enforce: [:uri]

      # Ontology metadata
      attribute :hasOntologyLanguage, namespace: :omv, enforce: [:existence, :ontology_format]
      attribute :homepage
      attribute :publication
      attribute :uri, namespace: :omv
      attribute :naturalLanguage, namespace: :omv
      attribute :documentation, namespace: :omv
      attribute :version, namespace: :omv
      attribute :creationDate, namespace: :omv, enforce: [:date_time], default: lambda { |record| DateTime.now }
      attribute :description, namespace: :omv
      attribute :status, namespace: :omv
      attribute :contact, enforce: [:existence, :contact, :list]
      attribute :released, enforce: [:date_time, :existence]

      # Internal values for parsing - not definitive
      attribute :uploadFilePath
      attribute :diffFilePath
      attribute :masterFileName
      attribute :submissionStatus, enforce: [:submission_status, :list], default: lambda { |record| [LinkedData::Models::SubmissionStatus.find("UPLOADED").first] }
      attribute :missingImports, enforce: [:list]

      # URI for pulling ontology
      attribute :pullLocation, enforce: [:uri]

      # Link to ontology
      attribute :ontology, enforce: [:existence, :ontology]

      #Link to metrics
      attribute :metrics, enforce: [:metrics]

      # Hypermedia settings
      embed :contact, :ontology
      embed_values :submissionStatus => [:code], :hasOntologyLanguage => [:acronym]
      serialize_default :contact, :ontology, :hasOntologyLanguage, :released, :creationDate, :homepage,
                        :publication, :documentation, :version, :description, :status, :submissionId

      # Links
      links_load :submissionId, ontology: [:acronym]
      link_to LinkedData::Hypermedia::Link.new("metrics", lambda {|s| "ontologies/#{s.ontology.acronym}/submissions/#{s.submissionId}/metrics"}, self.type_uri)

      # HTTP Cache settings
      cache_segment_instance lambda {|sub| segment_instance(sub)}
      cache_segment_keys [:ontology_submission]
      cache_load ontology: [:acronym]

      # Access control
      read_restriction_based_on lambda {|sub| sub.ontology}
      access_control_load ontology: [:administeredBy, :acl, :viewingRestriction]

      def self.segment_instance(sub)
        sub.bring(:ontology) unless sub.loaded_attributes.include?(:ontology)
        sub.ontology.bring(:acronym) unless sub.ontology.loaded_attributes.include?(:acronym)
        [sub.ontology.acronym] rescue []
      end

      def self.submission_id_generator(ss)
        if !ss.ontology.loaded_attributes.include?(:acronym)
          ss.ontology.bring(:acronym)
        end
        if ss.ontology.acronym.nil?
          raise ArgumentError, "Submission cannot be saved if ontology does not have acronym"
        end
        return RDF::URI.new(
          "#{(Goo.id_prefix)}ontologies/#{CGI.escape(ss.ontology.acronym.to_s)}/submissions/#{ss.submissionId.to_s}"
        )
      end

      def self.copy_file_repository(acronym, submissionId, src, filename = nil)
        path_to_repo = File.join([LinkedData.settings.repository_folder, acronym.to_s, submissionId.to_s])
        name = filename || File.basename(File.new(src).path)
        if not Dir.exist? path_to_repo
          FileUtils.mkdir_p path_to_repo
        end
        dst = File.join([path_to_repo, name])
        FileUtils.copy(src, dst)
        if not File.exist? dst
          raise Exception, "Unable to copy #{src} to #{dst}"
        end
        return dst
      end

      def valid?
        valid_result = super
        return false unless valid_result
        sc = self.sanity_check
        return valid_result && sc
      end

      def sanity_check
        self.bring(:ontology) if self.bring?(:ontology)
        self.ontology.bring(:summaryOnly) if self.ontology.bring?(:summaryOnly)
        self.bring(:uploadFilePath) if self.bring?(:uploadFilePath)
        self.bring(:pullLocation) if self.bring?(:pullLocation)
        self.bring(:masterFileName) if self.bring?(:masterFileName)
        self.bring(:submissionStatus) if self.bring?(:submissionStatus)

        if (self.submissionStatus)
          self.submissionStatus.each do |st|
            st.bring(:code) if st.bring?(:code)
          end
        end

        if self.ontology.summaryOnly || self.archived?
          return true
        elsif self.uploadFilePath.nil? && self.pullLocation.nil?
          self.errors[:uploadFilePath] = ["In non-summary only submissions a data file or url must be provided."]
          return false
        elsif self.pullLocation
          self.errors[:pullLocation] = ["File at #{self.pullLocation.to_s} does not exist"]
          return remote_file_exists?(self.pullLocation.to_s)
        end

        zip = LinkedData::Utils::FileHelpers.zip?(self.uploadFilePath)
        files =  LinkedData::Utils::FileHelpers.files_from_zip(self.uploadFilePath) if zip
        if not zip and self.masterFileName.nil?
          return true
        elsif zip and files.length == 1
          self.masterFileName = files.first
          return true
        elsif zip and self.masterFileName.nil?
          #zip and masterFileName not set. The user has to choose.
          if self.errors[:uploadFilePath].nil?
            self.errors[:uploadFilePath] = []
          end

          #check for duplicated names
          repeated_names =  LinkedData::Utils::FileHelpers.repeated_names_in_file_list(files)
          if repeated_names.length > 0
            names = repeated_names.keys.to_s
            self.errors[:uploadFilePath] <<
            "Zip file contains file names (#{names}) in more than one folder."
            return false
          end

          #error message with options to choose from.
          self.errors[:uploadFilePath] << {
            :message => "Zip file detected, choose the master file.", :options => files }
          return false

        elsif zip and not self.masterFileName.nil?
          #if zip and the user chose a file then we make sure the file is in the list.
          files =  LinkedData::Utils::FileHelpers.files_from_zip(self.uploadFilePath)
          if not files.include? self.masterFileName
            if self.errors[:uploadFilePath].nil?
              self.errors[:uploadFilePath] = []
              self.errors[:uploadFilePath] << {
                :message =>
              "The selected file `#{self.masterFileName}` is not included in the zip file",
                :options => files }
            end
          end
        end
        return true
      end

      def data_folder
        return File.join(LinkedData.settings.repository_folder,
                         self.ontology.acronym.to_s,
                         self.submissionId.to_s)
      end

      def zip_folder
        return File.join([self.data_folder, "unzipped"])
      end

      def unzip_submission(logger)
        zip = LinkedData::Utils::FileHelpers.zip?(self.uploadFilePath)
        zip_dst = nil

        if zip
          zip_dst = self.zip_folder

          if Dir.exist? zip_dst
            FileUtils.rm_r [zip_dst]
          end
          FileUtils.mkdir_p zip_dst
          extracted = LinkedData::Utils::FileHelpers.unzip(self.uploadFilePath, zip_dst)

          # Set master file name automatically if there is only one file
          if extracted.length == 1 && self.masterFileName.nil?
            self.masterFileName = extracted.first.name
            self.save
          end

          logger.info("Files extracted from zip #{extracted}")
          logger.flush
        end
        return zip_dst
      end

      # accepts another submission in 'older' (it should be an 'older' ontology version)
      def diff(logger, older)
        begin
          self.bring_remaining
          self.bring(:diffFilePath)
          self.bring(:uploadFilePath)
          older.bring(:uploadFilePath)
          LinkedData::Diff.logger = logger
          bubastis = LinkedData::Diff::BubastisDiffCommand.new(
              File.expand_path(older.uploadFilePath),
              File.expand_path(self.uploadFilePath)
          )
          self.diffFilePath = bubastis.diff
          self.save
          #
          # TODO: Add submission status value for 'CREATED_DIFF' or something?
          #
          logger.info("Bubastis diff processed")
          logger.flush
        rescue Exception => e
          logger.error("Bubastis diff failed: " + e.message)
          logger.flush
          raise e
        end
      end

      def generate_rdf(logger, file_path,reasoning=true)
        mime_type = nil

        if self.hasOntologyLanguage.umls?
          zip = LinkedData::Utils::FileHelpers.zip?(self.uploadFilePath)
          file_name = zip ?
              File.join(File.expand_path(self.data_folder.to_s), self.masterFileName) : self.uploadFilePath.to_s
          triples_file_path = File.expand_path(file_name)
          logger.info("Using UMLS turtle file, skipping OWLAPI parse")
          logger.flush
          mime_type = LinkedData::MediaTypes.media_type_from_base(LinkedData::MediaTypes::TURTLE)
        else
          labels_file = File.join(File.dirname(file_path), "labels.ttl")
          owlapi = LinkedData::Parser::OWLAPICommand.new(
              File.expand_path(file_path),
              File.expand_path(self.data_folder.to_s),
              self.masterFileName)
          if !reasoning
            owlapi.disable_reasoner
          end
          triples_file_path, missing_imports = owlapi.parse

          if missing_imports && missing_imports.length > 0
            self.missingImports = missing_imports
            missing_imports.each do |imp|
              logger.info("OWL_IMPORT_MISSING: #{imp}")
            end
          else
            self.missingImports = nil
          end
          logger.flush
        end
        delete_and_append(triples_file_path, logger, mime_type)
        version_info = extract_version()
        if version_info
          self.version = version_info
        end
      end

      def extract_version

        query_version_info = <<eos
SELECT ?versionInfo
FROM #{self.id.to_ntriples}
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

      def generate_missing_labels(logger, file_path)
        return if self.hasOntologyLanguage.umls?

        save_in_file = File.join(File.dirname(file_path), "labels.ttl")
        property_triples = LinkedData::Utils::Triples.rdf_for_custom_properties(self)
        result = Goo.sparql_data_client.append_triples(
            self.id,
            property_triples,
            mime_type="application/x-turtle")
        count_classes = 0
        page = 1
        size = 2500
        fsave = File.open(save_in_file,"w")
        fsave.write(property_triples)
        paging = LinkedData::Models::Class.in(self).include(:prefLabel, :synonym, :label).page(page, size)

        begin #per page
          label_triples = []
          t0 = Time.now
          page_classes = paging.page(page,size).read_only.all
          t1 = Time.now
          logger.info(
              "#{page_classes.length} in page #{page} classes for #{self.id.to_ntriples} (#{t1 - t0} sec)." +
                  " Total pages #{page_classes.total_pages}.")
          logger.flush

          page_classes.each do |c|
            if c.prefLabel.nil?
              rdfs_labels = c.label

              if rdfs_labels && rdfs_labels.length > 1 && c.synonym.length > 0
                rdfs_labels = (Set.new(c.label) -  Set.new(c.synonym)).to_a.first
                rdfs_labels = c.label if rdfs_labels.nil? || rdfs_labels.length == 0
              end
              rdfs_labels = [rdfs_labels] if rdfs_labels and not (rdfs_labels.instance_of?Array)
              label = nil

              if rdfs_labels && rdfs_labels.length > 0
                label = rdfs_labels[0]
              else
                label = LinkedData::Utils::Triples.last_iri_fragment c.id.to_s
              end
              label_triples << LinkedData::Utils::Triples.label_for_class_triple(
                  c.id, Goo.vocabulary(:metadata_def)[:prefLabel],label)
            end
            count_classes += 1
          end

          if (label_triples.length > 0)
            logger.info("Asserting #{label_triples.length} labels in #{self.id.to_ntriples}")
            logger.flush
            label_triples = label_triples.join "\n"
            fsave.write(label_triples)
            t0 = Time.now
            result = Goo.sparql_data_client.append_triples(
                self.id,
                label_triples,
                mime_type="application/x-turtle")
            t1 = Time.now
            logger.info("Labels asserted in #{t1 - t0} sec.")
            logger.flush
          else
            logger.info("No labels generated in page #{page_classes.total_pages}.")
            logger.flush
          end
          page = page_classes.next? ? page + 1 : nil
        end while !page.nil?
        logger.info("end generate_missing_labels traversed #{count_classes} classes")
        logger.info("Saved generated labels in #{save_in_file}")
        fsave.close()
        logger.flush
      end

      def generate_obsolete_classes(logger, file_path)
        self.bring(:obsoleteProperty) if self.bring?(:obsoleteProperty)
        self.bring(:obsoleteParent) if self.bring?(:obsoleteParent)
        classes_deprecated = []
        if self.obsoleteProperty &&
          self.obsoleteProperty.to_s != "http://www.w3.org/2002/07/owl#deprecated"

          predicate_obsolete = RDF::URI.new(self.obsoleteProperty.to_s)
          query_obsolete_predicate = <<eos
SELECT ?class_id ?deprecated
FROM #{self.id.to_ntriples}
WHERE { ?class_id #{predicate_obsolete.to_ntriples} ?deprecated . }
eos
          Goo.sparql_query_client.query(query_obsolete_predicate).each_solution do |sol|
            unless sol[:deprecated].to_s == "false"
              classes_deprecated << sol[:class_id].to_s
            end
          end
          logger.info("Obsolete found #{classes_deprecated.length} for property #{self.obsoleteProperty.to_s}")
        end
        if self.obsoleteParent
          class_obsolete_parent = LinkedData::Models::Class
                                  .find(self.obsoleteParent)
                                  .in(self).first
          if class_obsolete_parent
            descendents_obsolete = LinkedData::Models::Class
                                      .where(ancestors: class_obsolete_parent)
                                      .in(self)
                                      .all
            logger.info("Found #{descendents_obsolete.length} descendents of obsolete root #{self.obsoleteParent.to_s}")
            descendents_obsolete.each do |obs|
              classes_deprecated << obs.id
            end
          else
            logger.error("Submission #{self.id.to_s} obsoleteParent #{self.obsoleteParent.to_s} not found")
          end
        end
        if classes_deprecated.length > 0
          classes_deprecated.uniq!
          logger.info("Asserting owl:deprecated statement for #{classes_deprecated} classes")
          save_in_file = File.join(File.dirname(file_path), "obsolete.ttl")
          fsave = File.open(save_in_file,"w")
          classes_deprecated.each do |class_id|
            fsave.write(LinkedData::Utils::Triples.obselete_class_triple(class_id) + "\n")
          end
          fsave.close()
          result = Goo.sparql_data_client.append_triples_from_file(
                          self.id,
                          save_in_file,
                          mime_type="application/x-turtle")
        end
      end

      def add_submission_status(status)
        valid = status.is_a?(LinkedData::Models::SubmissionStatus)
        raise ArgumentError, "The status being added is not SubmissionStatus object" unless valid

        #archive removes the other status
        if status.archived?
          self.submissionStatus = [status]
          return self.submissionStatus
        end

        self.submissionStatus ||= []
        s = self.submissionStatus.dup

        if (status.error?)
          # remove the corresponding non_error status (if exists)
          non_error_status = status.get_non_error_status()
          s.reject! { |stat| stat.get_code_from_id() == non_error_status.get_code_from_id() }
        else
          # remove the corresponding non_error status (if exists)
          error_status = status.get_error_status()
          s.reject! { |stat| stat.get_code_from_id() == error_status.get_code_from_id() }
        end

        has_status = s.any? { |s| s.get_code_from_id() == status.get_code_from_id() }
        s << status unless has_status
        self.submissionStatus = s

      end

      def remove_submission_status(status)
        if (self.submissionStatus)
          valid = status.is_a?(LinkedData::Models::SubmissionStatus)
          raise ArgumentError, "The status being removed is not SubmissionStatus object" unless valid
          s = self.submissionStatus.dup

          # remove that status as well as the error status for the same status
          s.reject! { |stat|
            stat_code = stat.get_code_from_id()
            stat_code == status.get_code_from_id() ||
                stat_code == status.get_error_status().get_code_from_id()
          }
          self.submissionStatus = s
        end
      end

      def set_ready()
        ready_status = LinkedData::Models::SubmissionStatus.get_ready_status

        ready_status.each do |code|
          status = LinkedData::Models::SubmissionStatus.find(code).include(:code).first
          add_submission_status(status)
        end
      end

      # allows to optionally submit a list of statuses
      # that would define the "ready" state of this
      # submission in this context
      def ready?(options={})
        status = options[:status] || :ready
        status = status.is_a?(Array) ? status : [status]
        return true if status.include?(:any)
        return false unless self.submissionStatus

        if status.include? :ready
          return LinkedData::Models::SubmissionStatus.status_ready?(self.submissionStatus)
        else
          status.each do |x|
            return false if self.submissionStatus.select { |x1|
              x1.get_code_from_id() == x.to_s.upcase
            }.length == 0
          end
          return true
        end
      end

      def archived?
        return ready?(status: [:archived])
      end

      ########################################
      # Possible options with their defaults:
      #   process_rdf       = true
      #   index_search      = true
      #   run_metrics       = true
      #   reasoning         = true
      #   archive           = false
      #######################################
      def process_submission(logger, options={})
        # Wrap the whole process so we can email results
        begin
          process_rdf = options[:process_rdf] == false ? false : true
          index_search = options[:index_search] == false ? false : true
          run_metrics = options[:run_metrics] == false ? false : true
          reasoning = options[:reasoning] == false ? false : true
          archive = options[:archive] == true ? true : false
          diff = options[:diff] == true ? true : false

          self.bring_remaining
          self.ontology.bring_remaining

          logger.info("Starting to process #{self.ontology.acronym}/submissions/#{self.submissionId}")
          logger.flush
          LinkedData::Parser.logger = logger
          status = nil

          #TODO: for now, archiving simply means add "ARCHIVED" status. We need to expand the logic to include other appropriate actions (ie deleting backend, files, etc.)
          if (archive)
            self.submissionStatus = nil
            status = LinkedData::Models::SubmissionStatus.find("ARCHIVED").first
            add_submission_status(status)
          else
            if (process_rdf)
              if not self.valid?
                error = "Submission is not valid, it cannot be processed. Check errors"
                logger.info(error)
                logger.flush
                raise ArgumentError, error
              end

              if not self.uploadFilePath
                error = "Submission is missing an ontology file, cannot parse"
                logger.info(error)
                logger.flush
                raise ArgumentError, error
              end

              file_path = nil
              status = LinkedData::Models::SubmissionStatus.find("RDF").first
              #remove RDF status before starting
              remove_submission_status(status)

              begin
                zip_dst = unzip_submission(logger)
                file_path = zip_dst ? zip_dst.to_s : self.uploadFilePath.to_s
                generate_rdf(logger, file_path, reasoning=reasoning)
                add_submission_status(status)
              rescue Exception => e
                logger.info(e.message)
                logger.flush
                add_submission_status(status.get_error_status)
                self.save
                # if rdf generation fails, no point of continuing
                raise e
              end

              status = LinkedData::Models::SubmissionStatus.find("RDF_LABELS").first
              #remove RDF_LABELS status before starting
              remove_submission_status(status)

              begin
                generate_missing_labels(logger, file_path)
                add_submission_status(status)
              rescue Exception => e
                logger.info(e.message)
                logger.flush
                add_submission_status(status.get_error_status)
                self.save
                # if rdf label generation fails, no point of continuing
                raise e
              end

              status = LinkedData::Models::SubmissionStatus.find("OBSOLETE").first
              remove_submission_status(status)
              begin
                generate_obsolete_classes(logger, file_path)
                add_submission_status(status)
              rescue Exception => e
                logger.info(e.message)
                logger.flush
                add_submission_status(status.get_error_status)
                self.save
                # if obsolete fails the parsing fails
                raise e
              end
            end

            parsed = ready?(status: [:rdf, :rdf_labels])

            if (index_search)
              raise Exception, "The submission #{self.ontology.acronym}/submissions/#{self.submissionId} cannot be indexed because it has not been successfully parsed" unless parsed
              status = LinkedData::Models::SubmissionStatus.find("INDEXED").first
              #remove INDEXED status before starting
              remove_submission_status(status)

              begin
                index(logger, false)
                add_submission_status(status)
              rescue Exception => e
                add_submission_status(status.get_error_status)
                logger.info(e.message)
                logger.flush
              end
            end

            if (run_metrics)
              raise Exception, "Metrics cannot be generated on the submission #{self.ontology.acronym}/submissions/#{self.submissionId} because it has not been successfully parsed" unless parsed
              status = LinkedData::Models::SubmissionStatus.find("METRICS").first
              #remove METRICS status before starting
              remove_submission_status(status)

              begin
                process_metrics(logger)
                add_submission_status(status)
              rescue Exception => e
                self.metrics = nil
                add_submission_status(status.get_error_status)
                logger.info(e.message)
                logger.flush
              end
            end

            if diff
              # Get previous submission from ontology.submissions
              self.ontology.bring(:submissions)
              submissions = self.ontology.submissions
              unless submissions.nil?
                submissions.each {|s| s.bring(:submissionId, :diffFilePath)}
                # Sort submissions in descending order of submissionId, extract last two submissions
                recent_submissions = submissions.sort {|a,b| b.submissionId <=> a.submissionId}[0..1]
                if recent_submissions.length > 1
                  # validate that the most recent submission is the current submission
                  if self.submissionId == recent_submissions.first.submissionId
                    prev = recent_submissions.last
                    # Ensure that prev is older than the current submission
                    if self.submissionId > prev.submissionId
                      # generate a diff
                      begin
                        self.diff(logger, prev)
                      rescue
                        # pass, self.diff logs all errors
                      end
                    end
                  end
                else
                  logger.info("Bubastis diff: no older submissions available for diffs.")
                end
              else
                logger.info("Bubastis diff: no submissions available for diffs.")
              end
            end

          end

          self.save
          logger.info("Submission processing completed successfully")
          logger.flush
        ensure
          # make sure results get emailed
          begin
            LinkedData::Utils::Notifications.submission_processed(self)
          rescue Exception => e
            logger.info("Email sending failed: #{e.message}\n#{e.backtrace.join("\n\t")}"); logger.flush
          end
          return self
        end
      end

      def process_metrics(logger)
        metrics = LinkedData::Metrics.metrics_for_submission(self, logger)
        metrics.id = RDF::URI.new(self.id.to_s + "/metrics")
        exist_metrics = LinkedData::Models::Metric.find(metrics.id).first
        exist_metrics.delete if exist_metrics
        metrics.save
        self.metrics = metrics
        return self
      end

      def index(logger, optimize = true)
        page = 1
        size = 2500

        count_classes = 0
        time = Benchmark.realtime do
          self.bring(:ontology) if self.bring?(:ontology)
          logger.info("Indexing ontology: #{self.ontology.acronym}...")
          t0 = Time.now
          self.ontology.unindex()
          logger.info("Removing ontology index (#{Time.now - t0}s)"); logger.flush

          paging = LinkedData::Models::Class.in(self).include(:unmapped)
                                  .page(page,size)
          begin #per page
            t0 = Time.now
            page_classes = paging.page(page,size).all
            logger.info("Page #{page} of #{page_classes.total_pages} classes retrieved in #{Time.now - t0} sec.")
            t0 = Time.now
            page_classes.each do |c|
              LinkedData::Models::Class.map_attributes(c,paging.equivalent_predicates)
            end
            logger.info("Page #{page} of #{page_classes.total_pages} attributes mapped in #{Time.now - t0} sec.")
            count_classes += page_classes.length
            t0 = Time.now

            LinkedData::Models::Class.indexBatch(page_classes)
            logger.info("Page #{page} of #{page_classes.total_pages} indexed solr in #{Time.now - t0} sec.")

            logger.info("Page #{page} of #{page_classes.total_pages} completed")
            logger.flush

            page = page_classes.next? ? page + 1 : nil
          end while !page.nil?
          t0 = Time.now
          LinkedData::Models::Class.indexCommit()
          logger.info("Solr index commit in #{Time.now - t0} sec.")
        end
        logger.info("Completed indexing ontology: #{self.ontology.acronym} in #{time} sec. #{count_classes} classes.")
        logger.flush

        if optimize
          logger.info("Optimizing index...")
          time = Benchmark.realtime do
            LinkedData::Models::Class.indexOptimize()
          end
          logger.info("Completed optimizing index in #{time} sec.")
        end
      end

      # Override delete to add removal from the search index
      #TODO: revise this with a better process
      def delete(*args)
        options = {}
        args.each {|e| options.merge!(e) if e.is_a?(Hash)}
        remove_index = options[:remove_index] ? true : false

        super(*args)
        self.ontology.unindex()

        self.bring(:metrics) if self.bring?(:metrics)
        self.metrics.delete if self.metrics

        if remove_index
          # need to re-index the previous submission (if exists)
          self.ontology.bring(:submissions)
          if self.ontology.submissions.length > 0
            prev_sub = self.ontology.latest_submission()

            if prev_sub
              prev_sub.index(LinkedData::Parser.logger || Logger.new($stderr))
            end
          end
        end
      end

      def roots(extra_include=nil,aggregate_children=false)

        unless self.loaded_attributes.include?(:hasOntologyLanguage)
          self.bring(:hasOntologyLanguage)
        end
        isSkos = false
        if self.hasOntologyLanguage
          isSkos = self.hasOntologyLanguage.skos?
        end

        classes = []
        if !isSkos
          owlThing = Goo.vocabulary(:owl)["Thing"]
          classes = LinkedData::Models::Class.where(parents: owlThing).in(self)
                                             .disable_rules
                                             .all
        else
          root_skos = <<eos
SELECT DISTINCT ?root WHERE {
GRAPH #{self.id.to_ntriples} { 
  ?x #{RDF::SKOS[:hasTopConcept].to_ntriples} ?root .
}}
eos
          #needs to get cached
          class_ids = []
          Goo.sparql_query_client.query(root_skos, { :graphs => [self.id] }).each_solution do |s|
            class_ids << s[:root]
          end
          class_ids.each do |id|
            classes << LinkedData::Models::Class.find(id).in(self).disable_rules.first
          end
        end
        roots = []
        where = LinkedData::Models::Class.in(self)
                     .models(classes)
                     .include(:prefLabel, :definition, :synonym, :obsolete)
        if extra_include
          [:prefLabel, :definition, :synonym, :obsolete, :childrenCount].each do |x|
            extra_include.delete x
          end
        end
        load_children = false
        if extra_include
          load_children = extra_include.delete :children
          if !load_children
            load_children = extra_include.select { |x| x.instance_of?(Hash) && x.include?(:children) }
            if load_children
              extra_include = extra_include.select { |x| !(x.instance_of?(Hash) && x.include?(:children)) }
            end
          end
          if extra_include.length > 0
            where.include(extra_include)
          end
        end
        where.aggregate(:count,:children) if aggregate_children
        where.all
        if load_children
          LinkedData::Models::Class.partially_load_children(roots,99,self)
        end
        classes.each do |c|
          roots << c if (c.obsolete.nil?) || (c.obsolete == false)
        end
        return roots
      end

      def download_and_store_ontology_file
        file, filename = download_ontology_file
        file_location = self.class.copy_file_repository(self.ontology.acronym, self.submissionId, file, filename)
        self.uploadFilePath = file_location
        return file, filename
      end

      def remote_file_exists?(url)
        begin
          url = URI.parse(url)
          if url.kind_of?(URI::FTP)
            check = check_ftp_file(url)
          else
            check = check_http_file(url)
          end
        rescue Exception
          check = false
        end
        check
      end

      def download_ontology_file
        file, filename = LinkedData::Utils::FileHelpers.download_file(self.pullLocation.to_s)
        return file, filename
      end

      def delete_classes_graph
        Goo.sparql_data_client.delete_graph(self.id)
      end

      private

      def delete_and_append(triples_file_path, logger, mime_type = nil)
        Goo.sparql_data_client.delete_graph(self.id)
        Goo.sparql_data_client.put_triples(self.id, triples_file_path, mime_type)
        logger.info("Triples #{triples_file_path} appended in #{self.id.to_ntriples}")
        logger.flush
      end

      def check_http_file(url)
        session = Net::HTTP.new(url.host, url.port)
        session.use_ssl = true if url.port == 443
        session.start do |http|
          response_valid = http.head(url.request_uri).code.to_i < 400
          return response_valid
        end
      end

      def check_ftp_file(uri)
        ftp = Net::FTP.new(uri.host, uri.user, uri.password)
        ftp.login
        begin
          file_exists = ftp.size(uri.path) > 0
        rescue Exception => e
          # Check using another method
          path = uri.path.split("/")
          filename = path.pop
          path = path.join("/")
          ftp.chdir(path)
          files = ftp.dir
          # Dumb check, just see if the filename is somewhere in the list
          files.each { |file| return true if file.include?(filename) }
        end
        file_exists
      end

    end
  end
end
