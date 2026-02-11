module LinkedData
  module Models
    class Metric < LinkedData::Models::Base
      model :metrics, name_with: lambda { |m| metrics_id_generator(m) }
      attribute :submission, inverse: { on: :ontology_submission,
                                     attribute: :metrics }

      attribute :created, enforce: [:date_time],
                :default => lambda { |record| DateTime.now }

      attribute :classes, enforce: [:integer,:existence]
      attribute :individuals, enforce: [:integer,:existence]
      attribute :properties, enforce: [:integer,:existence]
      attribute :maxDepth, enforce: [:integer,:existence]
      attribute :maxChildCount, enforce: [:integer,:existence]
      attribute :averageChildCount, enforce: [:integer,:existence]
      attribute :classesWithOneChild, enforce: [:integer,:existence]
      attribute :classesWithMoreThan25Children, enforce: [:integer,:existence]
      attribute :classesWithNoDefinition, enforce: [:integer,:existence]

      cache_timeout 14400 # 4 hours

      # Hypermedia links
      links_load submission: [:submissionId, ontology: [:acronym]]
      link_to LinkedData::Hypermedia::Link.new("ontology", lambda {|m| "#{self.ontology_submission_links(m)[:ont]}"}, Goo.vocabulary["Ontology"]),
              LinkedData::Hypermedia::Link.new("submission", lambda {|m| "#{self.ontology_submission_links(m)[:ont]}#{ontology_submission_links(m)[:sub]}"}, Goo.vocabulary["OntologySubmission"])

      def self.ontology_submission_links(m)
        acronym_link = ""
        submission_link = ""

        if m.class == self
          m.bring(:submission) if m.bring?(:submission)

          begin
            m.submission.first.bring(:ontology) if m.submission.first.bring?(:ontology)
            ont = m.submission.first.ontology
            ont.bring(:acronym) if ont.bring?(:acronym)
            acronym_link = "ontologies/#{ont.acronym}"
            submission_link = "/submissions/#{m.submission.first.submissionId}"
          rescue Exception => e
            acronym_link = ""
            submission_link = ""
          end
        end

        {ont: acronym_link, sub: submission_link}
      end

      def self.metrics_id_generator(m)
        raise ArgumentError, "Metrics id needs to be set"
        #return RDF::URI.new(m.submission.id.to_s + "/metrics")
      end

      def embedded_doc
        doc = indexable_object
        doc.delete(:resource_model)
        doc.delete(:resource_id)
        doc.delete(:id)
        doc
      end
    end
  end
end
