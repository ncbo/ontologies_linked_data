require "set"
require "cgi"
require "ontologies_linked_data/models/notes/note"

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
        unless submission.loaded_attributes.include?(:hasOntologyLanguage)
          submission.bring(:hasOntologyLanguage)
        end
        if submission.hasOntologyLanguage
          return submission.hasOntologyLanguage.class_type
        end
        return RDF::OWL[:Class]
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

      #transitive children
      attribute :descendants, namespace: :rdfs,
                  enforce: [:list, :class],
                  property: :subClassOf,
                  inverse: { on: :class , attribute: :parents },
                  transitive: true

      search_options :index_id => lambda { |t| "#{t.id.to_s}_#{t.submission.ontology.acronym}_#{t.submission.submissionId}" },
                     :document => lambda { |t| t.get_index_doc }

      attribute :semanticType, enforce: [:list], :namespace => :umls, :property => :hasSTY
      attribute :cui, :namespace => :umls, alias: true
      attribute :xref, :namespace => :oboinowl_gen, alias: true

      attribute :notes,
            inverse: { on: :note, attribute: :relatedClass }

      # Hypermedia settings
      embed :children, :ancestors, :descendants, :parents
      serialize_default :prefLabel, :synonym, :definition, :obsolete
      serialize_methods :properties
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

      def get_index_doc
        doc = {
            :resource_id => self.id.to_s,
            :ontologyId => self.submission.id.to_s,
            :submissionAcronym => self.submission.ontology.acronym,
            :submissionId => self.submission.submissionId,
            :obsolete => self.obsolete.nil? ? "false" : self.obsolete.to_s
        }

        all_attrs = self.to_hash
        std = [:id, :prefLabel, :notation, :synonym, :definition]

        std.each do |att|
          cur_val = all_attrs[att]

          if (cur_val.is_a?(Array))
            doc[att] = []
            cur_val = cur_val.uniq
            cur_val.map { |val| doc[att] << (val.kind_of?(Goo::Base::Resource) ? val.id.to_s : val.to_s.strip) }
          else
            doc[att] = cur_val.to_s.strip
          end
          all_attrs.delete att
        end

        all_attrs.delete :submission
        props = []

        #for redundancy with prefLabel
        all_attrs.delete :label

        all_attrs.each do |attr_key, attr_val|
          if (!doc.include?(attr_key))
            if (attr_val.is_a?(Array))
              attr_val = attr_val.uniq
              attr_val.map { |val| props << (val.kind_of?(Goo::Base::Resource) ? val.id.to_s : val.to_s.strip) }
            else
              props << attr_val.to_s.strip
            end
          end
        end
        props.uniq!
        doc[:property] = props
        return doc
      end

      def childrenCount
        raise ArgumentError, "No aggregates included in #{self.id.to_ntriples}" if !self.aggregates
        cc = self.aggregates.select { |x| x.attribute == :children && x.aggregate == :count}.first
        raise ArgumentError, "No aggregate for attribute children and count found in #{self.id.to_ntriples}" if !cc
        return cc.value
      end

      def properties
        if self.unmapped.nil?
          raise Exception, "Properties can be call only with :unmmapped attributes preloaded"
        end
        properties = self.unmapped
        bad_iri = RDF::URI.new('http://bioportal.bioontology.org/metadata/def/prefLabel')
        properties.delete(bad_iri)

        #hack to be remove when closing NCBO-453
        orphan_id = "http://bioportal.bioontology.org/ontologies/umls/OrphanClass"
        subClassOf = RDF::RDFS[:subClassOf].to_s
        filtered = false
        change = Hash.new
        properties.each do |k,v|
          if k.to_s ==  subClassOf
            if v.is_a?(Array)
              if v.index { |x| x.to_s == orphan_id}
                filtered = true
              end
              v.delete_if { |x| x.to_s == orphan_id}
            end
          end
          unless k.to_s ==  subClassOf && filtered
            change[k] = v
          end
        end
        if filtered
          properties = change
        end
        #end hack
        
        properties
      end

      def paths_to_root
        self.bring(parents: [:prefLabel,:synonym, :definition]) if self.bring?(:parents)

        return [] if self.parents.nil? or self.parents.length == 0
        paths = [[self]]
        traverse_path_to_root(self.parents.dup, paths, 0)
        paths.each do |p|
          p.reverse!
        end
        return paths
      end

      def self.partially_load_children(models,threshold,submission,only_children_count=false)

        ld = [:prefLabel, :definition, :synonym]

        single_load = []
        query = self.in(submission)
              .models(models)
        if only_children_count
            query = query.include(ld)
        end
        query.aggregate(:count, :children).all

        models.each do |cls|
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
                .include(children: [:prefLabel]).all
        end
      end

      def tree
        self.bring(parents: [:prefLabel]) if self.bring?(:parents)
        return self if self.parents.nil? or self.parents.length == 0
        paths = [[self]]
        traverse_path_to_root(self.parents.dup, paths, 0, tree=true)
        roots = self.submission.roots

        #select one path that gets to root
        path = nil
        paths.each do |p|
          if (p.map { |x| x.id.to_s } & roots.map { |x| x.id.to_s }).length > 0
            path = p
            break
          end
        end

        if path.nil?
          return self
        end

        items_hash = {}
        path.each do |t|
          items_hash[t.id.to_s] = t
        end

        self.class.in(submission)
              .models(items_hash.values)
              .include(:prefLabel,:synonym).all

        LinkedData::Models::Class
          .partially_load_children(items_hash.values,99,self.submission)

        path.reverse!
        path.last.instance_variable_set("@children",[])
        childrens_hash = {}
        path.each do |m|
          next if m.id.to_s["#Thing"]
          m.children.each do |c|
            childrens_hash[c.id.to_s] = c
          end
        end

       LinkedData::Models::Class.
         partially_load_children(childrens_hash.values,99,self.submission,only_children_count=true)

        #build the tree
        root_node = path.first
        tree_node = path.first
        path.delete_at(0)
        while tree_node &&
              !tree_node.id.to_s["#Thing"] &&
              tree_node.children.length > 0 and path.length > 0 do

          next_tree_node = nil
          tree_node.children.each_index do |i|
            if tree_node.children[i].id.to_s == path.first.id.to_s
              next_tree_node = path.first
              children = tree_node.children.dup
              children[i] = path.first
              tree_node.instance_variable_set("@children",children)
            else
              tree_node.children[i].instance_variable_set("@children",[])
            end
          end
          tree_node = next_tree_node
          path.delete_at(0)
        end
        return root_node
      end

      def ancestors
        if @ancestors
          return @ancestors.select { |x| !x.id.to_s["owl#Thing"] }.freeze
        end
        raise Goo::Base::AttributeNotLoaded, "Persistent object with `ancestors` not loaded"
      end

      private

      def append_if_not_there_already(path,r)
        return nil if r.id.to_s["#Thing"]
        return nil if (path.select { |x| x.id.to_s == r.id.to_s }).length > 0
        path << r
      end

      def traverse_path_to_root(parents, paths, path_i, tree=false)
        return if (tree and parents.length == 0)
        recurse_on_path = []
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
          recurse_on_path[0] = !append_if_not_there_already(path,parents[0]).nil?
        end

        recursions.each_index do |i|
          rec_i = recursions[i]
          path = paths[rec_i]
          p = path.last
          next if p.id.to_s["umls/OrphanClass"]
          if p.bring?(:parents)
            p.bring(parents: [:prefLabel,:synonym, :definition] )
          end

          if !p.loaded_attributes.include?(:parents)
            # fail safely
            LOGGER.error("Class #{p.id.to_s} from #{p.submission.id}  cannot load parents")
            return
          end

          if !p.id.to_s["#Thing"] &&\
              (recurse_on_path[i] && p.parents && p.parents.length > 0)
            traverse_path_to_root(p.parents.dup, paths, rec_i, tree=tree)
          end
        end
      end

    end

  end
end
