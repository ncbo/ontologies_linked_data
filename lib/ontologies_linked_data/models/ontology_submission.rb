module LinkedData
  module Models
    class OntologySubmission < LinkedData::Models::Base
      model :ontology_submission
      attribute :acronym, :unique => true
      attribute :submissionId, :unique => true, :instance_of =>  { :with => Fixnum }
      attribute :name, :cardinality => { :max => 1, :min => 1 }

      #configurable properties
      attribute :prefLabelProperty, :instance_of =>  { :with => RDF::IRI }, :single_value => true
      attribute :definitionProperty, :instance_of =>  { :with => RDF::IRI }, :single_value  => true
      attribute :synonymProperty, :instance_of =>  { :with => RDF::IRI }, :single_value  => true
      attribute :authorProperty, :instance_of =>  { :with => RDF::IRI }, :single_value  => true
      attribute :classType, :instance_of =>  { :with => RDF::IRI }, :single_value  => true
      attribute :hiearchyProperty, :instance_of =>  { :with => RDF::IRI }, :single_value  => true
      attribute :status, :instance_of =>  { :with => :submission_status }, :single_value  => true, :not_nil => true
      attribute :summaryOnly, :single_value  => true

      #internal values for parsing - not definitive
      attribute :uploadFilePath,  :single_value =>true
      attribute :masterFileName,  :single_value =>true


      #link to ontology
      attribute :ontology, :single_value => true, :not_nil => true, :instance_of => { :with => :ontology }

      attribute :ontologyFormat, :single_value => true, :not_nil => true, :instance_of => { :with => :ontology_format }
      attribute :administeredBy, :not_nil => true, :instance_of => { :with => :user }

      def self.copy_file_repository(acronym, submissionId, src, filename = nil)
        path_to_repo = File.join([$REPOSITORY_FOLDER, acronym, submissionId.to_s])
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
        sc = self.sanity_check
        return valid_result && sc 
      end

      def filename
      end

      def sanity_check
        if self.summaryOnly
          return true
        elsif self.uploadFilePath.nil?
            self.errors[:uploadFilePath] = ["In non-summary only submissions a data file must be provided."]
            return false
        end

        zip = LinkedData::Utils::FileHelpers.zip?(self.uploadFilePath) 
        if not zip and self.masterFileName.nil?
          return true

        elsif zip and self.masterFileName.nil?
          #zip and masterFileName not set. The user has to choose.
          if self.errors[:uploadFilePath].nil?
            self.errors[:uploadFilePath] = []
          end
          files =  LinkedData::Utils::FileHelpers.files_from_zip(self.uploadFilePath)
          
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
                :message => "The selected file `#{self.materFileName}` is not included in the zip file", 
                :options => files }
            end
          end
        end
        return true
      end 

      def data_folder
        return File.join($REPOSITORY_FOLDER, self.ontology.acronym, self.submissionId.to_s)
      end

      def zip_folder
        return File.join([self.data_folder, "unzipped"])
      end

      def process_submission(logger)
        if not self.valid?
          raise ArgumentError, "Submission is not valid, it cannot be processed. Check errors"
        end
        if not self.loaded?
          self.load
          if not self.ontology.loaded?
            self.ontology.load
          end
        end
        zip = LinkedData::Utils::FileHelpers.zip?(self.uploadFilePath)
        zip_dst = nil
        if zip
          zip_dst = self.zip_folder
          if Dir.exist? zip_dst
            FileUtils.rm_r [zip_dst]
          end
          FileUtils.mkdir_p zip_dst
          extracted = LinkedData::Utils::FileHelpers.unzip(self.uploadFilePath, zip_dst)
          logger.info("Files extracted from zip #{extracted}")
        end 
        LinkedData::Parser.logger =  logger
        input_data = zip_dst ||  self.uploadFilePath
        owlapi = LinkedData::Parser::OWLAPICommand.new(input_data,self.data_folder,self.masterFileName)
        triples_file_path = owlapi.parse

        Goo.store.delete_graph(self.resource_id.value)
        Goo.store.append_in_graph(File.read(triples_file_path),self.resource_id.value)
        rdf_status = SubmissionStatus.find("RDF")
        self.status = rdf_status
        self.save

        missing_labels_generation logger
      end

      def missing_labels_generation(logger)  
        property_triples = LinkedData::Utils::Triples.rdf_for_custom_properties(self)
        Goo.store.append_in_graph(property_triples, self.resource_id.value, SparqlRd::Utils::MimeType.turtle)
        count_classes = 0
        self.classes.each do |c|
          if c.prefLabel.nil?
            rdfs_labels = c.rdfs_labels
            label = nil
            if rdfs_labels.length > 0
              label = rdfs_labels[0] 
            else
              label = LinkedData::Utils::Namespaces.last_iri_fragment c.id.value
            end
            label_triples = LinkedData::Utils::Triples.label_for_class_triple(c.id,
                                                   LinkedData::Utils::Namespaces.meta_prefLabel_iri,label)
            Goo.store.append_in_graph(label_triples, self.resource_id.value, SparqlRd::Utils::MimeType.turtle)
          end
          count_classes += 1
        end
        logger.info("#{count_classes} classes in ontology")
      end

      def classes
        return Class.where(:graph => self.resource_id, 
                           :prefLabelProperty => self.prefLabelProperty,
                           :classType => self.classType)
      end
    end
  end
end
