module LinkedData
  module Models
    class Ontology < Goo::Base::Resource
      model :ontology
      attribute :acronym, :unique => true

      #TODO not yet supported in goo
      #https://github.com/ncbo/goo/issues/32
      #attribute :submissions, :inverse_of { :with => :ontology_submission , :attribute => :ontology }

    end
  end
end
