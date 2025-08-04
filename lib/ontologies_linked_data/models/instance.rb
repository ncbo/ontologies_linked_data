
module LinkedData
  module Models
    class Instance < LinkedData::Models::Base

      model :named_individual, name_with: :id, collection: :submission,
            namespace: :owl, schemaless: :true ,  rdf_type: lambda { |*x| RDF::OWL[:NamedIndividual]}

      attribute :label, namespace: :rdfs, enforce: [:list]
      attribute :prefLabel, namespace: :skos, enforce: [:existence], alias: true

      attribute :types, namespace: :rdf, enforce: [:list], property: :type
      attribute :submission, collection: lambda { |s| s.resource_id }, namespace: :metadata

      serialize_never :submission, :id
      serialize_methods :properties

      cache_timeout 14400

      def properties
        self.unmapped
      end

    end
  end

  module InstanceLoader
    def self.count_instances_by_class(submission_id,class_id)
      ## TODO: pass directly an LinkedData::Models::OntologySubmission instance in the arguments instead of submission_id
      s = LinkedData::Models::OntologySubmission.find(submission_id).first
      instances_by_class_where_query(s, class_id: class_id).count
    end

    def self.get_instances_by_class(submission_id, class_id, page_no: nil, size: nil)
      ## TODO: pass directly an LinkedData::Models::OntologySubmission instance in the arguments instead of submission_id
      s = LinkedData::Models::OntologySubmission.find(submission_id).first

      inst = instances_by_class_where_query(s, class_id: class_id, page_no: page_no, size: size).all

      # TODO test if "include=all" parameter is passed in the request
      # For getting all the properties # For getting all the properties
      load_unmapped s,inst unless inst.nil? || inst.empty?
      inst
    end

    def self.get_instances_by_ontology(submission_id, page_no: nil, size: nil)
      ## TODO: pass directly an LinkedData::Models::OntologySubmission instance in the arguments instead of submission_id
      s = LinkedData::Models::OntologySubmission.find(submission_id).first
      inst = s.nil? ? [] : instances_by_class_where_query(s, page_no: page_no, size: size).all

      ## TODO test if "include=all" parameter is passed in the request
      load_unmapped s, inst unless inst.nil? || inst.empty?  # For getting all the properties
      inst
    end

    def self.instances_by_class_where_query(submission, class_id: nil, page_no: nil, size: nil)
      where_condition = class_id.nil? ? nil : {types: RDF::URI.new(class_id.to_s)}
      query = LinkedData::Models::Instance.where(where_condition).in(submission).include(:types, :label, :prefLabel)
      query.page(page_no, size) unless page_no.nil?
      query
    end

    def self.load_unmapped(submission, models)
      LinkedData::Models::Instance.where.in(submission).models(models).include(:unmapped).all
    end


  end
end