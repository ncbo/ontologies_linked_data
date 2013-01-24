module LinkedData
  module Models
    class Class

      attr_accessor :resource_id
      attr_accessor :submission

      def initialize(id, submission, plabel = nil, synonyms = nil)
        @resource_id = id

        @attributes = {}

        if !plabel.nil?
          set_prefLabel plabel
        end
        @attributes[:synonyms] = synonyms

        #backreference to the submission that "owns" the term
        @submission = submission
      end

      private

      def set_prefLabel(label_input)
        label = nil
        if label_input.instance_of? Array
          if label_input.length > 1
            raise ArgumentError, "Class model only allows one label. TODO: internationalization"
          end
          if label_input.length == 1
            label = label_input[0]
          end
        else
          label = label_input
        end
        if label.instance_of? SparqlRd::Resultset::Literal
          @attributes[:prefLabel] = label
        else
          raise ArgumentError, "Unknown type of prefLabel #{label.class.name}"
        end
      end

      public

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
          if ((classes.length > 0) and (classes[-1].resource_id.value == sol.get(:id).value))
            classes[-1].synonymLabel << sol.get(:synonymLabel)
          else
            if sol.get(:prefLabel).instance_of? Array
            end
            classes << Class.new(sol.get(:id), submission, sol.get(:prefLabel), [sol.get(:synonymLabel)])
          end
        end
        return classes
      end

      def self.find(resouce_id,options)

        #TODO notes
        # fail if :submission is missing
        # resource id has to parse into an IRI if it is not already
        # nil if not found


      end

    end
  end
end
