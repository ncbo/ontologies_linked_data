require 'rdf/raptor'

module LinkedData
  module Models

    class Resource

      def initialize(graph, id)
        @id = id
        @graph = graph
        @hash = fetch_related_triples(graph, id)
      end

      def to_hash
        @hash.dup
      end

      def to_object
        hashes = self.to_hash
        class_name = "GeneratedModel_#{Time.now.to_i}_#{rand(10000..99999)}"
        model_schema = ::Class.new(LinkedData::Models::Base)
        Object.const_set(class_name, model_schema)

        model_schema.model(:resource, name_with: :id, rdf_type: lambda { |*_x| self.to_hash[Goo.namespaces[:rdf][:type].to_s] })
        values_hash = {}
        hashes.each do |predicate, value|
          namespace, attr = namespace_predicate(predicate)
          next if namespace.nil?

          values = Array(value).map do |v|
            if v.is_a?(Hash)
              Struct.new(*v.keys.map { |k| namespace_predicate(k)[1].to_sym }.compact).new(*v.values)
            else
              v.is_a?(RDF::URI) ? v.to_s : v.object
            end
          end.compact

          model_schema.attribute(attr.to_sym, property: namespace.to_s, enforce: get_type(value))
          values_hash[attr.to_sym] = value.is_a?(Array) ? values : values.first
        end

        values_hash[:id] = hashes['id']
        model_schema.new(values_hash)
      end

      def to_json
        LinkedData::Serializers.serialize(to_hash, LinkedData::MediaTypes::JSONLD, namespaces)
      end

      def to_xml
        LinkedData::Serializers.serialize(to_hash, LinkedData::MediaTypes::RDF_XML, namespaces)
      end

      def to_ntriples
        LinkedData::Serializers.serialize(to_hash, LinkedData::MediaTypes::NTRIPLES, namespaces)
      end

      def to_turtle
        LinkedData::Serializers.serialize(to_hash, LinkedData::MediaTypes::TURTLE, namespaces)
      end

      def namespaces
        prefixes = {}
        ns_count = 0
        hash = to_hash
        reverse = hash.delete('reverse')

        hash.each do |key, value|
          uris = [key]
          uris += Array(value).map { |v| v.is_a?(Hash) ? v.to_a.flatten : v }.flatten
          prefixes, ns_count = transform_to_prefixes(ns_count, prefixes, uris)
        end

        reverse.each { |key, uris| prefixes, ns_count = transform_to_prefixes(ns_count, prefixes, [key] + Array(uris)) }

        prefixes
      end

      private

      def transform_to_prefixes(ns_count, prefixes, uris)
        uris.each do |uri|
          namespace, _ = namespace_predicate(uri)
          next if namespace.nil? || prefixes.value?(namespace)

          prefix, prefix_namespace = Goo.namespaces.select { |_k, v| v.to_s.eql?(namespace) }.first
          if prefix
            prefixes[prefix] = prefix_namespace.to_s
          else
            prefixes["ns#{ns_count}".to_sym] = namespace
            ns_count += 1
          end
        end
        [prefixes, ns_count]
      end

      def fetch_related_triples(graph, id)
        direct_fetch_query = Goo.sparql_query_client.select(:predicate, :object)
                                .from(RDF::URI.new(graph))
                                .where([RDF::URI.new(id), :predicate, :object])

        inverse_fetch_query = Goo.sparql_query_client.select(:subject, :predicate)
                                 .from(RDF::URI.new(graph))
                                 .where([:subject, :predicate, RDF::URI.new(id)])

        hashes = { 'id' => RDF::URI.new(id) }

        direct_fetch_query.each_solution do |solution|
          predicate = solution[:predicate].to_s
          value = solution[:object]

          if value.is_a?(RDF::Node) && Array(hashes[predicate]).none? { |x| x.is_a?(Hash) }
            value = fetch_b_nodes_triples(graph, id, solution[:predicate])
          elsif value.is_a?(RDF::Node)
            next
          end

          hashes[predicate] = hashes[predicate] ? (Array(hashes[predicate]) + Array(value)) : value
        end

        hashes['reverse'] = {}
        inverse_fetch_query.each_solution do |solution|
          subject = solution[:subject].to_s
          predicate = solution[:predicate]

          if hashes['reverse'][subject]
            if hashes['reverse'][subject].is_a?(Array)
              hashes['reverse'][subject] << predicate
            else
              hashes['reverse'][subject] = [predicate, hashes['reverse'][subject]]
            end
          else
            hashes['reverse'][subject] = predicate
          end

        end

        hashes
      end

      def fetch_b_nodes_triples(graph, id, predicate)
        b_node_fetch_query = Goo.sparql_query_client.select(:b, :predicate, :object)
                                .from(RDF::URI.new(graph))
                                .where(
                                  [RDF::URI.new(id), predicate, :b],
                                  %i[b predicate object]
                                )

        b_nodes_hash = {}
        b_node_fetch_query.each_solution do |s|
          b_node_id = s[:b].to_s
          s[:predicate].to_s
          s[:object]
          if b_nodes_hash[b_node_id]
            b_nodes_hash[b_node_id][s[:predicate].to_s] = s[:object]
          else
            b_nodes_hash[b_node_id] = { s[:predicate].to_s => s[:object] }
          end
        end
        b_nodes_hash.values
      end

      def get_type(value)
        types = []
        types << :list if value.is_a?(Array)
        value = Array(value).first
        if value.is_a?(RDF::URI)
          types << :uri
        elsif value.is_a?(Float)
          types << :float
        elsif value.is_a?(Integer)
          types << :integer
        elsif value.to_s.eql?('true') || value.to_s.eql?('false')
          types << :boolean
        end
        types
      end

      def namespace_predicate(property_url)
        return nil if property_url.is_a?(RDF::Literal) || !URI::DEFAULT_PARSER.make_regexp.match?(property_url)

        regex = %r{^(?<namespace>.*[/#])(?<id>[^/#]+)$}
        match = regex.match(property_url.to_s)
        [match[:namespace], match[:id]] if match
      end

    end
  end
end