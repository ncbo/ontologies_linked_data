require "set"
require "cgi"
require_relative "notes/note"

module LinkedData
  module Models
    class ClassAttributeNotLoaded < StandardError
    end

    class Class < LinkedData::Models::Base
      model :class, name_with: :id, collection: :submission,
            namespace: :owl, :schemaless => :true

      attribute :submission, :collection => lambda { |s| s.resource_id }, :namespace => :metadata

      attribute :label, namespace: :rdfs, enforce: [:list]
      attribute :prefLabel, namespace: :skos, enforce: [:existence], alias: true
      attribute :synonym, namespace: :skos, enforce: [:list], property: :altLabel, alias: true
      attribute :definition, namespace: :skos, enforce: [:list], alias: true
      attribute :deprecated, namespace: :owl

      attribute :notation, namespace: :skos

      attribute :parents, namespace: :rdfs, property: :subClassOf, enforce: [:list, :class]

      #transitive parent
      attribute :ancestors, namespace: :rdfs, property: :subClassOf, enforce: [:list, :class],
                  transitive: true

      attribute :children, namespace: :rdfs, property: :subClassOf,
                  inverse: { on: :class , :attribute => :parents }

      #transitive children
      attribute :descendants, namespace: :rdfs, property: :subClassOf,
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
      serialize_default :prefLabel, :synonym, :definition
      serialize_methods :properties
      serialize_never :submissionAcronym, :submissionId, :submission
      aggregates childrenCount: [:count, :children]
      links_load submission: [ontology: [:acronym]]
      link_to LinkedData::Hypermedia::Link.new("self", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("ontology", lambda {|s| "ontologies/#{s.submission.ontology.acronym}"}, Goo.vocabulary["Ontology"]),
              LinkedData::Hypermedia::Link.new("children", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/children"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("parents", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/parents"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("descendants", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/descendants"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("ancestors", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/ancestors"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("tree", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/tree"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("notes", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/notes"}, LinkedData::Models::Note.type_uri),
              LinkedData::Hypermedia::Link.new("mappings", lambda {|s| "ontologies/#{s.submission.ontology.acronym}/classes/#{CGI.escape(s.id.to_s)}/mappings"}, Goo.vocabulary["Mapping"]),
              LinkedData::Hypermedia::Link.new("ui", lambda {|s| "http://#{LinkedData.settings.ui_host}/ontologies/#{s.submission.ontology.acronym}?p=terms&conceptid=#{CGI.escape(s.id.to_s)}"}, self.uri_type)

      # HTTP Cache settings
      cache_timeout 86400
      cache_segment_instance lambda {|cls| segment_instance(cls) }
      cache_segment_keys [:class]
      cache_load submission: [ontology: [:acronym]]

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
        cls_all = self.class.find(self.id).in(self.submission).include(:unmapped).first
        properties = cls_all.unmapped
        bad_iri = RDF::URI.new('http://bioportal.bioontology.org/metadata/def/prefLabel')
        properties.delete(bad_iri)
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

      def tree
        self.bring(parents: [:prefLabel]) if self.bring?(:parents)
        return self if self.parents.nil? or self.parents.length == 0
        paths = [[self]]
        traverse_path_to_root(self.parents.dup, paths, 0, tree=true)
        path = paths.first
        items_hash = {}
        path.each do |t|
          items_hash[t.id.to_s] = t
        end

        self.class.in(self.submission)
              .models(items_hash.values)
              .include(:prefLabel, :children)
              .aggregate(:count, :children).all

        path.reverse!
        path.last.instance_variable_set("@children",[])
        childrens_hash = {}
        path.each do |m|
          m.children.each do |c|
            childrens_hash[c.id.to_s] = c
          end
        end

        self.class.in(self.submission)
              .models(childrens_hash.values)
              .include(:prefLabel, :children)
              .aggregate(:count, :children).all

        #build the tree
        root_node = path.first
        tree_node = path.first
        path.delete_at(0)
        while tree_node.children.length > 0 and path.length > 0 do
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

      private

      def append_if_not_there_already(path,r)
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
          p.bring(parents: [:prefLabel,:synonym, :definition] ) if p.bring?(:parents)
          if (recurse_on_path[i] && p.parents && p.parents.length > 0)
            traverse_path_to_root(p.parents.dup, paths, rec_i, tree=tree)
          end
        end
      end

    end

  end
end
