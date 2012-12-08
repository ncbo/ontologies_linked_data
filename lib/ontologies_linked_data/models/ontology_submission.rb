module LinkedData
  module Models
    class OntologySubmission < Goo::Base::Resource
      model :ontology_submission
      attribute :acronym, :unique => true
      attribute :submissionId, :unique => true, :instance_of =>  { :with => Fixnum }
      attribute :name, :cardinality => { :max => 1, :min => 1 }

      #configurable properties
      attribute :prefLabelProperty, :instance_of =>  { :with => RDF::IRI }, :single_value => true
      attribute :definitionProperty, :instance_of =>  { :with => RDF::IRI }, :single_value  => true
      attribute :synonymProperty, :instance_of =>  { :with => RDF::IRI }, :single_value  => true
      attribute :classType, :instance_of =>  { :with => RDF::IRI }, :single_value  => true
      attribute :hiearchyProperty, :instance_of =>  { :with => RDF::IRI }, :single_value  => true

      #internal values for parsing - not definitive
      attribute :repoPath,  :single_value =>true, :not_nil =>true
      attribute :masterFileName,  :single_value =>true, :not_nil =>true

      #link to ontology
      attribute :ontology, :single_value => true, :not_nil => true, :instance_of => { :with => :ontology }
    end
  end
end
