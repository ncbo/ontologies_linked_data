require 'csv'
require 'zlib'

module LinkedData
  module Utils
    class OntologyCSVWriter

      # Column headers for Standard BioPortal properties.
      CLASS_ID = 'Class ID'
      PREF_LABEL = 'Preferred Label'
      SYNONYMS = 'Synonyms'
      DEFINITIONS = 'Definitions'
      CUI = 'CUI'
      SEMANTIC_TYPES = 'Semantic Types'
      OBSOLETE = 'Obsolete'
      PARENTS = 'Parents'
      UNTAGGED_LABEL_KEYS = [:none, 'none', :'@none', '@none', nil, ''].freeze

      def open(ont, path)
        @file = File.new(path, 'w')
        @gz = Zlib::GzipWriter.new(@file)
        @csv = CSV.new(@gz, headers: true, return_headers: true, write_headers: true)
        @property_ids = Hash[ont.properties.map { |prop| [prop.id.to_s, get_prop_label(prop)] }]
        write_header(ont)
      end

      def write_header(ont)
        props_bioportal_standard = [CLASS_ID,PREF_LABEL,SYNONYMS,DEFINITIONS,OBSOLETE,CUI,SEMANTIC_TYPES,PARENTS]
        props_other = ont.properties.map { |prop| get_prop_label(prop) }
        props_other.sort! { |a,b| a.downcase <=> b.downcase }
        @headers = props_bioportal_standard.concat(props_other)
        @csv << @headers
      end

      def write_class(ont_class)
        ont_class.bring_remaining
        row = CSV::Row.new(@headers, Array.new(@headers.size), false)

        # ID
        row[CLASS_ID] = ont_class.id

        # Preferred label
        row[PREF_LABEL] = preferred_label_for_csv(ont_class)

        # Synonyms
        synonyms = ont_class.synonym
        row[SYNONYMS] = synonyms.join('|') unless synonyms.empty?

        # Definitions
        definitions = ont_class.definition
        row[DEFINITIONS] = definitions.join('|') unless definitions.empty?

        # Obsolete
        row[OBSOLETE] = Array(ont_class.obsolete).first.to_s.upcase

        # CUI
        cuis = ont_class.cui
        row[CUI] = cuis.join('|') unless cuis.empty?

        # Semantic types
        semantic_types = ont_class.semanticType
        row[SEMANTIC_TYPES] = semantic_types.join('|') unless semantic_types.empty?

        # Parents
        parents = ont_class.parents
        row[PARENTS] = get_parent_ids(parents) unless parents.empty?

        # Other properties.
        props = ont_class.properties
        props.each do |p|
          id = p.first.to_s
          if @property_ids.has_key?(id)
            values = p.last.map { |v| v.to_s }
            row[@property_ids[id]] = values.join('|')
          end
        end

        @csv << row
      end

      def close
        @gz.close
        @file.close
        @csv.close
      end

      def get_parent_ids(parents)
        parent_ids = []
        parents.each do |parent|
          parent_ids << parent.id
        end
        return parent_ids.join('|')
      end

      def preferred_label_for_csv(ont_class)
        pref_label = csv_pref_label(ont_class)
        return label_value(pref_label) unless pref_label.is_a?(Hash)

        label_for_language(pref_label) { |language_key| english_label_key?(language_key) } ||
          label_for_language(pref_label) { |language_key| untagged_label_key?(language_key) } ||
          first_label_value(pref_label)
      end

      def csv_pref_label(ont_class)
        ont_class.prefLabel(include_languages: true)
      rescue ArgumentError
        ont_class.prefLabel
      end

      def label_for_language(labels)
        labels.each do |language_key, value|
          next unless yield(language_key)

          label = label_value(value)
          return label unless label.nil?
        end
        nil
      end

      def english_label_key?(language_key)
        language_key.to_s.downcase.delete_prefix('@').match?(/\Aen(?:-|$)/)
      end

      def untagged_label_key?(language_key)
        UNTAGGED_LABEL_KEYS.include?(language_key)
      end

      def first_label_value(labels)
        labels.sort_by { |language_key, _| language_key.to_s }.each do |_, value|
          label = label_value(value)
          return label unless label.nil?
        end
        nil
      end

      def label_value(value)
        Array(value).flatten.each do |label|
          next if label.nil?

          label = label.id if defined?(Goo::Base::Resource) && label.is_a?(Goo::Base::Resource)
          label = label.to_s.strip
          return label unless label.empty?
        end

        nil
      end

      def get_prop_label(prop)
        prop.label.empty? ? prop.id.to_s : prop.label.first.to_s
      end
    end
  end
end
