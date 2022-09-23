require 'ontologies_linked_data/models/group'

module LinkedData::Models
  class Slice < LinkedData::Models::Base
    model :slice, name_with: :acronym
    attribute :acronym, enforce: [:unique, :existence, lambda {|inst,attr| validate_acronym(inst, attr)}]
    attribute :name, enforce: [:existence]
    attribute :description
    attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
    attribute :ontologies, enforce: [:existence, :list, :ontology]

    cache_timeout 3600

    def self.validate_acronym(inst, attr)
      inst.bring(attr) if inst.bring?(attr)
      value = inst.send(attr)
      acronym_regex = /\A[-_a-z]+\Z/
      if (acronym_regex.match value).nil?
        return [:acronym_value_validator,"The acronym value #{value} is invalid"]
      end
      return [:acronym_value_validator, nil]
    end

    # Should synchronize the groups with the slices (creating slice if needed). But it bugs and create slices with a wrong URI
    # http://data.bioontology.org/slice/ACR instead of http://data.bioontology.org/slices/ACR
    def self.synchronize_groups_to_slices
      # Check to make sure each group has a corresponding slice (and ontologies match)
      groups = LinkedData::Models::Group.where.include(LinkedData::Models::Group.attributes(:all)).all
      groups.each do |g|
        slice = self.find(g.acronym).include(LinkedData::Models::Slice.attributes(:all)).first
        if slice
          slice.ontologies = g.ontologies
          slice.save if slice.valid?
        else
          slice = self.new({ acronym: g.acronym.downcase.gsub(" ", "_"), name: g.name, description: g.description, ontologies: g.ontologies})
          slice.save
        end
      end
    end

    def ontology_id_set
      @ontology_set ||= Set.new(self.ontologies.map {|o| o.id.to_s})
    end
  end
end
