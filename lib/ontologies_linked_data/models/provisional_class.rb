module LinkedData
  module Models
    class ProvisionalClass < LinkedData::Models::Base
      model :provisional_class, name_with: lambda { |inst| uuid_uri_generator(inst) }

      PC_ID_PREFIX = "/provisional_classes/"

      attribute :label, enforce: [:existence]
      attribute :synonym, enforce: [:list]
      attribute :definition, enforce: [:list]
      attribute :subclassOf, enforce: [:uri]
      attribute :creator, enforce: [:existence, :user]
      attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
      attribute :permanentId, enforce: [:uri]
      attribute :noteId, enforce: [:uri]
      attribute :ontology, enforce: [:ontology]

      attribute :relations,
                :inverse => { :on => :provisional_relation, :attribute => :source }

      embed :relations

      system_controlled :creator, :created

      # display relations and some search attributes by default
      serialize_default *(self.attributes.unshift(:prefLabel) << :relations << :obsolete << :matchType << :ontologyType << :provisional)

      link_to LinkedData::Hypermedia::Link.new("self", lambda {|s| "provisional_classes/#{CGI.escape(s.id.to_s)}"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("ontology", lambda {|s|
                begin
                  if defined?(s.ontology) && s.ontology
                    "ontologies/#{s.ontology.id.split('/')[-1]}"
                  elsif defined?(s.submission) && s.submission
                    "ontologies/#{s.submission.ontology.id.split('/')[-1]}"
                  else
                    ""
                  end
                rescue Exception => e
                  ""
                end
              }, Goo.vocabulary["Ontology"])

      def index_id()
        self.bring(:ontology) if self.bring?(:ontology)
        return nil unless self.ontology
        latest = self.ontology.latest_submission(status: :any)
        return nil unless latest
        "#{self.id.to_s}_#{self.ontology.acronym}_#{latest.submissionId}"
      end

      def index_doc(to_set=nil)
        return {} unless self.ontology
        latest = self.ontology.latest_submission(status: :any)
        return {} unless latest
        path_ids = Set.new
        self.ontology.bring(:acronym) if self.ontology.bring?(:acronym)
        self.ontology.bring(:ontologyType) if self.ontology.bring?(:ontologyType)

        begin
          paths_to_root = self.paths_to_root
          paths_to_root.each do |paths|
            path_ids += paths.map { |p| p.id.to_s }
          end
          path_ids.delete(self.id.to_s)
        rescue Exception => e
          path_ids = Set.new
          puts "Exception getting paths to root for search for provisional class #{self.id.to_s}: #{e.class}: #{e.message}"
        end

        doc = {
          :prefLabel => self.label,
          :obsolete => false,
          :provisional => true,
          :ontologyId => latest.id.to_s,
          :submissionAcronym => self.ontology.acronym,
          :submissionId => latest.submissionId,
          :ontologyType => self.ontology.ontologyType.get_code_from_id,
          :parents => path_ids
        }

        all_attrs = self.to_hash
        std = [:id, :synonym, :definition]

        std.each do |att|
          cur_val = all_attrs[att]
          # don't store empty values
          next if cur_val.nil? || cur_val.empty?

          if cur_val.is_a?(Array)
            doc[att] = []
            cur_val = cur_val.uniq
            cur_val.map { |val| doc[att] << (val.kind_of?(Goo::Base::Resource) ? val.id.to_s : val.to_s.strip) }
          else
            doc[att] = cur_val.to_s.strip
          end
        end

        doc
      end

      def paths_to_root()
        paths = [[]]
        traverse_path_to_root(self, paths)
        paths.each { |p| p.reverse! }
        paths
      end

      def traverse_path_to_root(r, paths)
        rv = append_if_not_there_already(paths[0], r)
        return unless rv
        r.bring(:subclassOf) if r.bring?(:subclassOf)
        return if r.subclassOf.nil?

        if provisional_id?(r.subclassOf)
          parent = LinkedData::Models::ProvisionalClass.find(r.subclassOf).include(:label).first
          return if parent.nil?
          traverse_path_to_root(parent, paths)
        else
          # see if it's a real class
          r.bring(:ontology) if r.bring?(:ontology)
          return if r.ontology.nil?
          os = r.ontology.latest_submission
          return if os.nil?
          cls = LinkedData::Models::Class.find(r.subclassOf).in(os).include(:parents).include(:children).to_a[0]
          return if cls.nil?
          paths_to_root = cls.paths_to_root
          # add self to the beginning of each path
          paths_to_root.each { |p| p.unshift(r) }
          paths.concat(paths_to_root)
        end
      end

      def provisional_id?(id)
        return false if id.nil?
        id.to_s.include?(self.class::PC_ID_PREFIX)
      end

      def append_if_not_there_already(path, r)
        return false if r.nil?
        return false if r.id.to_s["#Thing"]
        return false if (path.select { |x| x.id.to_s == r.id.to_s }).length > 0
        path << r
        true
      end

      def index()
        if index_id
          unindex
          super
          LinkedData::Models::Ontology.indexCommit
        end
      end

      def unindex()
        ind_id = index_id

        if ind_id
          query = "id:#{solr_escape(ind_id)}"
          LinkedData::Models::Ontology.unindexByQuery(query)
          LinkedData::Models::Ontology.indexCommit
        end
      end

      ##
      # Override save to allow indexing
      def save(*args)
        super(*args)
        index
        self
      end

      def delete(*args)
        # remove index entries
        unindex
        super(*args)
      end

      def solr_escape(text)
        RSolr.solr_escape(text).gsub(/\s+/,"\\ ")
      end

      def self.children(source_uri)
        source_uri = RDF::URI.new(source_uri) unless source_uri.is_a?(RDF::URI)
        LinkedData::Models::ProvisionalClass.where(subclassOf: source_uri).include(LinkedData::Models::ProvisionalClass.attributes).all
      end

    end
  end
end
