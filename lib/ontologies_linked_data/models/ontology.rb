module LinkedData
  module Models
    class Ontology < LinkedData::Models::Base
      model :ontology
      attribute :acronym, :unique => true
      attribute :submissions, 
              :inverse_of => { :with => :ontology_submission , 
              :attribute => :ontology }

      #TODO not yet supported in goo
      #https://github.com/ncbo/goo/issues/32
      #attribute :submissions, :inverse_of { :with => :ontology_submission , :attribute => :ontology }

    end
  end
end
