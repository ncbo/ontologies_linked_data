module LinkedData
  module Concerns
    module OntologySubmission
      module MetadataExtractor

        def extract_metadata(logger, user_params)

          version_info = extract_version
          ontology_iri = extract_ontology_iri

          self.version = version_info if version_info
          self.uri = ontology_iri if ontology_iri

          begin
            # Extract metadata directly from the ontology
            extract_ontology_metadata(logger, user_params)
            logger.info('Additional metadata extracted.')
          rescue StandardError => e
            e.backtrace
            logger.error("Error while extracting additional metadata: #{e}")
          end

          begin
            # Set default metadata
            set_default_metadata(logger)
            logger.info('Default metadata set.')
          rescue StandardError => e
            logger.error("Error while setting default metadata: #{e}")
          end



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


        private

        # Extract additional metadata about the ontology
        # First it extracts the main metadata, then the mapped metadata
        def extract_ontology_metadata(logger, user_params)
          user_params = {} if user_params.nil?
          ontology_uri = self.uri
          logger.info("Extraction metadata from ontology #{ontology_uri}")


          # go through all OntologySubmission attributes. Returns symbols
          LinkedData::Models::OntologySubmission.attributes(:all).each do |attr|
            # for attribute with the :extractedMetadata setting on, and that have not been defined by the user
            if (LinkedData::Models::OntologySubmission.attribute_settings(attr)[:extractedMetadata]) && !(user_params.has_key?(attr) && !user_params[attr].nil? && !user_params[attr].empty?)
              # a boolean to check if a value that should be single have already been extracted
              single_extracted = false

              if !LinkedData::Models::OntologySubmission.attribute_settings(attr)[:namespace].nil?
                property_to_extract = LinkedData::Models::OntologySubmission.attribute_settings(attr)[:namespace].to_s + ':' + attr.to_s
                hash_results = extract_each_metadata(ontology_uri, attr, property_to_extract, logger)

                if (LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:list))
                  # Add the retrieved value(s) to the attribute if the attribute take a list of objects
                  if self.send(attr.to_s).nil?
                    metadata_values = []
                  else
                    metadata_values = self.send(attr.to_s).dup
                  end
                  hash_results.each do |k,v|
                    metadata_values.push(v)
                  end
                  self.send("#{attr.to_s}=", metadata_values)
                elsif (LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:concatenate))
                  # don't keep value from previous submissions for concats
                  metadata_concat = []
                  # if multiple value for this attribute, then we concatenate it. And it's send to the attr after getting all metadataMappings
                  hash_results.each do |k,v|
                    metadata_concat << v.to_s
                  end
                else
                  # If multiple value for a metadata that should have a single value: taking one value randomly (the first in the hash)
                  hash_results.each do |k,v|
                    single_extracted = true
                    self.send("#{attr.to_s}=", v)
                    break
                  end
                end
              end

              # extracts attribute value from metadata mappings
              if !LinkedData::Models::OntologySubmission.attribute_settings(attr)[:metadataMappings].nil?

                LinkedData::Models::OntologySubmission.attribute_settings(attr)[:metadataMappings].each do |mapping|
                  if single_extracted == true
                    # if an attribute with only one possible object as already been extracted
                    break
                  end
                  hash_mapping_results = extract_each_metadata(ontology_uri, attr, mapping.to_s, logger)

                  if (LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:list))
                    # Add the retrieved value(s) to the attribute if the attribute take a list of objects
                    if self.send(attr.to_s).nil?
                      metadata_values = []
                    else
                      metadata_values = self.send(attr.to_s).dup
                    end
                    hash_mapping_results.each do |k,v|
                      metadata_values.push(v)
                    end
                    self.send("#{attr.to_s}=", metadata_values)
                  elsif (LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:concatenate))
                    # if multiple value for this attribute, then we concatenate it
                    hash_mapping_results.each do |k,v|
                      metadata_concat << v.to_s
                    end
                  else
                    # If multiple value for a metadata that should have a single value: taking one value randomly (the first in the hash)
                    hash_mapping_results.each do |k,v|
                      self.send("#{attr.to_s}=", v)
                      break
                    end
                  end
                end
              end

              # Add the concat at the very end, to easily join the content of the array
              if (LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:concatenate))
                if !metadata_concat.empty?
                  self.send("#{attr.to_s}=", metadata_concat.join(', '))
                end
              end
            end
          end

        end

        # Set some metadata to default values if nothing extracted
        def set_default_metadata(logger)
          if self.identifier.nil?
            self.identifier = self.uri.to_s
          end

          if self.deprecated.nil?
            if self.status.eql?('retired')
              self.deprecated = true
            else
              self.deprecated = false
            end
          end

          # Add the ontology hasDomain to the submission hasDomain metadata value
          ontology_domain_list = []
          self.ontology.bring(:hasDomain).hasDomain.each do |domain|
            ontology_domain_list << domain.id
          end
          if (ontology_domain_list.length > 0 && self.hasDomain.nil?)
            self.hasDomain = ''
          end
          if !self.hasDomain.nil?
            self.hasDomain << ontology_domain_list.join(', ')
          end

          # Only get the first view because the attribute is not a list
          ontology_view = self.ontology.bring(:views).views.first
          if (self.hasPart.nil? && !ontology_view.nil?)
            self.hasPart = ontology_view.id
          end

          # If no example identifier extracted: take the first class
          if self.exampleIdentifier.nil?
            self.exampleIdentifier = LinkedData::Models::Class.in(self).first.id
          end

          # Metadata specific to BioPortal that have been removed:
          #if self.hostedBy.nil?
          #  self.hostedBy = [ RDF::URI.new("http://#{LinkedData.settings.ui_host}") ]
          #end

          # Add the search endpoint URL
          if self.openSearchDescription.nil?
            self.openSearchDescription = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}search?ontologies=#{self.ontology.acronym}&q=")
          end

          # Search allow to search by URI too
          if self.uriLookupEndpoint.nil?
            self.uriLookupEndpoint = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}search?ontologies=#{self.ontology.acronym}&require_exact_match=true&q=")
          end

          # Add the dataDump URL
          if self.dataDump.nil?
            self.dataDump = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{self.ontology.acronym}/download?download_format=rdf")
          end

          if self.csvDump.nil?
            self.csvDump = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{self.ontology.acronym}/download?download_format=csv")
          end

          # Add the previous submission as a prior version
          if self.submissionId > 1
=begin
          if prior_versions.nil?
            prior_versions = []
          else
            prior_versions = self.hasPriorVersion.dup
          end
          prior_versions.push(RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{self.ontology.acronym}/submissions/#{self.submissionId - 1}"))
          self.hasPriorVersion = prior_versions
=end
            self.hasPriorVersion = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{self.ontology.acronym}/submissions/#{self.submissionId - 1}")
          end

          if self.hasOntologyLanguage.umls?
            self.hasOntologySyntax = 'http://www.w3.org/ns/formats/Turtle'
          elsif self.hasOntologyLanguage.obo?
            self.hasOntologySyntax = 'http://purl.obolibrary.org/obo/oboformat/spec.html'
          end

          # Define default properties for prefLabel, synonyms, definition, author:
          if self.hasOntologyLanguage.owl?
            if self.prefLabelProperty.nil?
              self.prefLabelProperty = Goo.vocabulary(:skos)[:prefLabel]
            end
            if self.synonymProperty.nil?
              self.synonymProperty = Goo.vocabulary(:skos)[:altLabel]
            end
            if self.definitionProperty.nil?
              self.definitionProperty = Goo.vocabulary(:rdfs)[:comment]
            end
            if self.authorProperty.nil?
              self.authorProperty = Goo.vocabulary(:dc)[:creator]
            end
            # Add also hierarchyProperty? Could not find any use of it
          end

          # Add the sparql endpoint URL
          if self.endpoint.nil? && LinkedData.settings.sparql_endpoint_url
            self.endpoint = RDF::URI.new(LinkedData.settings.sparql_endpoint_url)
          end

        end

        # Return a hash with the best literal value for an URI
        # it selects the literal according to their language: no language > english > french > other languages
        def select_metadata_literal(metadata_uri, metadata_literal, hash)
          if metadata_literal.is_a?(RDF::Literal)
            if hash.has_key?(metadata_uri)
              if metadata_literal.has_language?
                if !hash[metadata_uri].has_language?
                  return hash
                else
                  if metadata_literal.language == :en || metadata_literal.language == :eng
                    # Take the value with english language over other languages
                    hash[metadata_uri] = metadata_literal
                    return hash
                  elsif metadata_literal.language == :fr || metadata_literal.language == :fre
                    # If no english, take french
                    if hash[metadata_uri].language == :en || hash[metadata_uri].language == :eng
                      return hash
                    else
                      hash[metadata_uri] = metadata_literal
                      return hash
                    end
                  else
                    return hash
                  end
                end
              else
                # Take the value with no language in priority (considered as a default)
                hash[metadata_uri] = metadata_literal
                return hash
              end
            else
              hash[metadata_uri] = metadata_literal
              return hash
            end
          end
        end


        # A function to extract additional metadata
        # Take the literal data if the property is pointing to a literal
        # If pointing to an URI: first it takes the "omv:name" of the object pointed by the property, if nil it takes the "rdfs:label".
        # If not found it check for "omv:firstName + omv:lastName" (for "omv:Person") of this object. And to finish it takes the "URI"
        # The hash_results contains the metadataUri (objet pointed on by the metadata property) with the value we are using from it
        def extract_each_metadata(ontology_uri, attr, prop_to_extract, logger)

          query_metadata = <<eos

SELECT DISTINCT ?extractedObject ?omvname ?omvfirstname ?omvlastname ?rdfslabel
FROM #{self.id.to_ntriples}
WHERE {
  <#{ontology_uri}> #{prop_to_extract} ?extractedObject .
  OPTIONAL { ?extractedObject omv:name ?omvname } .
  OPTIONAL { ?extractedObject omv:firstName ?omvfirstname } .
  OPTIONAL { ?extractedObject omv:lastName ?omvlastname } .
  OPTIONAL { ?extractedObject rdfs:label ?rdfslabel } .
}
eos
          Goo.namespaces.each do |prefix,uri|
            query_metadata = "PREFIX #{prefix}: <#{uri}>\n" + query_metadata
          end

          #logger.info(query_metadata)
          # This hash will contain the "literal" metadata for each object (uri or literal) pointed by the metadata predicate
          hash_results = {}
          Goo.sparql_query_client.query(query_metadata).each_solution do |sol|

            if LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:uri)
              # If the attr is enforced as URI then it directly takes the URI
              if sol[:extractedObject].is_a?(RDF::URI)
                hash_results[sol[:extractedObject]] = sol[:extractedObject]
              end

            elsif LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:date_time)
              begin
                hash_results[sol[:extractedObject]] = DateTime.iso8601(sol[:extractedObject].to_s)
              rescue StandardError => e
                logger.error("Impossible to extract DateTime metadata for #{attr.to_s}: #{sol[:extractedObject].to_s}. It should follow iso8601 standards. Error message: #{e}")
              end

            elsif LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:integer)
              begin
                hash_results[sol[:extractedObject]] = sol[:extractedObject].to_s.to_i
              rescue StandardError => e
                logger.error("Impossible to extract integer metadata for #{attr.to_s}: #{sol[:extractedObject].to_s}. Error message: #{e}")
              end

            elsif LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:boolean)
              begin
                if (sol[:extractedObject].to_s.downcase.eql?('true'))
                  hash_results[sol[:extractedObject]] = true
                elsif (sol[:extractedObject].to_s.downcase.eql?('false'))
                  hash_results[sol[:extractedObject]] = false
                end
              rescue StandardError => e
                logger.error("Impossible to extract boolean metadata for #{attr.to_s}: #{sol[:extractedObject].to_s}. Error message: #{e}")
              end

            else
              if sol[:extractedObject].is_a?(RDF::URI)
                # if the object is an URI but we are requesting a String
                # TODO: ATTENTION on veut pas forcément TOUT le temps recump omvname, etc... Voir si on change ce comportement
                if !sol[:omvname].nil?
                  hash_results = select_metadata_literal(sol[:extractedObject],sol[:omvname], hash_results)
                elsif !sol[:rdfslabel].nil?
                  hash_results = select_metadata_literal(sol[:extractedObject],sol[:rdfslabel], hash_results)
                elsif !sol[:omvfirstname].nil?
                  hash_results = select_metadata_literal(sol[:extractedObject],sol[:omvfirstname], hash_results)
                  # if first and last name are defined (for omv:Person)
                  if !sol[:omvlastname].nil?
                    hash_results[sol[:extractedObject]] = hash_results[sol[:extractedObject]].to_s + ' ' + sol[:omvlastname].to_s
                  end
                elsif !sol[:omvlastname].nil?
                  # if only last name is defined
                  hash_results = select_metadata_literal(sol[:extractedObject],sol[:omvlastname], hash_results)
                else
                  hash_results[sol[:extractedObject]] = sol[:extractedObject].to_s
                end

              else
                # If this is directly a literal
                hash_results = select_metadata_literal(sol[:extractedObject],sol[:extractedObject], hash_results)
              end
            end
          end

          hash_results
        end

      end
    end
  end
end

