module LinkedData
  module Concerns
    module OntologySubmission
      module MetadataExtractor

        def extract_metadata(logger = nil, heavy_extraction = true, user_params = nil)
          logger ||= Logger.new(STDOUT)
          logger.info('Extracting metadata from the ontology submission.')

          @submission = self
          version_info = extract_version
          ontology_iri = extract_ontology_iri
          @submission.version = version_info if version_info
          @submission.uri = ontology_iri if ontology_iri
          @submission.save

          if heavy_extraction
            begin
              # Extract metadata directly from the ontology
              extract_ontology_metadata(logger, user_params, skip_attrs: [:version, :uri])
              logger.info('Additional metadata extracted.')
            rescue StandardError => e
              e.backtrace
              logger.error("Error while extracting additional metadata: #{e}")
            end
          end

          if @submission.valid?
            @submission.save
          else
            logger.error("Error while extracting additional metadata: #{@submission.errors}")
            @submission = LinkedData::Models::OntologySubmission.find(@submission.id).first.bring_remaining
          end
        end

        def extract_version

          query = Goo.sparql_query_client.select(:versionInfo).distinct
                     .from(@submission.id)
                     .where([RDF::URI.new('http://bioportal.bioontology.org/ontologies/versionSubject'),
                             RDF::URI.new('http://www.w3.org/2002/07/owl#versionInfo'),
                             :versionInfo])

          sol = query.each_solution.first || {}
          sol[:versionInfo]&.to_s
        end

        def extract_ontology_iri
          query = Goo.sparql_query_client.select(:uri).distinct
                     .from(@submission.id)
                     .where([:uri,
                             RDF::URI.new('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'),
                             RDF::URI.new('http://www.w3.org/2002/07/owl#Ontology')])
          sol = query.each_solution.first || {}
          RDF::URI.new(sol[:uri]) if sol[:uri]
        end

        # Extract additional metadata about the ontology
        # First it extracts the main metadata, then the mapped metadata
        def extract_ontology_metadata(logger, user_params, skip_attrs: [])
          user_params = {} if user_params.nil? || !user_params
          ontology_uri = @submission.uri
          logger.info("Extraction metadata from ontology #{ontology_uri}")

          # go through all OntologySubmission attributes. Returns symbols
          LinkedData::Models::OntologySubmission.attributes(:all).each do |attr|
            next if skip_attrs.include? attr
            # for attribute with the :extractedMetadata setting on, and that have not been defined by the user
            attr_settings = LinkedData::Models::OntologySubmission.attribute_settings(attr)

            attr_not_excluded = user_params && !(user_params.key?(attr) && !user_params[attr].nil? && !user_params[attr].empty?)

            next unless attr_settings[:extractedMetadata] && attr_not_excluded

            # a boolean to check if a value that should be single have already been extracted
            single_extracted = false
            type = enforce?(attr, :list) ? :list : :string
            old_value = value(attr, type)

            unless attr_settings[:namespace].nil?
              property_to_extract = "#{attr_settings[:namespace].to_s}:#{attr.to_s}"
              hash_results = extract_each_metadata(ontology_uri, attr, property_to_extract, logger)
              single_extracted = send_value(attr, hash_results, logger) unless hash_results.empty?
            end

            # extracts attribute value from metadata mappings
            attr_settings[:metadataMappings] ||= []

            attr_settings[:metadataMappings].each do |mapping|
              break if single_extracted

              hash_mapping_results = extract_each_metadata(ontology_uri, attr, mapping.to_s, logger)
              single_extracted = send_value(attr, hash_mapping_results, logger) unless hash_mapping_results.empty?
            end

            new_value = value(attr, type)

            send_value(attr, old_value, logger) if empty_value?(new_value) && !empty_value?(old_value)
          end
        end

        def empty_value?(value)
          value.nil? || (value.is_a?(Array) && value.empty?) || value.to_s.strip.empty?
        end

        def value(attr, type)
          val = @submission.send(attr.to_s)
          type.eql?(:list) ? Array(val) || [] : val || ''
        end

        def send_value(attr, new_value, logger)
          old_val = nil
          single_extracted = false

          if enforce?(attr, :list)
            old_val = value(attr, :list)
            old_values = old_val.dup
            new_values = new_value.values
            new_values = new_values.map { |v| find_or_create_agent(attr, v, logger) }.compact if enforce?(attr, :Agent)

            old_values.push(*new_values)

            @submission.send("#{attr}=", old_values.uniq)
          elsif enforce?(attr, :concatenate)
            # if multiple value for this attribute, then we concatenate it
            # Add the concat at the very end, to easily join the content of the array
            old_val = value(attr, :string)
            metadata_values = old_val.split(', ')
            new_values = new_value.values.map { |x| x.to_s.split(', ') }.flatten

            @submission.send("#{attr}=", (metadata_values + new_values).uniq.join(', '))
          else
            new_value = new_value.values.first

            new_value = find_or_create_agent(attr, nil, logger) if enforce?(attr, :Agent)

            @submission.send("#{attr}=", new_value)
            single_extracted = true
          end

          unless @submission.valid?
            logger.error("Error while extracting metadata for the attribute #{attr}: #{@submission.errors[attr] || @submission.errors}")
            new_value&.delete if enforce?(attr, :Agent) && new_value.respond_to?(:delete)
            @submission.send("#{attr}=", old_val)
          end

          single_extracted
        end

        # Return a hash with the best literal value for an URI
        # it selects the literal according to their language: no language > english > french > other languages
        def select_metadata_literal(metadata_uri, metadata_literal, hash)
          return unless metadata_literal.is_a?(RDF::Literal)

          if hash.key?(metadata_uri)
            if metadata_literal.has_language?
              if !hash[metadata_uri].has_language?
                return hash
              else
                case metadata_literal.language
                when :en, :eng
                  # Take the value with english language over other languages
                  hash[metadata_uri] = metadata_literal
                  return hash
                when :fr, :fre
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
            hash
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
FROM #{@submission.id.to_ntriples}
WHERE {
  <#{ontology_uri}> #{prop_to_extract} ?extractedObject .
  OPTIONAL { ?extractedObject omv:name ?omvname } .
  OPTIONAL { ?extractedObject omv:firstName ?omvfirstname } .
  OPTIONAL { ?extractedObject omv:lastName ?omvlastname } .
  OPTIONAL { ?extractedObject rdfs:label ?rdfslabel } .
}
eos
          Goo.namespaces.each do |prefix, uri|
            query_metadata = "PREFIX #{prefix}: <#{uri}>\n" + query_metadata
          end

          # logger.info(query_metadata)
          # This hash will contain the "literal" metadata for each object (uri or literal) pointed by the metadata predicate
          hash_results = {}
          Goo.sparql_query_client.query(query_metadata).each_solution do |sol|
            value = sol[:extractedObject]
            if enforce?(attr, :uri)
              # If the attr is enforced as URI then it directly takes the URI
              uri_value = value ? RDF::URI.new(value.to_s.strip) : nil
              hash_results[value] = uri_value if uri_value&.valid?
            elsif enforce?(attr, :date_time)
              begin
                hash_results[value] = DateTime.iso8601(value.to_s)
              rescue StandardError => e
                logger.error("Impossible to extract DateTime metadata for #{attr}: #{value}. It should follow iso8601 standards. Error message: #{e}")
              end
            elsif enforce?(attr, :integer)
              begin
                hash_results[value] = value.to_s.to_i
              rescue StandardError => e
                logger.error("Impossible to extract integer metadata for #{attr}: #{value}. Error message: #{e}")
              end
            elsif enforce?(attr, :boolean)
              case value.to_s.downcase
              when 'true'
                hash_results[value] = true
              when 'false'
                hash_results[value] = false
              else
                logger.error("Impossible to extract boolean metadata for #{attr}: #{value}. Error message: #{e}")
              end
            elsif value.is_a?(RDF::URI)
              hash_results = find_object_label(hash_results, sol, value)
            else
              # If this is directly a literal
              hash_results = select_metadata_literal(value, value, hash_results)
            end
          end
          hash_results
        end

        def find_object_label(hash_results, sol, value)
          if !sol[:omvname].nil?
            hash_results = select_metadata_literal(value, sol[:omvname], hash_results)
          elsif !sol[:rdfslabel].nil?
            hash_results = select_metadata_literal(value, sol[:rdfslabel], hash_results)
          elsif !sol[:omvfirstname].nil?
            hash_results = select_metadata_literal(value, sol[:omvfirstname], hash_results)
            # if first and last name are defined (for omv:Person)
            hash_results[value] = "#{hash_results[value]} #{sol[:omvlastname]}" unless sol[:omvlastname].nil?
          elsif !sol[:omvlastname].nil?
            # if only last name is defined
            hash_results = select_metadata_literal(value, sol[:omvlastname], hash_results)
          else
            # if the object is an URI but we are requesting a String
            hash_results[value] = value.to_s
          end
          hash_results
        end

        def enforce?(attr, type)
          LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(type)
        end

        def find_or_create_agent(attr, old_val, logger)
          agent = LinkedData::Models::Agent.where(agentType: 'person', name: old_val).first
          begin
            agent ||= LinkedData::Models::Agent.new(name: old_val, agentType: 'person', creator: @submission.ontology.administeredBy.first).save
          rescue
            logger.error("Error while extracting metadata for the attribute #{attr}: Can't create Agent #{agent.errors} ")
            agent = nil
          end
          agent
        end
      end
    end
  end
end
