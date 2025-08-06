require 'cgi'
require 'ontologies_linked_data/models/notes/proposal'
require 'ontologies_linked_data/models/notes/reply'

module LinkedData
  module Models
    class Note < LinkedData::Models::Base
      model :note, name_with: lambda { |inst| uuid_uri_generator(inst) }
      attribute :subject, enforce: [:safe_text_64]
      attribute :body, enforce: [:safe_text]
      attribute :creator, enforce: [:existence, :user]
      attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
      attribute :archived, enforce: [:boolean]
      attribute :createdInSubmission, enforce: [:ontology_submission]
      attribute :reply, enforce: [LinkedData::Models::Notes::Reply, :list]
      attribute :relatedOntology, enforce: [:list, :ontology, :existence]
      attribute :relatedClass, enforce: [:list, :class]
      attribute :proposal, enforce: [LinkedData::Models::Notes::Proposal]

      embed :reply, :proposal
      embed_values proposal: LinkedData::Models::Notes::Proposal.goo_attrs_to_load
      link_to LinkedData::Hypermedia::Link.new("replies", lambda {|n| "notes/#{n.id.to_s.split('/').last}/replies"}, LinkedData::Models::Notes::Reply.type_uri),
              LinkedData::Hypermedia::Link.new("ui", lambda {|n| "http://#{LinkedData.settings.ui_host}/notes/#{CGI.escape(n.id)}"}, self.type_uri)

      system_controlled :creator, :created

      # HTTP Cache settings
      cache_segment_instance lambda {|note| segment_instance(note)}
      cache_segment_keys [:note]

      def self.segment_instance(note)
        note.bring(relatedOntology: [:acronym]) unless note.loaded_attributes.include?(:relatedOntology)
        note.relatedOntology.each {|o| o.bring(:acronym) unless o.loaded_attributes.include?(:acronym)}
        [note.relatedOntology.map {|o| o.acronym}.join(":")] rescue []
      end

      def save(*args)
        super(*args)
        LinkedData::Utils::Notifications.new_note(self) rescue nil
        return self
      end

      def delete(*args)
        bring(:reply, :proposal)
        reply.each {|r| r.delete if r.exist?}
        proposal.delete if !proposal.nil? && proposal.exist?
        super(*args)
      end
    end
  end
end
