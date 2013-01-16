module LinkedData
  module Models
    class Class


      attr_accessor :id
      attr_accessor :graph

      def initialize(id,graph,prefLabel = nil, synonymLabel = nil)
        @id = id

        @graph = graph
        @attributes = { :prefLabel => prefLabel, :synonyms => synonymLabel }

      end

      def prefLabel
        return (@attributes[:prefLabel] ? @attributes[:prefLabel].value : nil)
      end

      def synonymLabel
        @attributes[:synonyms].select!{ |sy| sy != nil }
        return (@attributes[:synonyms] ? (@attributes[:synonyms].map { |sy| sy.value })  : [])
      end

      def self.where(*args)
        if args.length == 1 and args[0].include? :graph
          params = args[0]
          graph = params[:graph]
          prefLabelProperty =  params[:prefLabelProperty] || LinkedData::Utils::Namespaces.default_pref_label
          classType =  params[:classType] || LinkedData::Utils::Namespaces.default_type_for_classes

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
        else
          raise ArgumentError, "Current Class implementation search capabilities are minimal"
        end
      end

      def rdfs_labels
        query = <<eos
SELECT DISTINCT ?id ?label WHERE {
  GRAPH <#{self.graph.value}> {
    <#{self.id.value}> <#{LinkedData::Utils::Namespaces.rdfs_label}> ?label .
} }
eos
        rdfs_labels = []
        Goo.store.query(query).each_solution do |sol|
          rdfs_labels << sol.get(:label).value
        end
        return rdfs_labels
      end
    end
  end
end
