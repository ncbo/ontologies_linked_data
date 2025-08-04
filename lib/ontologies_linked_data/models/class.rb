require "set"
require "cgi"
require "multi_json"
require "ontologies_linked_data/models/notes/note"
require "ontologies_linked_data/mappings/mappings"

module LinkedData
  module Models
    class ClassAttributeNotLoaded < StandardError
    end

    class Class < LinkedData::Models::Base
      include LinkedData::Concerns::Concept::Sort
      include LinkedData::Concerns::Concept::Tree
      include LinkedData::Concerns::Concept::InScheme
      include LinkedData::Concerns::Concept::InCollection

      model :class, name_with: :id, collection: :submission,
            namespace: :owl, :schemaless => :true,
            rdf_type: lambda { |*x| self.class_rdf_type(x) }

      def self.class_rdf_type(*args)
        submission = args.flatten.first
        return RDF::OWL[:Class] if submission.nil?
        if submission.bring?(:classType)
          submission.bring(:classType)
        end
        if not submission.classType.nil?
          return submission.classType
        end
        unless submission.loaded_attributes.include?(:hasOntologyLanguage)
          submission.bring(:hasOntologyLanguage)
        end
        if submission.hasOntologyLanguage
          return submission.hasOntologyLanguage.class_type
        end
        return RDF::OWL[:Class]
      end

      def self.urn_id(acronym,classId)
        return "urn:#{acronym}:#{classId.to_s}"
      end

      attribute :submission, :collection => lambda { |s| s.resource_id }, :namespace => :metadata

      attribute :label, namespace: :rdfs, enforce: [:list]
      attribute :prefLabel, namespace: :skos, enforce: [:existence], alias: true
      attribute :prefLabelXl, property: :prefLabel, namespace: :skosxl, enforce: [:label, :list], alias: true
      attribute :altLabelXl, property: :altLabel, namespace: :skosxl, enforce: [:label, :list], alias: true
      attribute :hiddenLabelXl, property: :hiddenLabel, namespace: :skosxl, enforce: [:label, :list], alias: true
      attribute :synonym, namespace: :skos, enforce: [:list], property: :altLabel, alias: true
      attribute :definition, namespace: :skos, enforce: [:list], alias: true
      attribute :obsolete, namespace: :owl, property: :deprecated, alias: true

      attribute :notation, namespace: :skos
      attribute :prefixIRI, namespace: :metadata

      attribute :parents, namespace: :rdfs,
                  property: lambda {|x| self.tree_view_property(x) },
                enforce: [:list, :class]

      #transitive parent
      attribute :ancestors, namespace: :rdfs,
                property: :subClassOf,
                enforce: [:list, :class],
                transitive: true

      attribute :children, namespace: :rdfs,
                  property: lambda {|x| self.tree_view_property(x) },
                  inverse: { on: :class , :attribute => :parents }

      attribute :subClassOf, namespace: :rdfs,
                enforce: [:list, :uri]

      attribute :ancestors, namespace: :rdfs, property: :subClassOf, handler: :retrieve_ancestors

      attribute :descendants, namespace: :rdfs, property: :subClassOf,
                handler: :retrieve_descendants

      attribute :semanticType, enforce: [:list], :namespace => :umls, :property => :hasSTY
      attribute :cui, enforce: [:list], :namespace => :umls, alias: true
      attribute :xref, :namespace => :oboinowl_gen, alias: true,
                :property => :hasDbXref

      attribute :notes,
                inverse: { on: :note, attribute: :relatedClass }
      attribute :inScheme, enforce: [:list, :uri], namespace: :skos
      attribute :memberOf, namespace: :uneskos, inverse: { on: :collection , :attribute => :member }
      attribute :created, namespace:  :dcterms
      attribute :modified, namespace:  :dcterms

      # Hypermedia settings
      embed :children, :ancestors, :descendants, :parents, :prefLabelXl, :altLabelXl, :hiddenLabelXl
      serialize_default :prefLabel, :synonym, :definition, :cui, :semanticType, :obsolete, :matchType,
                        :ontologyType, :provisional, # an attribute used in Search (not shown out of context)
                        :created, :modified, :memberOf, :inScheme
      serialize_methods :properties, :childrenCount, :hasChildren
      serialize_never :submissionAcronym, :submissionId, :submission, :descendants
      aggregates childrenCount: [:count, :children]
      links_load submission: [ontology: [:acronym]]
      do_not_load :descendants, :ancestors
      prevent_serialize_when_nested :properties, :parents, :children, :ancestors, :descendants, :memberOf
      link_to LinkedData::Hypermedia::Link.new("self", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("ontology", lambda {|s| "ontologies/#{s.submission.ontology.acronym}"}, Goo.vocabulary["Ontology"]),
              LinkedData::Hypermedia::Link.new("children", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/children"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("parents", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/parents"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("descendants", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/descendants"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("ancestors", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/ancestors"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("instances", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/instances"}, Goo.vocabulary["Instance"]),
              LinkedData::Hypermedia::Link.new("tree", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/tree"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("notes", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/notes"}, LinkedData::Models::Note.type_uri),
              LinkedData::Hypermedia::Link.new("mappings", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/mappings"}, Goo.vocabulary["Mapping"]),
              LinkedData::Hypermedia::Link.new("ui", lambda {|s| "http://#{LinkedData.settings.ui_host}/ontologies/#{s.submission.ontology.acronym}?p=classes&conceptid=#{CGI.escape(s.id.to_s)}"}, self.uri_type)

      # HTTP Cache settings
      cache_timeout 86400
      cache_segment_instance lambda {|cls| segment_instance(cls) }
      cache_segment_keys [:class]
      cache_load submission: [ontology: [:acronym]]

      def self.tree_view_property(*args)
        submission = args.first
        unless submission.loaded_attributes.include?(:hasOntologyLanguage)
          submission.bring(:hasOntologyLanguage)
        end
        if submission.hasOntologyLanguage
          return submission.hasOntologyLanguage.tree_property
        end
        return RDF::RDFS[:subClassOf]
      end

      def self.segment_instance(cls)
        cls.submission.ontology.bring(:acronym) unless cls.submission.ontology.loaded_attributes.include?(:acronym)
        [cls.submission.ontology.acronym] rescue []
      end

      def obsolete
        @obsolete || false
      end

      def index_id()
        self.bring(:submission) if self.bring?(:submission)
        return nil unless self.submission
        self.submission.bring(:submissionId) if self.submission.bring?(:submissionId)
        self.submission.bring(:ontology) if self.submission.bring?(:ontology)
        return nil unless self.submission.ontology
        self.submission.ontology.bring(:acronym) if self.submission.ontology.bring?(:acronym)
        "#{self.id.to_s}_#{self.submission.ontology.acronym}_#{self.submission.submissionId}"
      end

      def to_hash(include_languages: false)
        attr_hash = {}
        self.class.attributes.each do |attr|
          v = self.instance_variable_get("@#{attr}")
          attr_hash[attr] = v unless v.nil?
        end
        properties_values = properties(include_languages: include_languages)
        if properties_values
          all_attr_uris = Set.new
          self.class.attributes.each do |attr|
            if self.class.collection_opts
              all_attr_uris << self.class.attribute_uri(attr, self.collection)
            else
              all_attr_uris << self.class.attribute_uri(attr)
            end
          end
          properties_values.each do |attr, values|
            values = values.values.flatten if values.is_a?(Hash)
            attr_hash[attr] = values.map { |v| v.to_s } unless all_attr_uris.include?(attr)
          end
        end
        attr_hash[:id] = @id
        attr_hash
      end

      # to_set is an optional array that allows passing specific
      # field names that require updating
      # if to_set is nil, it's assumed to be a new document for insert
      def index_doc(to_set=nil)
        doc = {}
        path_ids = Set.new
        self.bring(:submission) if self.bring?(:submission)
        class_id = self.id.to_s

        if to_set.nil?
          begin
            doc[:childCount] = self.childrenCount
          rescue ArgumentError
            LinkedData::Models::Class.in(self.submission).models([self]).aggregate(:count, :children).all
            doc[:childCount] = self.childrenCount
          rescue Exception => e
            doc[:childCount] = 0
            puts "Exception getting childCount for search for #{class_id}: #{e.class}: #{e.message}"
          end

          begin
            # paths_to_root = self.paths_to_root
            # paths_to_root.each do |paths|
            #   path_ids += paths.map { |p| p.id.to_s }
            # end
            # path_ids.delete(class_id)
            path_ids = retrieve_hierarchy_ids(:ancestors)
            path_ids.select! { |x| !x["owl#Thing"] }
            doc[:parents] = path_ids
          rescue Exception => e
            doc[:parents] = Set.new
            puts "Exception getting paths to root for search for #{class_id}: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
          end

          acronym = self.submission.ontology.acronym

          doc[:ontologyId] = self.submission.id.to_s
          doc[:submissionAcronym] = self.submission.ontology.acronym
          doc[:submissionId] = self.submission.submissionId
          doc[:ontologyType] = self.submission.ontology.ontologyType.get_code_from_id
          doc[:obsolete] = self.obsolete.to_s

          all_attrs = self.to_hash
          std = [:id, :prefLabel, :notation, :synonym, :definition, :cui]
          multi_language_fields = [:prefLabel, :synonym, :definition]
          std.each do |att|
            cur_val = all_attrs[att]

            # don't store empty values
            next if cur_val.nil? || (cur_val.respond_to?('empty?') && cur_val.empty?)

            if cur_val.is_a?(Hash) # Multi language
              if multi_language_fields.include?(att)
                doc[att] = cur_val.values.flatten # index all values of each language
                cur_val.each { |lang, values| doc["#{att}_#{lang}".to_sym] = values } # index values per language
              else
                doc[att] = cur_val.values.flatten.first
              end
            end

            if cur_val.is_a?(Array)
              # don't store empty values
              cur_val = cur_val.reject { |c| c.respond_to?('empty?') && c.empty? }
              doc[att] = []
              cur_val = cur_val.uniq
              cur_val.map { |val| doc[att] << (val.kind_of?(Goo::Base::Resource) ? val.id.to_s : val.to_s.strip) }
            elsif doc[att].nil?
              doc[att] = cur_val.to_s.strip
            end
          end

          # special handling for :semanticType (AKA tui)
          if all_attrs[:semanticType] && !all_attrs[:semanticType].empty?
            doc[:semanticType] = []
            all_attrs[:semanticType].each { |semType| doc[:semanticType] << semType.split("/").last }
          end

          # mdorf, 2/4/2024: special handling for :notation field because some ontologies have it defined as :prefixIRI
          if !doc[:notation] || doc[:notation].empty?
            if all_attrs[:prefixIRI] && !all_attrs[:prefixIRI].empty?
              doc[:notation] = all_attrs[:prefixIRI].values.flatten.first.strip
            else
              doc[:notation] = LinkedData::Utils::Triples::last_iri_fragment(doc[:id])
            end
          end
          doc[:idAcronymMatch] = true if notation_acronym_match(doc[:notation], acronym)
          # https://github.com/bmir-radx/radx-project/issues/46
          # https://github.com/bmir-radx/radx-project/issues/46#issuecomment-1939782535
          # https://github.com/bmir-radx/radx-project/issues/46#issuecomment-1939932614
          set_oboid_fields(class_id, self.submission.uri, acronym, doc)
        end

        if to_set.nil? || (to_set.is_a?(Array) && to_set.include?(:properties))
          props = self.properties_for_indexing

          unless props.nil?
            doc[:property] = props[:property]
            doc[:propertyRaw] = props[:propertyRaw]
          end
        end
        doc
      end

      def set_oboid_fields(class_id, ontology_iri, ontology_acronym, index_doc)
        short_id = LinkedData::Utils::Triples.last_iri_fragment(class_id)
        matched = short_id.match(/([A-Za-z]+)_([0-9]+)$/) do |m|
          index_doc[:oboId] = "#{m[1]}:#{m[2]}"
          index_doc[:idAcronymMatch] = true if m[1].upcase === ontology_acronym.upcase
          true
        end

        if !matched && ontology_iri && class_id.start_with?(ontology_iri)
          index_doc[:oboId] = "#{ontology_acronym}:#{short_id}"
          index_doc[:idAcronymMatch] = true
        end
      end

      def notation_acronym_match(notation, ontology_acronym)
        notation.match(/^([A-Za-z]+)[_:]{1}/) do |m|
          return m[1].upcase === ontology_acronym.upcase
        end
        false
      end

      def properties_for_indexing()
        self_props = self.properties
        return nil if self_props.nil?

        ret_val = nil
        props = {}
        prop_vals = []

        self_props.each do |attr_key, attr_val|
          # unless doc.include?(attr_key)
          if attr_val.is_a?(Array)
            props[attr_key] = []
            attr_val = attr_val.uniq

            attr_val.map { |val|
              real_val = val.kind_of?(Goo::Base::Resource) ? val.id.to_s : val.to_s.strip

              # don't store empty values
              unless real_val.respond_to?('empty?') && real_val.empty?
                prop_vals << real_val
                props[attr_key] << real_val
              end
            }
          else
            real_val = attr_val.to_s.strip

            # don't store empty values
            unless real_val.respond_to?('empty?') && real_val.empty?
              prop_vals << real_val
              props[attr_key] = real_val
            end
          end
          # end
        end

        begin
          ret_val = {}
          ret_val[:propertyRaw] = MultiJson.dump(props)
          prop_vals.uniq!
          ret_val[:property] = prop_vals
        rescue JSON::GeneratorError => e
          ret_val = nil
          # need to ignore non-UTF-8 characters in properties of classes (this is a rare issue)
          puts "#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}"
        end
        ret_val
      end

      def childrenCount()
        self.bring(:submission) if self.bring?(:submission)
        raise ArgumentError, "No aggregates included in #{self.id.to_ntriples}. Submission: #{self.submission.id.to_s}" unless self.aggregates
        cc = self.aggregates.select { |x| x.attribute == :children && x.aggregate == :count}.first
        raise ArgumentError, "No aggregate for attribute children and count found in #{self.id.to_ntriples}" if !cc
        cc.value
      end

      BAD_PROPERTY_URIS = LinkedData::Mappings.mapping_predicates.values.flatten + ['http://bioportal.bioontology.org/metadata/def/prefLabel']
      EXCEPTION_URIS = ["http://bioportal.bioontology.org/ontologies/umls/cui"]
      BLACKLIST_URIS = BAD_PROPERTY_URIS - EXCEPTION_URIS
      def properties(*args)
        return nil if self.unmapped(*args).nil?
        properties = self.unmapped(*args)
        BLACKLIST_URIS.each {|bad_iri| properties.delete(RDF::URI.new(bad_iri))}
        properties
      end

      def self.partially_load_children(models, threshold, submission)
        ld = [:prefLabel, :definition, :synonym]
        ld << :subClassOf if submission.hasOntologyLanguage.obo?
        ld += LinkedData::Models::Class.concept_is_in_attributes if submission.skos?

        single_load = []
        query = self.in(submission).models(models)
        query.aggregate(:count, :children).all

        models.each do |cls|
          if cls.aggregates.nil?
            next
          end
          if cls.aggregates.first.value > threshold
            #too many load a page
            page_children = LinkedData::Models::Class
                              .where(parents: cls)
                              .include(ld)
                              .in(submission).page(1,threshold).all

            cls.instance_variable_set("@children",page_children.to_a)
            cls.loaded_attributes.add(:children)
          else
            single_load << cls
          end
        end

        self.in(submission).models(single_load).include({children: ld}).all if single_load.length > 0
      end

      def load_computed_attributes(to_load:, options:)
        self.load_has_children if to_load&.include?(:hasChildren)
        self.load_is_in_scheme(options[:schemes]) if to_load&.include?(:isInActiveScheme)
        self.load_is_in_collection(options[:collections]) if to_load&.include?(:isInActiveCollection)
      end

      def self.concept_is_in_attributes
        [:inScheme, :isInActiveScheme, :memberOf, :isInActiveCollection]
      end

      def retrieve_ancestors()
        ids = retrieve_hierarchy_ids(:ancestors)
        if ids.length == 0
          return []
        end
        ids.select { |x| !x["owl#Thing"] }
        ids.map! { |x| RDF::URI.new(x) }
        return LinkedData::Models::Class.in(self.submission).ids(ids).all
      end

      def retrieve_descendants(page=nil, size=nil)
        ids = retrieve_hierarchy_ids(:descendants)
        if ids.length == 0
          return []
        end
        ids.select { |x| !x["owl#Thing"] }
        total_size = ids.length
        if !page.nil?
          ids = ids.to_a.sort
          rstart = (page -1) * size
          rend = (page * size) -1
          ids = ids[rstart..rend]
        end
        ids.map! { |x| RDF::URI.new(x) }
        models = LinkedData::Models::Class.in(self.submission).ids(ids).all
        if !page.nil?
          return Goo::Base::Page.new(page,size,total_size,models)
        end
        return models
      end

      def hasChildren()
        if instance_variable_get("@intlHasChildren").nil?
          raise ArgumentError, "HasChildren not loaded for #{self.id.to_ntriples}"
        end
        return @intlHasChildren
     end

      def load_has_children()
        if !instance_variable_get("@intlHasChildren").nil?
          return
        end
        graphs = [self.submission.id.to_s]
        query = has_children_query(self.id.to_s,graphs.first)
        has_c = false
        Goo.sparql_query_client.query(query,
                      query_options: {rules: :NONE }, graphs: graphs)
           .each do |sol|
          has_c = true
        end
        @intlHasChildren = has_c
      end

      def retrieve_hierarchy_ids(direction=:ancestors)
        current_level = 1
        max_levels = 40
        level_ids = Set.new([self.id.to_s])
        all_ids = Set.new()
        graphs = [self.submission.id.to_s]
        submission_id_string = self.submission.id.to_s
        while current_level <= max_levels do
          next_level = Set.new
          slices = level_ids.to_a.sort.each_slice(750).to_a
          threads = []
          slices.each_index do |i|
            ids_slice = slices[i]
            threads[i] = Thread.new {
              next_level_thread = Set.new
              query = hierarchy_query(direction,ids_slice)
              Goo.sparql_query_client.query(query,query_options: {rules: :NONE }, graphs: graphs)
                 .each do |sol|
                parent = sol[:node].to_s
                next if !parent.start_with?("http")
                ontology = sol[:graph].to_s
                if submission_id_string == ontology
                  unless all_ids.include?(parent)
                    next_level_thread << parent
                  end
                end
              end
              Thread.current["next_level_thread"] = next_level_thread
            }
          end
          threads.each {|t| t.join ; next_level.merge(t["next_level_thread"]) }
          current_level += 1
          pre_size = all_ids.length
          all_ids.merge(next_level)
          if all_ids.length == pre_size
            #nothing new
            return all_ids
          end
          level_ids = next_level
        end
        return all_ids
      end

      private

      def has_children_query(class_id, submission_id)
        property_tree = self.class.tree_view_property(self.submission)
        pattern = "?c <#{property_tree.to_s}> <#{class_id.to_s}> . "
        query = <<eos
SELECT ?c WHERE {
GRAPH <#{submission_id}> {
  #{pattern}
}
}
LIMIT 1
eos
        return query
      end

      def hierarchy_query(direction, class_ids)
        filter_ids = class_ids.map { |id| "?id = <#{id}>" } .join " || "
        directional_pattern = ""
        property_tree = self.class.tree_view_property(self.submission)
        if direction == :ancestors
          directional_pattern = "?id <#{property_tree.to_s}> ?node . "
        else
          directional_pattern = "?node <#{property_tree.to_s}> ?id . "
        end

        query = <<eos
SELECT DISTINCT ?id ?node ?graph WHERE {
GRAPH ?graph {
  #{directional_pattern}
}
FILTER (#{filter_ids})
}
eos
        return query
      end

      def append_if_not_there_already(path, r)
        return nil if r.id.to_s["#Thing"]
        return nil if (path.select { |x| x.id.to_s == r.id.to_s }).length > 0
        path << r
      end

      def traverse_path_to_root(parents, paths, path_i, tree = false, roots = nil)
        return if (tree && parents.length == 0)

        recursions = [path_i]
        recurse_on_path = [false]
        if parents.length > 1 and not tree
          (parents.length-1).times do
            paths << paths[path_i].clone
            recursions << (paths.length - 1)
            recurse_on_path << false
          end

          parents.each_index do |i|
            rec_i = recursions[i]
            recurse_on_path[i] = recurse_on_path[i] ||
              !append_if_not_there_already(paths[rec_i], parents[i]).nil?
          end
        else
          path = paths[path_i]
          recurse_on_path[0] = !append_if_not_there_already(path, parents[0]).nil?
        end

        recursions.each_index do |i|
          rec_i = recursions[i]
          path = paths[rec_i]
          p = path.last
          next if p.id.to_s["umls/OrphanClass"]

          if !tree_root?(p, roots) && recurse_on_path[i]
            if p.bring?(:parents)
              p.bring(parents: [:prefLabel, :synonym, :definition, :inScheme, parents: [:prefLabel, :synonym, :definition, :inScheme]])
            end

            if !p.loaded_attributes.include?(:parents)
              # fail safely
              logger = LinkedData::Parser.logger || Logger.new($stderr)
              logger.error("Class #{p.id.to_s} from #{p.submission.id} cannot load parents")
              return
            end

            traverse_path_to_root(p.parents.dup, paths, rec_i, tree=tree, roots=roots)
          end
        end
      end

    end
  end
end
