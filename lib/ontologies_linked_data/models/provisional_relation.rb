module LinkedData
  module Models
    class ProvisionalRelation < LinkedData::Models::Base
      model :provisional_relation, name_with: lambda { |inst| uuid_uri_generator(inst) }

      attribute :source, enforce: [:existence, :provisional_class]
      attribute :relationType, enforce: [:existence, :uri]
      attribute :targetClassId, enforce: [:existence, :uri]
      attribute :targetClassOntology, enforce: [:existence, :ontology]
      attribute :creator, enforce: [:existence, :user]
      attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }

      system_controlled :creator, :created

      def self.find_unique(source_id, relation_type, target_class_id, target_ont_id_or_acronym)
        source_id = RDF::URI.new(source_id) unless source_id.is_a?(RDF::URI)
        relation_type = RDF::URI.new(relation_type) unless relation_type.is_a?(RDF::URI)
        target_class_id = RDF::URI.new(target_class_id) unless target_class_id.is_a?(RDF::URI)
        LinkedData::Models::ProvisionalRelation.where(
            source: source_id, relationType: relation_type, targetClassId: target_class_id,
            targetClassOntology: target_ont_id_or_acronym).first
      end

      def target_class
        self.bring(:targetClassId) if self.bring?(:targetClassId)
        self.bring(targetClassOntology: [:acronym]) if self.bring?(:targetClassOntology)
        sub = self.targetClassOntology.latest_submission
        LinkedData::Models::Class.find(self.targetClassId).in(sub).first
      end

      def ==(that)
        self.bring(:source) if self.bring?(:source)
        that.bring(:source) if that.bring?(:source)
        self.bring(:relationType) if self.bring?(:relationType)
        that.bring(:relationType) if that.bring?(:relationType)
        self.bring(:targetClassId) if self.bring?(:targetClassId)
        that.bring(:targetClassId) if that.bring?(:targetClassId)
        self.bring(targetClassOntology: [:acronym]) if self.bring?(:targetClassOntology)
        that.bring(targetClassOntology: [:acronym]) if that.bring?(:targetClassOntology)

        self.source.id == that.source.id &&
            self.relationType == that.relationType &&
            self.targetClassId == that.targetClassId &&
            self.targetClassOntology.acronym == that.targetClassOntology.acronym
      end

      def valid?
        valid_result = super

        if valid_result
          self.bring(:targetClassOntology) if self.bring?(:targetClassOntology)
          sub = self.targetClassOntology.latest_submission

          if sub.nil?
            self.errors[:targetClassOntology] = {existence: "No processed submission found for ontology #{self.targetClassOntology.id}. A provisional relation must refer to a class in an existing processed ontology submission."}
            valid_result = false
          else
            cls = self.target_class

            if cls.nil?
              self.errors[:targetClassId] = {existence: "Class with id #{self.targetClassId} in ontology #{self.targetClassOntology.id} was not found."}
              valid_result = false
            end
          end
        end
        valid_result
      end

    end
  end
end
