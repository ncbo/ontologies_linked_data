module LinkedData
  module Concerns
    module OntologySubmission
      module MetadataExtractor

        def extract_metadata
          version_info = extract_version
          ontology_iri = extract_ontology_iri

          self.version = version_info if version_info
          self.uri = ontology_iri if ontology_iri

        end

        def extract_version

          query = Goo.sparql_query_client.select(:versionInfo).distinct
                     .from(self.id)
                    .where([RDF::URI.new('http://bioportal.bioontology.org/ontologies/versionSubject'),
                            RDF::URI.new('http://www.w3.org/2002/07/owl#versionInfo'),
                            :versionInfo])

          sol = query.each_solution.first || {}
          sol[:versionInfo]&.to_s
        end

        def extract_ontology_iri
          query = Goo.sparql_query_client.select(:uri).distinct
                     .from(self.id)
                     .where([:uri,
                             RDF::URI.new('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'),
                             RDF::URI.new('http://www.w3.org/2002/07/owl#Ontology')])
          sol = query.each_solution.first || {}
          sol[:uri]&.to_s
        end
      end
    end
  end
end
