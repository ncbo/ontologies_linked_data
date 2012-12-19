module LinkedData
  module Models
    class Class


      attr_accessor :id
      attr_accessor :graph

      def initialize(id,graph,prefLabel = nil)
        @id = id
        @prefLabel = prefLabel
        @graph = graph
      end

      def prefLabel
        return (@prefLabel ? @prefLabel.value : nil)
      end 

      def self.where(*args)
        if args.length == 1 and args[0].include? :graph
          params = args[0]
          graph = params[:graph]
          prefLabelProperty =  params[:prefLabelProperty] || LinkedData::Utils::Namespaces.default_pref_label 
          classType =  params[:classType] || LinkedData::Utils::Namespaces.default_type_for_classes

          query = <<eos
SELECT DISTINCT ?id ?label WHERE {
  GRAPH <#{graph.value}> {
    ?id a <#{classType.value}> .
    OPTIONAL { ?id <#{LinkedData::Utils::Namespaces.skos_prefLabel}> ?label . }
} }
eos
          rs = Goo.store.query(query)
          classes = []
          rs.each_solution do |sol|
            classes << Class.new(sol.get(:id),graph, sol.get(:label))
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
