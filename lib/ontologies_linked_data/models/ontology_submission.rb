require 'net/ftp'
require 'net/http'
require 'uri'
require 'open-uri'
require 'cgi'
require 'benchmark'
require 'csv'
require 'fileutils'

module LinkedData
  module Models

    class OntologySubmission < LinkedData::Models::Base

      include LinkedData::Concerns::SubmissionProcessable
      include LinkedData::Concerns::OntologySubmission::MetadataExtractor
      include LinkedData::Concerns::OntologySubmission::Validators
      extend LinkedData::Concerns::OntologySubmission::DefaultCallbacks

      include SKOS::ConceptSchemes
      include SKOS::RootsFetcher

      FLAT_ROOTS_LIMIT = 1000
      # default file permissions for files copied from tempdir
      REPOSITORY_FILE_MODE = 0o660   # rw-rw----
      REPOSITORY_DIR_MODE  = 0o2770  # rwxrws--- + set-GID

      model :ontology_submission, scheme: File.join(__dir__, '../../../config/schemes/ontology_submission.yml'),
            name_with: ->(s) { submission_id_generator(s) }

      attribute :submissionId, type: :integer, enforce: [:existence]

      # Object description properties metadata
      # Configurable properties for processing
      attribute :prefLabelProperty, type: :uri, default: ->(s) { Goo.vocabulary(:skos)[:prefLabel] }
      attribute :definitionProperty, type: :uri, default: ->(s) { Goo.vocabulary(:skos)[:definition] }
      attribute :synonymProperty, type: :uri, default: ->(s) { Goo.vocabulary(:skos)[:altLabel] }
      attribute :authorProperty, type: :uri, default: ->(s) { Goo.vocabulary(:dc)[:creator] }
      attribute :classType, type: :uri
      attribute :hierarchyProperty, type: :uri, default: ->(s) { default_hierarchy_property(s) }
      attribute :obsoleteProperty, type: :uri, default: ->(s) { Goo.vocabulary(:owl)[:deprecated] }
      attribute :obsoleteParent, type: :uri
      attribute :createdProperty, type: :uri, default: ->(s) { Goo.vocabulary(:dc)[:created] }
      attribute :modifiedProperty, type: :uri, default: ->(s) { Goo.vocabulary(:dc)[:modified] }

      # Ontology metadata
      # General metadata
      attribute :versionIRI, namespace: :owl, type: :uri, enforce: [:distinct_of_uri]
      attribute :version, namespace: :omv, enforce: [:safe_text_64]
      attribute :status, namespace: :omv, default: ->(x) { 'production' }
      attribute :deprecated, namespace: :owl, type: :boolean, default: ->(x) { false }
      attribute :hasOntologyLanguage, namespace: :omv, type: :ontology_format, enforce: [:existence]
      attribute :hasFormalityLevel, namespace: :omv, type: :uri
      attribute :hasOntologySyntax, namespace: :omv, type: :uri, default: ->(s) { ontology_syntax_default(s) }
      attribute :naturalLanguage, namespace: :omv, type: %i[list]
      attribute :isOfType, namespace: :omv, type: :uri
      attribute :identifier, namespace: :dct, type: %i[list uri], enforce: [:distinct_of_uri]

      # Description metadata
      attribute :description, namespace: :omv, enforce: %i[concatenate], fuzzy_search: true

      # attribute :homepage
      # attribute :documentation, namespace: :omv
      # attribute :publication
      # attribute :uri, namespace: :omv
      attribute :homepage, namespace: :foaf, type: :uri
      attribute :documentation, namespace: :omv, type: :uri
      attribute :publication, type: %i[uri list]
      attribute :uri, namespace: :omv, type: :uri, enforce: %i[distinct_of_identifier], fuzzy_search: true

      attribute :notes, namespace: :omv, type: :list
      attribute :keywords, namespace: :omv, type: :list
      attribute :hiddenLabel, namespace: :skos, type: :list
      attribute :alternative, namespace: :dct, type: :list
      attribute :abstract, namespace: :dct

      # Licensing metadata
      attribute :hasLicense, namespace: :omv, type: :uri
      attribute :useGuidelines, namespace: :cc
      attribute :morePermissions, namespace: :cc
      # attribute :copyrightHolder, namespace: :schema, type: :Agent

      # Date metadata
      attribute :released, type: :date_time, enforce: [:existence]
      attribute :valid, namespace: :dct, type: :date_time
      attribute :curatedOn, namespace: :pav, type: %i[date_time list]
      attribute :creationDate, namespace: :omv, type: :date_time, default: ->(x) { Date.today.to_datetime }
      attribute :modificationDate, namespace: :omv, type: :date_time

      # Person and organizations metadata
      attribute :contact, type: %i[contact list], enforce: [:existence]
      # attribute :hasCreator, namespace: :omv, type: %i[list Agent]
      # attribute :hasContributor, namespace: :omv, type: %i[list Agent]
      # attribute :curatedBy, namespace: :pav, type: %i[list Agent]
      # attribute :publisher, namespace: :dct, type: %i[list Agent]
      # attribute :fundedBy, namespace: :foaf, type: %i[list Agent]
      # attribute :endorsedBy, namespace: :omv, type: %i[list Agent]
      # attribute :translator, namespace: :schema, type: %i[list Agent]

      # Community metadata
      attribute :audience, namespace: :dct
      attribute :repository, namespace: :doap, type: :uri
      attribute :bugDatabase, namespace: :doap, type: :uri
      attribute :mailingList, namespace: :doap
      attribute :toDoList, namespace: :voaf, type: :list
      attribute :award, namespace: :schema, type: :list

      # Usage metadata
      attribute :knownUsage, namespace: :omv, type: :list
      attribute :designedForOntologyTask, namespace: :omv, type: %i[list uri]
      attribute :hasDomain, namespace: :omv, type: :list, default: ->(s) { ontology_has_domain(s) }
      attribute :coverage, namespace: :dct
      attribute :example, namespace: :vann, type: :list

      # Methodology metadata
      attribute :conformsToKnowledgeRepresentationParadigm, namespace: :omv
      attribute :usedOntologyEngineeringMethodology, namespace: :omv
      attribute :usedOntologyEngineeringTool, namespace: :omv, type: %i[list]
      attribute :accrualMethod, namespace: :dct, type: %i[list]
      attribute :accrualPeriodicity, namespace: :dct
      attribute :accrualPolicy, namespace: :dct
      attribute :competencyQuestion, namespace: :mod, type: :list
      attribute :wasGeneratedBy, namespace: :prov, type: :list
      attribute :wasInvalidatedBy, namespace: :prov, type: :list

      # Links
      attribute :pullLocation, type: :uri # URI for pulling ontology
      attribute :isFormatOf, namespace: :dct, type: :uri
      attribute :hasFormat, namespace: :dct, type: %i[uri list]
      attribute :dataDump, namespace: :void, type: :uri, default: -> (s) { data_dump_default(s) }
      attribute :csvDump, type: :uri, default: -> (s) { csv_dump_default(s) }
      attribute :uriLookupEndpoint, namespace: :void, type: :uri, default: -> (s) { uri_lookup_default(s) }
      attribute :openSearchDescription, namespace: :void, type: :uri, default: -> (s) { open_search_default(s) }
      attribute :source, namespace: :dct, type: :list
      attribute :endpoint, namespace: :sd, type: %i[uri list],
                default: ->(s) { default_sparql_endpoint(s) }
      attribute :includedInDataCatalog, namespace: :schema, type: %i[list uri]

      # Relations
      attribute :hasPriorVersion, namespace: :omv, type: :uri
      attribute :hasPart, namespace: :dct, type: %i[uri list]
      attribute :ontologyRelatedTo, namespace: :door, type: %i[list uri]
      attribute :similarTo, namespace: :door, type: %i[list uri]
      attribute :comesFromTheSameDomain, namespace: :door, type: %i[list uri]
      attribute :isAlignedTo, namespace: :door, type: %i[list uri]
      attribute :isBackwardCompatibleWith, namespace: :omv, type: %i[list uri]
      attribute :isIncompatibleWith, namespace: :omv, type: %i[list uri]
      attribute :hasDisparateModelling, namespace: :door, type: %i[list uri]
      attribute :hasDisjunctionsWith, namespace: :voaf, type: %i[uri list]
      attribute :generalizes, namespace: :voaf, type: %i[list uri]
      attribute :explanationEvolution, namespace: :door, type: %i[list uri]
      attribute :useImports, namespace: :omv, type: %i[list uri]
      attribute :usedBy, namespace: :voaf, type: %i[uri list]
      attribute :workTranslation, namespace: :schema, type: %i[uri list]
      attribute :translationOfWork, namespace: :schema, type: %i[uri list]

      # Content metadata
      attribute :uriRegexPattern, namespace: :void
      attribute :preferredNamespaceUri, namespace: :vann, type: :uri
      attribute :preferredNamespacePrefix, namespace: :vann
      attribute :exampleIdentifier, namespace: :idot
      attribute :keyClasses, namespace: :omv, type: %i[list]
      attribute :metadataVoc, namespace: :voaf, type: %i[uri list]
      attribute :uploadFilePath
      attribute :diffFilePath
      attribute :masterFileName

      # Media metadata
      attribute :associatedMedia, namespace: :schema, type: %i[uri list]
      attribute :depiction, namespace: :foaf, type: %i[uri list]
      attribute :logo, namespace: :foaf, type: :uri

      # Metrics metadata
      attribute :metrics, type: :metrics

      # Configuration metadata

      # Internal values for parsing - not definitive
      attribute :submissionStatus, type: %i[submission_status list], default: ->(record) { [LinkedData::Models::SubmissionStatus.find("UPLOADED").first] }
      attribute :missingImports, type: :list

      # Link to ontology
      attribute :ontology, type: :ontology, enforce: [:existence]

      # System-controlled attributes that should not be set by API clients
      system_controlled :submissionId, :uploadFilePath, :diffFilePath, :missingImports

      def self.agents_attrs
        return [] #TODO implement agent separately
        %i[hasCreator publisher copyrightHolder hasContributor
         translator endorsedBy fundedBy curatedBy]
      end

      # Hypermedia settings
      embed *%i[contact ontology metrics] + agents_attrs

      def self.embed_values_hash
        out = {
          submissionStatus: [:code], hasOntologyLanguage: [:acronym]
        }

        # TODO implement agents separately
        # agent_attributes = LinkedData::Models::Agent.goo_attrs_to_load +
        #   [identifiers: LinkedData::Models::AgentIdentifier.goo_attrs_to_load, affiliations: LinkedData::Models::Agent.goo_attrs_to_load]
        #
        # agents_attrs.each { |k| out[k] = agent_attributes }
        out
      end

      embed_values self.embed_values_hash

      serialize_default :contact, :ontology, :hasOntologyLanguage, :released, :creationDate, :homepage,
                        :publication, :documentation, :version, :description, :status, :submissionId

      # Links
      links_load :submissionId, ontology: [:acronym]
      link_to LinkedData::Hypermedia::Link.new("metrics", ->(s) { "#{self.ontology_link(s)}/submissions/#{s.submissionId}/metrics" }, self.type_uri)
      LinkedData::Hypermedia::Link.new("download", ->(s) { "#{self.ontology_link(s)}/submissions/#{s.submissionId}/download" }, self.type_uri)

      # Hypermedia settings
      embed :contact, :ontology
      embed_values :submissionStatus => [:code], :hasOntologyLanguage => [:acronym]
      serialize_default :contact, :ontology, :hasOntologyLanguage, :released, :creationDate, :homepage,
                        :publication, :documentation, :version, :description, :status, :submissionId
      serialize_never :uploadFilePath, :diffFilePath

      # HTTP Cache settings
      cache_timeout 3600
      cache_segment_instance lambda {|sub| segment_instance(sub)}
      cache_segment_keys [:ontology_submission]
      cache_load ontology: [:acronym]

      # Access control
      read_restriction_based_on lambda { |sub| sub.ontology }
      access_control_load ontology: [:administeredBy, :acl, :viewingRestriction]

      def initialize(*args)
        super(*args)
        @mutex = Mutex.new
      end

      def synchronize(&block)
        @mutex.synchronize(&block)
      end

      def URI=(value)
        self.uri  = value
      end

      def URI
        self.uri
      end

      def self.ontology_link(m)
        ontology_link = ""

        if m.class == self
          m.bring(:ontology) if m.bring?(:ontology)

          begin
            m.ontology.bring(:acronym) if m.ontology.bring?(:acronym)
            ontology_link = "ontologies/#{m.ontology.acronym}"
          rescue Exception => e
            ontology_link = ""
          end
        end
        ontology_link
      end

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

      def self.copy_file_repository(acronym, submission_id, src, filename = nil)
        path_to_repo = File.join(
          LinkedData.settings.repository_folder,
          acronym.to_s,
          submission_id.to_s
        )

        name = filename || File.basename(src)
        dst  = File.join(path_to_repo, name)

        begin
          FileUtils.mkdir_p(path_to_repo)
          FileUtils.chmod(REPOSITORY_DIR_MODE, path_to_repo)

          FileUtils.copy(src, dst)
          # Uploaded files are initially written to a Tempfile in tmpdir with
          # permissions 0600 (owner read/write only) for security. To ensure
          # repository files are also accessible by the service group as intended,
          # we explicitly chmod the destination file to REPOSITORY_FILE_MODE.
          FileUtils.chmod(REPOSITORY_FILE_MODE, dst)
        rescue StandardError => e
          raise e.class, "Failed to copy #{src} to #{dst}: #{e.message}", e.backtrace
        end

        # Sanity check: ensure the file actually exists after copy and chmod
        # This guards against rare cases like silent file storage failures or
        # race conditions
        unless File.exist?(dst)
          raise IOError, "Copy operation completed without error, but file '#{dst}' does not exist"
        end

        dst
      end

      def valid?
        valid_result = super
        return false unless valid_result
        sc = self.sanity_check
        return valid_result && sc
      end

      def remote_pulled?
        self.bring(:pullLocation) if self.bring?(:pullLocation)
        self.pullLocation != nil
      end

      def sanity_check
        self.bring(:ontology) if self.bring?(:ontology)
        self.ontology.bring(:summaryOnly) if self.ontology.bring?(:summaryOnly)
        self.bring(:uploadFilePath) if self.bring?(:uploadFilePath)
        self.bring(:pullLocation) if self.bring?(:pullLocation)
        self.bring(:masterFileName) if self.bring?(:masterFileName)
        self.bring(:submissionStatus) if self.bring?(:submissionStatus)

        if self.submissionStatus
          self.submissionStatus.each do |st|
            st.bring(:code) if st.bring?(:code)
          end
        end

        # TODO: this code was added to deal with intermittent issues with 4store, where the error:
        # Attribute `summaryOnly` is not loaded for http://data.bioontology.org/ontologies/GPI
        # was thrown for no apparent reason!!!
        sum_only = nil

        begin
          sum_only = self.ontology.summaryOnly
        rescue Exception => e
          i = 0
          num_calls = LinkedData.settings.num_retries_4store
          sum_only = nil

          while sum_only.nil? && i < num_calls do
            i += 1
            puts "Exception while getting summaryOnly for #{self.id.to_s}. Retrying #{i} times..."
            sleep(1)

            begin
              self.ontology.bring(:summaryOnly)
              sum_only = self.ontology.summaryOnly
              puts "Success getting summaryOnly for #{self.id.to_s} after retrying #{i} times..."
            rescue Exception => e1
              sum_only = nil

              if i == num_calls
                raise $!, "#{$!} after retrying #{i} times...", $!.backtrace
              end
            end
          end
        end

        if sum_only == true || self.archived?
          return true
        elsif self.uploadFilePath.nil? && self.pullLocation.nil?
          self.errors[:uploadFilePath] = ["In non-summary only submissions a data file or url must be provided."]
          return false
        elsif self.pullLocation
          if self.uploadFilePath.nil?
            remote_exists = remote_file_exists?(self.pullLocation.to_s)
            self.errors[:pullLocation] = ["The provided File Pull Location at #{self.pullLocation.to_s} does not point to a valid file."] unless remote_exists
            return remote_exists
          end
          return true
        end

        zip = zipped?
        files = LinkedData::Utils::FileHelpers.filenames_in_archive(uploadFilePath) if zip

        if not zip and self.masterFileName.nil?
          return true
        elsif zip and files.length == 1
          self.masterFileName = files.first
          return true
        elsif zip && self.masterFileName.nil? && LinkedData::Utils::FileHelpers.automaster?(self.uploadFilePath, self.hasOntologyLanguage.file_extension)
          self.masterFileName = LinkedData::Utils::FileHelpers.automaster(self.uploadFilePath, self.hasOntologyLanguage.file_extension)
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
          files =  LinkedData::Utils::FileHelpers.filenames_in_archive(self.uploadFilePath)
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
        bring(:ontology) if bring?(:ontology)
        self.ontology.bring(:acronym) if self.ontology.bring?(:acronym)
        bring(:submissionId) if bring?(:submissionId)
        return File.join(LinkedData.settings.repository_folder,
                         self.ontology.acronym.to_s,
                         self.submissionId.to_s)
      end

      def zipped?(full_file_path = uploadFilePath)
        LinkedData::Utils::FileHelpers.zip?(full_file_path) || LinkedData::Utils::FileHelpers.gzip?(full_file_path)
      end

      def zip_folder
        File.join([data_folder, 'unzipped'])
      end

      def master_file_folder
        zipped? ? zip_folder : data_folder
      end

      def csv_path
        return File.join(self.data_folder, self.ontology.acronym.to_s + ".csv.gz")
      end

      def metrics_path
        return File.join(self.data_folder, "metrics.csv")
      end

      def rdf_path
        return File.join(self.data_folder, "owlapi.xrdf")
      end

      def parsing_log_path
        return File.join(self.data_folder, 'parsing.log')
      end

      def triples_file_path
        self.bring(:uploadFilePath) if self.bring?(:uploadFilePath)
        self.bring(:masterFileName) if self.bring?(:masterFileName)
        triples_file_name = File.basename(self.uploadFilePath.to_s)
        full_file_path = File.join(File.expand_path(self.data_folder.to_s), triples_file_name)
        zip = zipped? full_file_path
        triples_file_name = File.basename(self.masterFileName.to_s) if zip && self.masterFileName
        file_name = File.join(File.expand_path(self.data_folder.to_s), triples_file_name)
        File.expand_path(file_name)
      end

      def unzip_submission(logger)
        zip_dst = nil

        if zipped?
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

          if logger
            logger.info("Files extracted from zip #{extracted}")
            logger.flush
          end
        end
        zip_dst
      end

      def class_count(logger=nil)
        logger ||= LinkedData::Parser.logger || Logger.new($stderr)
        count = -1
        count_set = false
        self.bring(:metrics) if self.bring?(:metrics)

        begin
          mx = self.metrics
        rescue Exception => e
          logger.error("Unable to retrieve metrics in class_count for #{self.id.to_s} - #{e.class}: #{e.message}")
          logger.flush
          mx = nil
        end

        self.bring(:hasOntologyLanguage) unless self.loaded_attributes.include?(:hasOntologyLanguage)

        if mx
          mx.bring(:classes) if mx.bring?(:classes)
          count = mx.classes

          if self.hasOntologyLanguage.skos?
            mx.bring(:individuals) if mx.bring?(:individuals)
            count += mx.individuals
          end
          count_set = true
        else
          mx = metrics_from_file(logger)

          unless mx.empty?
            count = mx[1][0].to_i

            if self.hasOntologyLanguage.skos?
              count += mx[1][1].to_i
            end
            count_set = true
          end
        end

        unless count_set
          logger.error("No calculated metrics or metrics file was found for #{self.id.to_s}. Unable to return total class count.")
          logger.flush
        end
        count
      end

      def metrics_from_file(logger=nil)
        logger ||= LinkedData::Parser.logger || Logger.new($stderr)
        metrics = []
        m_path = self.metrics_path

        begin
          metrics = CSV.read(m_path)
        rescue Exception => e
          logger.error("Unable to find metrics file: #{m_path}")
          logger.flush
        end
        metrics
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
          s.reject! { |stat| stat.get_code_from_id() == non_error_status.get_code_from_id() } unless non_error_status.nil?
        else
          # remove the corresponding non_error status (if exists)
          error_status = status.get_error_status()
          s.reject! { |stat| stat.get_code_from_id() == error_status.get_code_from_id() } unless error_status.nil?
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
        self.bring(:submissionStatus) if self.bring?(:submissionStatus)
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

      # Override delete to add removal from the search index
      #TODO: revise this with a better process
      def delete(*args)
        options = {}
        args.each {|e| options.merge!(e) if e.is_a?(Hash)}
        remove_index = options[:remove_index] ? true : false
        index_commit = options[:index_commit] == false ? false : true

        super(*args)
        self.ontology.unindex(index_commit)
        self.ontology.unindex_properties(index_commit)

        self.bring(:metrics) if self.bring?(:metrics)
        self.metrics.delete if self.metrics

        if remove_index
          # need to re-index the previous submission (if exists)
          self.ontology.bring(:submissions)

          if self.ontology.submissions.length > 0
            prev_sub = self.ontology.latest_submission

            if prev_sub
              prev_sub.index(LinkedData::Parser.logger || Logger.new($stderr))
              prev_sub.index_properties(LinkedData::Parser.logger || Logger.new($stderr))
            end
          end
        end

        # delete the folder and files
        FileUtils.remove_dir(self.data_folder) if Dir.exist?(self.data_folder)
      end

      def roots(extra_include = [], page = nil, pagesize = nil, concept_schemes: [], concept_collections: [])
        self.bring(:ontology) unless self.loaded_attributes.include?(:ontology)
        self.bring(:hasOntologyLanguage) unless self.loaded_attributes.include?(:hasOntologyLanguage)
        paged = false
        fake_paged = false

        if page || pagesize
          page ||= 1
          pagesize ||= 50
          paged = true
        end

        skos = self.skos?
        classes = []

        if skos
          classes = skos_roots(concept_schemes, page, paged, pagesize)
          extra_include += LinkedData::Models::Class.concept_is_in_attributes
        else
          self.ontology.bring(:flat)
          data_query = nil

          if self.ontology.flat
            data_query = LinkedData::Models::Class.in(self)

            unless paged
              page = 1
              pagesize = FLAT_ROOTS_LIMIT
              paged = true
              fake_paged = true
            end
          else
            owl_thing = Goo.vocabulary(:owl)["Thing"]
            data_query = LinkedData::Models::Class.where(parents: owl_thing).in(self)
          end

          if paged
            page_data_query = data_query.page(page, pagesize)
            classes = page_data_query.page(page, pagesize).disable_rules.all
            # simulate unpaged query for flat ontologies
            # we use paging just to cap the return size
            classes = classes.to_a if fake_paged
          else
            classes = data_query.disable_rules.all
          end
        end

        where = LinkedData::Models::Class.in(self).models(classes).include(:prefLabel, :definition, :synonym, :obsolete)

        if extra_include
          %i[prefLabel definition synonym obsolete childrenCount].each do |x|
            extra_include.delete x
          end
        end

        load_children = []

        if extra_include
          load_children = extra_include.delete :children

          if load_children.nil?
            load_children = extra_include.select { |x| x.instance_of?(Hash) && x.include?(:children) }

            if load_children.length > 0
              extra_include = extra_include.select { |x| !(x.instance_of?(Hash) && x.include?(:children)) }
            end
          else
            load_children = [:children]
          end

          where.include(extra_include) if extra_include.length > 0
        end
        where.all

        LinkedData::Models::Class.partially_load_children(classes, 99, self) if load_children.length > 0

        classes.delete_if { |c|
          obs = !c.obsolete.nil? && c.obsolete == true
          if !obs
            c.load_computed_attributes(to_load: extra_include,
                                       options: { schemes: current_schemes(concept_schemes), collections: concept_collections })
          end
          obs
        }
        classes
      end

      def children(cls, includes_param: [], concept_schemes: [], concept_collections: [], page: 1, size: 50)
        ld = LinkedData::Models::Class.goo_attrs_to_load(includes_param)
        unmapped = ld.delete(:properties)

        ld += LinkedData::Models::Class.concept_is_in_attributes if skos?

        page_data_query = LinkedData::Models::Class.where(parents: cls).in(self).include(ld)
        aggregates = LinkedData::Models::Class.goo_aggregates_to_load(ld)
        page_data_query.aggregate(*aggregates) unless aggregates.empty?
        page_data = page_data_query.page(page, size).all
        LinkedData::Models::Class.in(self).models(page_data).include(:unmapped).all if unmapped

        page_data.delete_if { |x| x.id.to_s == cls.id.to_s }
        if ld.include?(:hasChildren) || ld.include?(:isInActiveScheme) || ld.include?(:isInActiveCollection)
          page_data.each do |c|
            c.load_computed_attributes(to_load: ld,
                                       options: { schemes: concept_schemes, collections: concept_collections })
          end
        end

        unless concept_schemes.empty?
          page_data.delete_if { |c| Array(c.isInActiveScheme).empty? && !c.load_has_children }
          if (page_data.size < size) && page_data.next_page
            page_data += children(cls, includes_param: includes_param, concept_schemes: concept_schemes,
                                  concept_collections: concept_collections,
                                  page: page_data.next_page, size: size)
          end
        end

        page_data
      end

      def skos?
        self.bring :hasOntologyLanguage if bring? :hasOntologyLanguage
        self.hasOntologyLanguage&.skos?
      end

      def ontology_uri
        self.bring(:uri) if self.bring? :uri
        RDF::URI.new(self.uri)
      end













      def roots_sorted(extra_include=nil)
        classes = roots(extra_include)
        LinkedData::Models::Class.sort_classes(classes)
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


      def master_file_path
        path = if zipped?
                 File.join(self.zip_folder, self.masterFileName)
               else
                 self.uploadFilePath
               end
        File.expand_path(path)
      end


      def owlapi_parser(logger: Logger.new($stdout))
        unzip_submission(logger)
        LinkedData::Parser::OWLAPICommand.new(
          owlapi_parser_input,
          File.expand_path(self.data_folder.to_s),
          master_file: self.masterFileName,
          logger: logger)
      end

      def parsable?(logger: Logger.new($stdout))
        owlapi = owlapi_parser(logger: logger)
        owlapi.disable_reasoner
        parsable = true
        begin
          owlapi.parse
        rescue StandardError => e
          parsable = false
        end
        parsable
      end

      def owlapi_parser(logger: Logger.new($stdout))
        unzip_submission(logger)
        LinkedData::Parser::OWLAPICommand.new(
          owlapi_parser_input,
          File.expand_path(self.data_folder.to_s),
          master_file: self.masterFileName,
          logger: logger)
      end

      private

      def owlapi_parser_input
        path = if zipped?
                 self.zip_folder
               else
                 self.uploadFilePath
               end
        File.expand_path(path)
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

      def self.loom_transform_literal(lit)
        res = []
        lit.each_char do |c|
          if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
            res << c.downcase
          end
        end
        return res.join ''
      end

    end
  end
end
