module LinkedData
  module Models
    class Class

      attr_accessor :id
      attr_accessor :graph

      attr_accessor :ontology

      def initialize(id,graph, ontology, prefLabel = nil, synonymLabel = nil)
        @id = id

        @graph = graph
        @attributes = { :prefLabel => prefLabel, :synonyms => synonymLabel }

        #backreference to the ontology that "owns" the term
        @ontology = ontology

      end

      def prefLabel
        return (@attributes[:prefLabel] ? @attributes[:prefLabel].value : nil)
      end

      def synonymLabel
        return [] if @attributes[:synonyms].nil?
        @attributes[:synonyms].select!{ |sy| sy != nil }
        return (@attributes[:synonyms] ? (@attributes[:synonyms].map { |sy| sy.value })  : [])
      end

      def loaded_parents?
        return !@attributes.nil?
      end

      def load_parents
          query = <<eos
SELECT DISTINCT ?id ?prefLabel ?synonymLabel WHERE {
  GRAPH <#{graph.value}> {
    ?id a <#{classType.value}> .
    OPTIONAL { ?id <#{LinkedData::Utils::Namespaces.default_pref_label.value}> ?prefLabel . }
    OPTIONAL { ?id <#{LinkedData::Utils::Namespaces.rdfs_label}> ?synonymLabel . }
    FILTER(!isBLANK(?id))
} } ORDER BY ?id
eos
      end

      def self.where(*args)
        params = args[0]
        ontology = params[:ontology]
        if ontology.nil?
          raise ArgumentError, "Ontology needs to be provided to retrive terms"
        end

        graph = ontology.resource_id
        classType =  ontology.classType || LinkedData::Utils::Namespaces.default_type_for_classes

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
