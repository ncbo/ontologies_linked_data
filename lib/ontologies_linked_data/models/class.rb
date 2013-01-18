module LinkedData
  module Models
    class Class

      attr_accessor :id
      attr_accessor :graph

      attr_accessor :submission

      def initialize(id,graph, submission, prefLabel = nil, synonymLabel = nil)
        @id = id

        @graph = graph
        @attributes = { :prefLabel => prefLabel, :synonyms => synonymLabel }

        #backreference to the submission that "owns" the term
        @submission = submission

      end

      def prefLabel
        return @attributes[:prefLabel]
      end

      def synonymLabel
        return [] if @attributes[:synonyms].nil?
        @attributes[:synonyms].select!{ |sy| sy != nil }
        return @attributes[:synonyms]
      end

      def loaded_parents?
        return !@attributes[:parents].nil?
      end

      def load_parents
        hierarchyProperty = @submission.hierarchyProperty ||
                                LinkedData::Utils::Namespaces.default_hieararchy_property
        graph = submission.resource_id
        query = <<eos
SELECT DISTINCT ?id WHERE {
  GRAPH <#{graph.value}> {
    ?id <#{hierarchyProperty.value}> ?parentId .
    FILTER (!isBLANK(?parentId))
} } ORDER BY ?id
eos
        rs = Goo.store.query(query)
        classes = []
        rs.each_solution do |sol|
          binding.pry
        end
      end

      def self.where(*args)
        params = args[0]
        submission = params[:submission]
        if submission.nil?
          raise ArgumentError, "Submission needs to be provided to retrive terms"
        end

        graph = submission.resource_id
        classType =  submission.classType || LinkedData::Utils::Namespaces.default_type_for_classes

          query = <<eos
SELECT DISTINCT ?id ?prefLabel ?synonymLabel WHERE {
  GRAPH <#{graph.value}> {
    ?id a <#{classType.value}> .
    OPTIONAL { ?id <#{LinkedData::Utils::Namespaces.default_pref_label.value}> ?prefLabel . }
    OPTIONAL { ?id <#{LinkedData::Utils::Namespaces.rdfs_label}> ?synonymLabel . }
    FILTER(!isBLANK(?id))
} } ORDER BY ?id
eos
        rs = Goo.store.query(query)
        classes = []
        rs.each_solution do |sol|
          if ((classes.length > 0) and (classes[-1].id.value == sol.get(:id).value))
            classes[-1].synonymLabel << sol.get(:synonymLabel)
          else
            classes << Class.new(sol.get(:id),graph, sol.get(:prefLabel), [sol.get(:synonymLabel)])
          end
        end
        return classes
      end

    end
  end
end
