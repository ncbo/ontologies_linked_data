require 'ontologies_linked_data/models/group'

module LinkedData::Models
  class Slice < LinkedData::Models::Base
    model :slice, name_with: :acronym
    attribute :acronym, enforce: [:unique, :existence, lambda {|inst,attr| validate_acronym(inst, attr)}]
    attribute :name, enforce: [:existence]
    attribute :description
    attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
    attribute :ontologies, enforce: [:existence, :list, :ontology]

    system_controlled :created

    cache_timeout 3600

    def self.validate_acronym(inst, attr)
      inst.bring(attr) if inst.bring?(attr)
      acronym = inst.send(attr)

      return [] if acronym.nil?

      errors = []

      if acronym.match(/\A[^a-z^A-Z]{1}/)
        errors << [:start_with_letter, "`acronym` must start with a letter"]
      end

      if acronym.match(/[^-0-9a-zA-Z]/)
        errors << [:special_characters, "`acronym` must only contain the folowing characters: -, letters, and numbers"]
      end

      if acronym.match(/.{17,}/)
        errors << [:length, "`acronym` must be sixteen characters or less"]
      end

      return errors.flatten
    end

    # Check to make sure each group has a corresponding slice (and ontologies match)
    def self.synchronize_groups_to_slices
      groups = LinkedData::Models::Group.where.include(LinkedData::Models::Group.attributes(:all)).all
      groups.each do |g|
        slice = self.find(g.acronym.downcase.gsub(" ", "_")).include(LinkedData::Models::Slice.attributes(:all)).first
        if slice
          slice.ontologies = g.ontologies
          slice.save if slice.valid?
        else
          slice = self.new({
            acronym: g.acronym.downcase.gsub(" ", "-"),
            name: g.name,
            description: g.description,
            ontologies: g.ontologies
          })
          slice.save
        end
      end
    end

    def ontology_id_set
      @ontology_set ||= Set.new(self.ontologies.map {|o| o.id.to_s})
    end
  end
end
