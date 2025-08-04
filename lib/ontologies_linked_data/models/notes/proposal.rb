require 'ontologies_linked_data/models/notes/proposal_type'

module LinkedData
  module Models
    module Notes
      class Proposal < LinkedData::Models::Base

        TYPE_ATTRIBUTE_MAP = {
          :default => [:type, :contactInfo, :reasonForChange],
          "ProposalChangeHierarchy" => [:newTarget, :oldTarget, :newRelationshipType],
          "ProposalChangeProperty" => [:propertyId, :newValue, :oldValue],
          "ProposalNewClass" => [:classId, :label, :synonym, :definition, :parent]
        }

        model :base, name_with: lambda { |inst| uuid_uri_generator(inst) }
        attribute :type, enforce: [LinkedData::Models::Notes::ProposalType, :existence]
        attribute :contactInfo, enforce: [:safe_text_256]
        attribute :reasonForChange, enforce: [:existence, :safe_text_256]

        # ProposalChangeHierarchy
        attribute :newTarget, enforce: [lambda {|inst, attr| existence(inst, attr, "ProposalChangeHierarchy")}]
        attribute :oldTarget
        attribute :newRelationshipType, enforce: [:list]

        # ProposalChangeProperty
        attribute :propertyId, enforce: [lambda {|inst, attr| existence(inst, attr, "ProposalChangeProperty")}]
        attribute :newValue, enforce: [lambda {|inst, attr| existence(inst, attr, "ProposalChangeProperty")}]
        attribute :oldValue

        # ProposalNewClass
        attribute :classId
        attribute :label, enforce: [lambda {|inst, attr| existence(inst, attr, "ProposalNewClass")}]
        attribute :synonym, enforce: [:list]
        attribute :definition, enforce: [:list]
        attribute :parent

        serialize_filter lambda {|inst| default_attributes_per_type(inst)}
        embedded true
        embed_values type: [:type]

        def self.default_attributes_per_type(inst)
          # This could get called when we have an instance (serialization)
          # or when we are asking which attributes to load (controller)
          # Try to figure out which and when there is no instance, return everything for load.
          if inst.respond_to?(:type)
            return TYPE_ATTRIBUTE_MAP[:default] + TYPE_ATTRIBUTE_MAP[inst.type.type]
          else
            return attributes
          end
        end

        def self.existence(instance, attribute, type)
          instance.type.bring(:type) if instance.type.bring?(:type)
          if instance.type.type.eql?(type)
            return :existence, "`#{attribute}` value cannot be nil" if instance.send(attribute).nil?
          end
          return nil, nil
        end
      end
    end
  end
end
