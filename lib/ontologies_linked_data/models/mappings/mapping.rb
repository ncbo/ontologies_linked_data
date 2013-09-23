require_relative '../ontology'
require_relative '../class'
require_relative './process'


module LinkedData
  module Models
    class TermMapping < LinkedData::Models::Base

      model :term_mapping, :name_with => lambda { |s| term_mapping_id_generator(s.term,s.ontology.acronym) }
      attribute :term, enforce: [ :uri, :existence , :list]
      attribute :ontology, enforce: [:existence, :ontology ]
      attribute :mappings, :inverse => { on: :mapping, attribute: :terms }

      def self.term_mapping_id_generator(term,acronym)
        term_vals=term.map { |t| t.to_s }
        term_vals.sort!
        val_to_hash = term_vals.join("-")
        hashed_value = Digest::SHA1.hexdigest(val_to_hash)
        return RDF::IRI.new(
        "#{(self.namespace)}termmapping/#{acronym}/#{hashed_value}")
      end
    end

    class Mapping < LinkedData::Models::Base
      model :mapping, :name_with => lambda { |s| mapping_id_generator(s) }
      attribute :terms, enforce: [ :term_mapping, :existence, :list ]

      #mappings can exist without process
      attribute :process, enforce: [ :mapping_process, :list ]

      # Hypermedia settings for serializer
      serialize_default :process, :classes
      serialize_never :terms
      serialize_methods :classes
      embed :process, :classes

      def self.mapping_id_generator(ins)
        return mapping_id_generator_iris(*ins.terms.map { |x| x.id })
      end

      def self.mapping_id_generator_iris(*term_ids)
        term_ids.each do |t|
          raise ArgumentError, "Terms must be URIs" if !(t.instance_of? RDF::URI)
        end
        val_to_hash = (term_ids.map{ |t| t.to_s}).sort.join("-")
        hashed_value = Digest::SHA1.hexdigest(val_to_hash)
        return RDF::IRI.new(
          "#{(self.namespace)}mapping/#{hashed_value}")
      end

      def classes
        submissions = {}
        classes = []
        terms.each do |term_mapping|
          term_mapping.term.each do |term|
            unless submissions[term_mapping.ontology]
              ont = term_mapping.ontology
              submission = LinkedData::Models::OntologySubmission.read_only(id: ont.id.to_s + "/latest_submission", ontology: ont)
              submissions[term_mapping.ontology] = submission
            end
            cls = LinkedData::Models::Class.read_only(id: term, submission: submissions[term_mapping.ontology])
            classes << cls
          end
        end
        classes
      end
    end
  end
end
