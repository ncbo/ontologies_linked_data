
module LinkedData
  module Models

    class OntologyProperty < LinkedData::Models::Base
      model :ontology_property, name_with: ->(p) { uuid_uri_generator(p) }

      def self.index_schema(schema_generator)
        schema_generator.add_field(:label, 'text_general', indexed: true, stored: true, multi_valued: true)
        schema_generator.add_field(:labelGenerated, 'text_general', indexed: true, stored: true, multi_valued: true)

        schema_generator.add_field(:definition, 'string', indexed: true, stored: true, multi_valued: true)
        schema_generator.add_field(:submissionAcronym, 'string', indexed: true, stored: true, multi_valued: false)
        schema_generator.add_field(:parents, 'string', indexed: true, stored: true, multi_valued: true)
        schema_generator.add_field(:ontologyType, 'string', indexed: true, stored: true, multi_valued: false)
        schema_generator.add_field(:propertyType, 'string', indexed: true, stored: true, multi_valued: false)
        schema_generator.add_field(:ontologyId, 'string', indexed: true, stored: true, multi_valued: false)
        schema_generator.add_field(:submissionId, 'pint', indexed: true, stored: true, multi_valued: false)

        %i[label labelGenerated].each do |field|
          schema_generator.add_copy_field(field, '_text_')
          schema_generator.add_copy_field(field, "#{field}Exact")
          schema_generator.add_copy_field(field, "#{field}Suggest")
          schema_generator.add_copy_field(field, "#{field}SuggestEdge")
          schema_generator.add_copy_field(field, "#{field}SuggestNgram")
        end
      end

      enable_indexing(:property_search_active, :property, target_collection: :prop_search_core1) do |schema_generator|
        index_schema(schema_generator)
      end

      def properties
        self.unmapped
      end

      def retrieve_ancestors
        retrieve_ancestors_descendants(:ancestors)
      end

      def retrieve_descendants
        retrieve_ancestors_descendants(:descendants)
      end

      def retrieve_ancestors_descendants(which)
        ids = retrieve_hierarchy_ids(which)

        if ids.length == 0
          return []
        end

        ids.select! { |x| !x["owl#{self.class::TOP_PROPERTY}"] }
        ids.map! { |x| RDF::URI.new(x) }
        models = self.class.in(self.submission).ids(ids).all
        models.each { |m| m.load_has_children } if which == :descendants
        self.class.sort_properties(models)
      end

      def hasChildren
        if instance_variable_get("@intlHasChildren").nil?
          raise ArgumentError, "hasChildren not loaded for #{self.id.to_ntriples}"
        end

        @intlHasChildren
      end

      # this call must be preceded by:
      # self.class.in(self.submission).models([self]).aggregate(:count, :children).all
      def childrenCount
        self.bring(:submission) if self.bring?(:submission)
        raise ArgumentError, "No aggregates included in #{self.id.to_ntriples}. Submission: #{self.submission.id.to_s}" unless self.aggregates
        cc = self.aggregates.select { |x| x.attribute == :children && x.aggregate == :count}.first
        raise ArgumentError, "No aggregate for attribute children and count found in #{self.id.to_ntriples}" unless cc
        cc.value
      end

      def tree
        self.bring(parents: [:label]) if self.bring?(:parents)
        threshold = 99

        if self.parents.nil? || self.parents.length == 0
          self.load_has_children
          self.instance_variable_set("@children", [])
          return self
        end

        paths = [[self]]

        traverse_path_to_root(self.parents.dup, paths, 0, tree=true, top_property=self.class::TOP_PROPERTY)

        items_hash = {}
        path = paths[0]
        path.each { |t| items_hash[t.id.to_s] = t }

        self.class.partially_load_children(items_hash.values, threshold, self.submission)

        path.reverse!
        path.last.instance_variable_set("@children", [])
        children_hash = {}

        path.delete_if do |m|
          next if self.class::TOP_PROPERTY && m.id.to_s[self.class::TOP_PROPERTY]

          # handle https://github.com/ncbo/ontologies_linked_data/issues/71
          begin
            m.children.each { |c| children_hash[c.id.to_s] = c }
            false
          rescue Goo::Base::AttributeNotLoaded
            true
          end
        end

        self.class.partially_load_children(children_hash.values, threshold, self.submission)

        #build the tree
        root_node = path.first
        tree_node = path.first
        path.delete_at(0)

        while tree_node && (self.class::TOP_PROPERTY.nil? || !tree_node.id.to_s[self.class::TOP_PROPERTY]) && tree_node.children.length > 0 && path.length > 0 do
          next_tree_node = nil
          tree_node.load_has_children

          tree_node.children.each_index do |i|
            if tree_node.children[i].id.to_s == path.first.id.to_s
              next_tree_node = path.first
              children = tree_node.children.dup
              children[i] = path.first
              children.each { |c| c.load_has_children }
              tree_node.instance_variable_set("@children", children)
            else
              tree_node.children[i].instance_variable_set("@children", [])
            end
          end

          tree_node.children << path.shift if path.length > 0 && next_tree_node.nil?
          tree_node = next_tree_node
          path.delete_at(0)
        end

        self.class.sort_tree_children(root_node)

        root_node
      end

      def load_has_children
        unless instance_variable_get("@intlHasChildren").nil?
          return
        end

        graphs = [self.submission.id.to_s]
        query = has_children_query(self.id.to_s, graphs.first)
        has_c = false
        Goo.sparql_query_client.query(query, query_options: {rules: :NONE }, graphs: graphs).each { |sol| has_c = true }
        @intlHasChildren = has_c
      end

      def has_children_query(class_id, submission_id)
        property_tree = RDF::RDFS[:subPropertyOf]
        safe_class_id_uri = class_id.to_s.gsub(' ', '%20').gsub('<', '%3C').gsub('>', '%3E').gsub('[', '%5B').gsub(']', '%5D')
        pattern = "?c <#{property_tree.to_s}> <#{safe_class_id_uri}> . "
        query = <<eos
SELECT ?c WHERE {
  GRAPH <#{submission_id}> {
    #{pattern}
  }
}
LIMIT 1
eos
        query
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
              query = hierarchy_query(direction, ids_slice)

              Goo.sparql_query_client.query(query, query_options: {rules: :NONE }, graphs: graphs).each do |sol|
                parent = sol[:node].to_s
                next unless parent.start_with?("http")
                ontology = sol[:graph].to_s
                next_level_thread << parent if submission_id_string == ontology && !all_ids.include?(parent)
              end

              Thread.current["next_level_thread"] = next_level_thread
            }
          end

          threads.each {|t| t.join; next_level.merge(t["next_level_thread"]) }
          current_level += 1
          pre_size = all_ids.length
          all_ids.merge(next_level)

          #nothing new
          return all_ids if all_ids.length == pre_size
          level_ids = next_level
        end

        all_ids
      end

      def hierarchy_query(direction, prop_ids)
        filter_ids = prop_ids.map { |id| "?id = <#{id}>" }.join " || "
        directional_pattern = nil
        property_tree = RDF::RDFS[:subPropertyOf]

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
        query
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

      def index_doc(to_set=nil)
        self.bring(:label) if self.bring?(:label)
        self.bring(:submission) if self.bring?(:submission)
        self.submission.bring(:submissionId) if self.submission.bring?(:submissionId)
        self.submission.bring(:ontology) if self.submission.bring?(:ontology)
        self.submission.ontology.bring(:acronym) if self.submission.ontology.bring?(:acronym)
        self.submission.ontology.bring(:ontologyType) if self.submission.ontology.bring?(:ontologyType)

        doc = {
            :ontologyId => self.submission.id.to_s,
            :submissionAcronym => self.submission.ontology.acronym,
            :submissionId => self.submission.submissionId,
            :ontologyType => self.submission.ontology.ontologyType.get_code_from_id,
            :propertyType => self.class::PROPERTY_TYPE,
            :labelGenerated => LinkedData::Utils::Triples.generated_label(self.id, self.label)
        }

        all_attrs = self.to_hash
        std = %i[id label definition parents]

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

        doc
      end

      def append_if_not_there_already(path, r, top_property=nil)
        return nil if top_property && r.id.to_s[top_property]
        return nil if (path.select { |x| x.id.to_s == r.id.to_s }).length > 0
        path << r
      end

      def traverse_path_to_root(parents, paths, path_i, tree=false, top_property=nil)
        return if parents.empty?
        recursions = [path_i]
        recurse_on_path = [false]

        # multiple paths
        if parents.length > 1 && !tree
          (parents.length - 1).times do
            paths << paths[path_i].clone
            recursions << (paths.length - 1)
            recurse_on_path << false
          end

          parents.each_index do |i|
            rec_i = recursions[i]
            recurse_on_path[i] = recurse_on_path[i] ||
                !append_if_not_there_already(paths[rec_i], parents[i], top_property).nil?
          end
        else
          path = paths[path_i]
          recurse_on_path[0] = !append_if_not_there_already(path, parents[0], top_property).nil?
        end

        recursions.each_index do |i|
          rec_i = recursions[i]
          path = paths[rec_i]
          p = path.last
          p.bring(parents: %i[label definition]) if p.bring?(:parents)

          unless p.loaded_attributes.include?(:parents)
            # fail safely
            logger = LinkedData::Parser.logger || Logger.new($stderr)
            logger.error("Property #{p.id.to_s} from #{p.submission.id.to_s} cannot load parents")
            return
          end

          if (!top_property || !p.id.to_s[top_property]) && recurse_on_path[i] && p.parents && p.parents.length > 0
            traverse_path_to_root(p.parents.dup, paths, rec_i, tree=tree, top_property=top_property)
          end
        end
      end

      def self.ontology_link(m)
        if m.class == self
          m.bring(:submission) if m.bring?(:submission)
          m.submission.bring(:ontology) if m.submission.bring?(:ontology)
          m.submission.ontology.bring(:acronym) if m.submission.ontology.bring?(:acronym)
        end
        "ontologies/#{m.submission.ontology.acronym}"
      end

      def self.partially_load_children(models, threshold, submission)
        ld = %i[label definition]
        single_load = []
        query = self.in(submission).models(models)
        query.aggregate(:count, :children).all

        models.each do |prop|
          if prop.aggregates.nil?
            next
          end

          if prop.aggregates.first.value > threshold
            #too many load a page
            self.in(submission).models(single_load).include(children: [:label]).all
            page_children = self.where(parents: prop).include(ld).in(submission).page(1, threshold).all
            prop.instance_variable_set("@children", page_children.to_a)
            prop.loaded_attributes.add(:children)
          else
            single_load << prop
          end
        end

        if single_load.length > 0
          self.in(submission).models(single_load).include(ld << {children: [:label]}).all
        end
      end

      def self.sort_tree_children(root_node)
        self.sort_properties!(root_node.children)
        root_node.children.each { |ch| self.sort_tree_children(ch) }
      end

      def self.sort_properties(props)
        props.sort { |prop_a, prop_b| self.compare_properties(prop_a, prop_b) }
      end

      def self.sort_properties!(props)
        props.sort! { |prop_a, prop_b| self.compare_properties(prop_a, prop_b) }
        props
      end

      def self.compare_properties(prop_a, prop_b)
        label_a = ""
        label_b = ""
        label_a_full = []
        label_b_full = []

        prop_a.bring(:label) if prop_a.bring?(:label)
        prop_b.bring(:label) if prop_b.bring?(:label)

        begin
          if !prop_a.label.nil? && !prop_a.label.empty?
            label_a = prop_a.label[0]
            label_a_full = prop_a.label
          end
        rescue Goo::Base::AttributeNotLoaded
          label_a = ""
          label_a_full = []
        end

        begin
          if !prop_b.label.nil? && !prop_b.label.empty?
            label_b = prop_b.label[0]
            label_b_full = prop_b.label
          end
        rescue Goo::Base::AttributeNotLoaded
          label_b = ""
          label_b_full = []
        end

        if label_a.empty?
          gen_lbl_arr_a = LinkedData::Utils::Triples.generated_label(prop_a.id, label_a_full)
          label_a = gen_lbl_arr_a.empty? ? "" : gen_lbl_arr_a[0]
        end

        if label_b.empty?
          gen_lbl_arr_b = LinkedData::Utils::Triples.generated_label(prop_b.id, label_b_full)
          label_b = gen_lbl_arr_b.empty? ? "" : gen_lbl_arr_b[0]
        end

        [label_a.downcase] <=> [label_b.downcase]
      end
    end
  end

end
