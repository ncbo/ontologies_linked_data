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
      attribute :created, namespace:  :dcterms
      attribute :modified, namespace:  :dcterms

      # Hypermedia settings
      embed :children, :ancestors, :descendants, :parents
      serialize_default :prefLabel, :synonym, :definition, :cui, :semanticType, :obsolete, :matchType, :ontologyType, :provisional, :created, :modified # an attribute used in Search (not shown out of context)
      serialize_methods :properties, :childrenCount, :hasChildren
      serialize_never :submissionAcronym, :submissionId, :submission, :descendants
      aggregates childrenCount: [:count, :children]
      links_load submission: [ontology: [:acronym]]
      do_not_load :descendants, :ancestors
      prevent_serialize_when_nested :properties, :parents, :children, :ancestors, :descendants
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

      # to_set is an optional array that allows passing specific
      # field names that require updating
      # if to_set is nil, it's assumed to be a new document for insert
      def index_doc(to_set=nil)
        doc = {}
        path_ids = Set.new
        self.bring(:submission) if self.bring?(:submission)

        if to_set.nil?
          begin
            doc[:childCount] = self.childrenCount
          rescue ArgumentError
            LinkedData::Models::Class.in(self.submission).models([self]).aggregate(:count, :children).all
            doc[:childCount] = self.childrenCount
          rescue Exception => e
            doc[:childCount] = 0
            puts "Exception getting childCount for search for #{self.id.to_s}: #{e.class}: #{e.message}"
          end

          begin
            # paths_to_root = self.paths_to_root
            # paths_to_root.each do |paths|
            #   path_ids += paths.map { |p| p.id.to_s }
            # end
            # path_ids.delete(self.id.to_s)
            path_ids = retrieve_hierarchy_ids(:ancestors)
            path_ids.select! { |x| !x["owl#Thing"] }
            doc[:parents] = path_ids
          rescue Exception => e
            doc[:parents] = Set.new
            puts "Exception getting paths to root for search for #{self.id.to_s}: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
          end

          doc[:ontologyId] = self.submission.id.to_s
          doc[:submissionAcronym] = self.submission.ontology.acronym
          doc[:submissionId] = self.submission.submissionId
          doc[:ontologyType] = self.submission.ontology.ontologyType.get_code_from_id
          doc[:obsolete] = self.obsolete.to_s

          all_attrs = self.to_hash
          std = [:id, :prefLabel, :notation, :synonym, :definition, :cui]

          std.each do |att|
            cur_val = all_attrs[att]

            # don't store empty values
            next if cur_val.nil? || (cur_val.respond_to?('empty?') && cur_val.empty?)

            if cur_val.is_a?(Array)
              # don't store empty values
              cur_val = cur_val.reject { |c| c.respond_to?('empty?') && c.empty? }
              doc[att] = []
              cur_val = cur_val.uniq
              cur_val.map { |val| doc[att] << (val.kind_of?(Goo::Base::Resource) ? val.id.to_s : val.to_s.strip) }
            else
              doc[att] = cur_val.to_s.strip
            end
          end

          # special handling for :semanticType (AKA tui)
          if all_attrs[:semanticType] && !all_attrs[:semanticType].empty?
            doc[:semanticType] = []
            all_attrs[:semanticType].each { |semType| doc[:semanticType] << semType.split("/").last }
          end
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
      def properties
        return nil if self.unmapped.nil?
        properties = self.unmapped
        BLACKLIST_URIS.each {|bad_iri| properties.delete(RDF::URI.new(bad_iri))}
        properties
      end

      def paths_to_root()
        self.bring(parents: [:prefLabel, :synonym, :definition]) if self.bring?(:parents)
        return [] if self.parents.nil? or self.parents.length == 0
        paths = [[self]]
        traverse_path_to_root(self.parents.dup, paths, 0)
        paths.each do |p|
          p.reverse!
        end
        paths
      end

      def self.partially_load_children(models, threshold, submission)
        ld = [:prefLabel, :definition, :synonym]
        ld << :subClassOf if submission.hasOntologyLanguage.obo?
        single_load = []
        query = self.in(submission)
              .models(models)
        query.aggregate(:count, :children).all

        models.each do |cls|
          if cls.aggregates.nil?
            next
          end
          if cls.aggregates.first.value > threshold
            #too many load a page
            self.in(submission)
                .models(single_load)
                .include(children: [:prefLabel]).all
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

        if single_load.length > 0
          self.in(submission)
                .models(single_load)
                .include(ld << {children: [:prefLabel]}).all
        end
      end

      def tree()
        self.bring(parents: [:prefLabel]) if self.bring?(:parents)
        return self if self.parents.nil? or self.parents.length == 0
        paths = [[self]]
        traverse_path_to_root(self.parents.dup, paths, 0, tree=true)
        roots = self.submission.roots(extra_include=[:hasChildren])
        threshhold = 99

        #select one path that gets to root
        path = nil
        paths.each do |p|
          if (p.map { |x| x.id.to_s } & roots.map { |x| x.id.to_s }).length > 0
            path = p
            break
          end
        end

        if path.nil?
          # do one more check for root classes that don't get returned by the submission.roots call
          paths.each do |p|
            root_node = p.last
            root_parents = root_node.parents

            if root_parents.empty?
              path = p
              break
            end
          end
          return self if path.nil?
        end

        items_hash = {}
        path.each do |t|
          items_hash[t.id.to_s] = t
        end

        attrs_to_load = [:prefLabel,:synonym,:obsolete]
        attrs_to_load << :subClassOf if submission.hasOntologyLanguage.obo?
        self.class.in(submission)
              .models(items_hash.values)
              .include(attrs_to_load).all

        LinkedData::Models::Class
          .partially_load_children(items_hash.values,threshhold,self.submission)

        path.reverse!
        path.last.instance_variable_set("@children",[])
        childrens_hash = {}
        path.each do |m|
          next if m.id.to_s["#Thing"]
          m.children.each do |c|
            childrens_hash[c.id.to_s] = c
          end
        end

        LinkedData::Models::Class.partially_load_children(childrens_hash.values,threshhold, self.submission)

        #build the tree
        root_node = path.first
        tree_node = path.first
        path.delete_at(0)
        while tree_node &&
              !tree_node.id.to_s["#Thing"] &&
              tree_node.children.length > 0 and path.length > 0 do

          next_tree_node = nil
          tree_node.load_has_children
          tree_node.children.each_index do |i|
            if tree_node.children[i].id.to_s == path.first.id.to_s
              next_tree_node = path.first
              children = tree_node.children.dup
              children[i] = path.first
              tree_node.instance_variable_set("@children",children)
              children.each do |c|
                  c.load_has_children
              end
            else
              tree_node.children[i].instance_variable_set("@children",[])
            end
          end

          if path.length > 0 && next_tree_node.nil?
            tree_node.children << path.shift
          end

          tree_node = next_tree_node
          path.delete_at(0)
        end

        root_node
      end

      def tree_sorted()
        tr = tree
        self.class.sort_tree_children(tr)
        tr
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

      def traverse_path_to_root(parents, paths, path_i, tree=false)
        return if (tree and parents.length == 0)
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

          if p.bring?(:parents)
            p.bring(parents: [:prefLabel, :synonym, :definition, parents: [:prefLabel, :synonym, :definition]])
          end

          if !p.loaded_attributes.include?(:parents)
            # fail safely
            logger = LinkedData::Parser.logger || Logger.new($stderr)
            logger.error("Class #{p.id.to_s} from #{p.submission.id} cannot load parents")
            return
          end

          if !p.id.to_s["#Thing"] &&\
              (recurse_on_path[i] && p.parents && p.parents.length > 0)
            traverse_path_to_root(p.parents.dup, paths, rec_i, tree=tree)
          end
        end
      end

      def self.sort_tree_children(root_node)
        self.sort_classes!(root_node.children)
        root_node.children.each { |ch| self.sort_tree_children(ch) }
      end

      def self.sort_classes(classes)
        classes.sort { |class_a, class_b| self.compare_classes(class_a, class_b) }
      end

      def self.sort_classes!(classes)
        classes.sort! { |class_a, class_b| self.compare_classes(class_a, class_b) }
        classes
      end

      def self.compare_classes(class_a, class_b)
        label_a = ""
        label_b = ""
        class_a.bring(:prefLabel) if class_a.bring?(:prefLabel)
        class_b.bring(:prefLabel) if class_b.bring?(:prefLabel)

        begin
          label_a = class_a.prefLabel unless (class_a.prefLabel.nil? || class_a.prefLabel.empty?)
        rescue Goo::Base::AttributeNotLoaded
          label_a = ""
        end

        begin
          label_b = class_b.prefLabel unless (class_b.prefLabel.nil? || class_b.prefLabel.empty?)
        rescue Goo::Base::AttributeNotLoaded
          label_b = ""
        end

        label_a = class_a.id if label_a.empty?
        label_b = class_b.id if label_b.empty?

        [label_a.downcase] <=> [label_b.downcase]
      end

    end
  end
end
