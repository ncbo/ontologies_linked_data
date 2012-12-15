module LinkedData
  module Models
    class SubmissionStatus < LinkedData::Models::Base
      attribute :code, :unique => true
       attribute :submissions, 
              :inverse_of => { :with => :ontology_submission , 
              :attribute => :status }

      def self.init(values = ["UPLOADED", "RDF", "INDEXED", "READY", "ERROR_RDF", "ERROR_INDEX"])
        values.each do |code|
          of =  LinkedData::Models::SubmissionStatus.new( { :code => code } )
          if not of.exist?
            of.save
          end
        end
      end
    end
  end
end

