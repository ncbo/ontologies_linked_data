require 'set'

class Object

  DO_NOT_SERIALIZE = %w(attributes table _cached_exist internals captures splat uuid password inverse_atttributes loaded_attributes modified_attributes previous_values persistent aggregates unmapped errors id)
  CONVERT_TO_STRING = Set.new([RDF::IRI, RDF::URI])

  def to_flex_hash(options = {}, &block)
    return self if is_a?(String) || is_a?(Fixnum) || is_a?(Float) || is_a?(TrueClass) || is_a?(FalseClass)

    # Recurse to handle sets, arrays, etc
    recursed_object = enumerable_handling(options, &block)
    return recursed_object unless recursed_object.nil?

    # Get sets for passed parameters from users
    all = options[:all] ||= false
    only = Set.new(options[:only]).map! {|e| e.to_sym }
    methods = Set.new(options[:methods]).map! {|e| e.to_sym }
    except = Set.new(options[:except]).map! {|e| e.to_sym }

    hash = {}

    if all # Get everything
      methods = self.class.hypermedia_settings[:serialize_methods] if self.is_a?(LinkedData::Hypermedia::Resource)
    end

    # Check to see if we're nested, if so remove necessary properties
    if options[:nested] && self.is_a?(LinkedData::Hypermedia::Resource) && !self.class.hypermedia_settings[:prevent_serialize_when_nested].empty?
      only = only - self.class.hypermedia_settings[:prevent_serialize_when_nested]
    end

    # Determine whether to use defaults from the DSL or all attributes
    hash = populate_attributes(hash, all, only)

    # Remove banned attributes (from DSL or defined here)
    hash = remove_bad_attributes(hash)

    # Infer methods from only
    only.each do |prop|
      methods << prop unless hash.key?(prop)
    end

    # Add methods
    methods.each do |method|
      begin
        hash[method] = self.send(method.to_s) if self.respond_to?(method)
      rescue Exception => e
        next
      end
    end

    # Get rid of everything except the 'only'
    hash.keep_if {|k,v| only.include?(k) } unless only.empty?

    # Make sure we're not returning things to be excepted
    hash.delete_if {|k,v| except.include?(k) } unless except.empty?

    # Filter to use if we need to remove attributes (done when we iterate the hash below)
    do_not_filter = self.class.hypermedia_settings[:serialize_filter].first.call(self) unless !self.is_a?(LinkedData::Hypermedia::Resource) || self.class.hypermedia_settings[:serialize_filter].empty?

    # Special processing for each attribute in the new hash
    # This will handle serializing linked goo objects
    keys = hash.keys
    keys.each do |k|
      v = hash[k]

      # Filter out values on a per-instance basis
      # If the attributes list contains a proc, call it to get values
      filtered_attribute = do_not_filter && !do_not_filter.include?(k)
      if self.is_a?(LinkedData::Hypermedia::Resource) && filtered_attribute
        hash.delete(k)
        next
      end

      # Convert keys from IRIs to strings
      unless k.is_a?(Symbol) || k.is_a?(String) || k.is_a?(Fixnum)
        hash.delete(k)
        hash[convert_nonstandard_types(k, options, &block)] = v
      end

      # Look at the Hypermedia DSL to determine if we should embed this attribute
      hash, modified = embed_goo_objects(hash, k, v, options, &block)
      next if modified

      # Look at the Hypermedia DSL to determine if we should embed this attribute
      hash, modified = embed_goo_objects_just_values(hash, k, v, options, &block)
      next if modified

      new_value = convert_nonstandard_types(v, options, &block)

      hash[k] = new_value
    end

    # Don't show nil properties for read_only objects. We do this because
    # we could be showing a term, but only know its id. If we showed prefLabel
    # as nil, it would be misleading, because the term likely has a prefLabel.
    if self.respond_to?(:klass)
      hash.delete_if {|k,v| v.nil?}
    end

    # Provide the hash for serialization processes to add data
    yield hash, self if block_given?

    hash
  end

  private

  ##
  # Convert types from goo and elsewhere using custom methods
  def convert_nonstandard_types(value, options, &block)
    return convert_value_hash(value, options, &block) if value.is_a?(Hash)
    return value.to_flex_hash(options, &block) if value.is_a?(Struct) && value.respond_to?(:klass)
    value = convert_goo_objects(value)
    value = convert_to_string(value)
    value = convert_url_prefix(value)
    value
  end

  ##
  # If the config option is set, turn http://data.bioontology.org urls into the configured REST url
  def convert_url_prefix(value)
    if LinkedData.settings.replace_url_prefix
      if value.is_a?(String) && value.start_with?(LinkedData.settings.id_url_prefix)
        value = value.sub(LinkedData.settings.id_url_prefix, LinkedData.settings.rest_url_prefix)
      end

      if (value.is_a?(Array) || value.is_a?(Set)) && value.first.is_a?(String) && value.first.start_with?(LinkedData.settings.id_url_prefix)
        value = value.map {|v| v.sub(LinkedData.settings.id_url_prefix, LinkedData.settings.rest_url_prefix)}
      end
    end
    value
  end

  ##
  # Convert values that should be a string to a string
  def convert_to_string(value)
    sample_class = value.is_a?(Array) ? value.first.class : value.class
    if CONVERT_TO_STRING.include?(sample_class)
      if value.is_a?(Array)
        value = value.map {|e| e.to_s}
      else
        value = value.to_s
      end
    end
    value
  end

  ##
  # Handle enumerables by recursing
  def enumerable_handling(options, &block)
    if (self.is_a?(Array) || self.is_a?(Set)) && !self.is_a?(Goo::Base::Page)
      new_enum = self.class.new
      each do |item|
        new_enum << item.to_flex_hash(options, &block)
      end
      return new_enum
    elsif kind_of?(Hash)
      new_hash = self.class.new
      each do |key, value|
        new_hash[key] = value.to_flex_hash(options, &block)
      end
      return new_hash
    elsif kind_of?(Goo::Base::Page)
      return convert_goo_page(options, &block)
    end
    return nil
  end

  def convert_goo_page(options, &block)
    page = {
      page: self.page_number,
      pageCount: self.total_pages,
      prevPage: self.prev_page,
      nextPage: self.next_page,
      links: generate_page_links(options, self.page_number, self.total_pages),
      collection: []
    }

    self.each do |item|
      page[:collection] << item.to_flex_hash(options, &block)
    end

    page
  end

  def generate_page_links(options, page, page_count)
    request = options[:request]

    if request
      params = request.params.dup
      request_path = "#{LinkedData.settings.rest_url_prefix.chomp("/")}#{request.path}"
      next_page = page == page_count ? nil : "#{request_path}?#{Rack::Utils.build_nested_query(params.merge("page" => (page + 1).to_s))}"
      prev_page = page == 1 ? nil : "#{request_path}?#{Rack::Utils.build_query(params.merge("page" => (page - 1).to_s))}"
    else
      next_page = "?#{Rack::Utils.build_query("page" => page + 1)}"
      prev_page = "?#{Rack::Utils.build_query("page" => page - 1)}"
    end

    return {
      nextPage: next_page,
      prevPage: prev_page
    }
  end

  def populate_attributes(hash, all = false, only = [])
    current_cls = self.respond_to?(:klass) ? self.klass : self.class

    # Look for default attributes or use all
    if !current_cls.ancestors.include?(LinkedData::Hypermedia::Resource) || current_cls.hypermedia_settings[:serialize_default].empty? || all
      attributes = self.is_a?(Struct) ? self.members : self.instance_variables.map {|e| e.to_s.delete("@").to_sym }
      attributes.each do |attribute|
        next unless self.respond_to?(attribute)
        hash[attribute] = self.send(attribute)
      end
    elsif !only.empty?
      # Only get stuff we need
      hash = populate_hash_from_list(hash, only)
    else
      attributes = current_cls.hypermedia_settings[:serialize_default]
      hash = populate_hash_from_list(hash, attributes)
    end
    hash
  end

  def populate_hash_from_list(hash, attributes)
    attributes.each do |attribute|
      attribute = attribute.to_sym

      next unless self.respond_to?(attribute)
      begin
        hash[attribute] = self.send(attribute)
      rescue Goo::Base::AttributeNotLoaded
        next
      rescue ArgumentError
        next
      end
    end
    hash
  end

  def remove_bad_attributes(hash)
    bad_attributes = DO_NOT_SERIALIZE.dup
    bad_attributes.concat(self.class.hypermedia_settings[:serialize_never]) unless !self.is_a?(LinkedData::Hypermedia::Resource)
    bad_attributes.each do |bad_attribute|
      hash.delete(bad_attribute)
      hash.delete(bad_attribute.to_sym)
    end
    hash
  end

  def embed_goo_objects(hash, attribute, value, options, &block)
    sample_object = value.is_a?(Enumerable) && !value.is_a?(Hash) ? value.first : value

    # Use the same options if the object to serialize is the same as the one containing it
    options = sample_object.class == self.class ? options : {}

    # If we're using a struct here, we should get it's class
    sample_class = self.is_a?(Struct) && self.respond_to?(:klass) ? self.klass : self.class

    # Don't process if we're recursing and this attribute is forbidden in nested elements
    disallow_nested = sample_class.ancestors.include?(LinkedData::Hypermedia::Resource) && sample_class.hypermedia_settings[:prevent_serialize_when_nested].include?(attribute) && options[:nested]
    return hash, false if disallow_nested

    embedded = sample_class.ancestors.include?(LinkedData::Hypermedia::Resource) && sample_class.hypermedia_settings[:embed].include?(attribute)
    if embedded
      options[:nested] = true
      if (value.is_a?(Array) || value.is_a?(Set))
        values = value.map {|e| e.to_flex_hash(options, &block)}
      else
        values = value.to_flex_hash(options, &block)
      end
      hash[attribute] = values
      return hash, true
    end
    return hash, false
  end

  def embed_goo_objects_just_values(hash, attribute, value, options, &block)
    # If we're using a struct here, we should get it's class
    sample_class = self.is_a?(Struct) && self.respond_to?(:klass) ? self.klass : self.class

    if sample_class.ancestors.include?(LinkedData::Hypermedia::Resource) &&
      if !sample_class.hypermedia_settings[:embed_values].empty? && sample_class.hypermedia_settings[:embed_values].first.key?(attribute)
        attributes_to_embed = sample_class.hypermedia_settings[:embed_values].first[attribute]
        embedded_values = []
        if (value.is_a?(Array) || value.is_a?(Set))
          value.each do |goo_object|
            add_goo_values(goo_object, embedded_values, attributes_to_embed, options, &block)
          end
        else
          add_goo_values(value, embedded_values, attributes_to_embed, options, &block)
          embedded_values = embedded_values.first
        end
        hash[attribute] = embedded_values
        return hash, true
      end
    end
    return hash, false
  end

  def add_goo_values(goo_object, embedded_values, attributes_to_embed, options, &block)
    if attributes_to_embed.length > 1
      embedded_values_hash = {}
      attributes_to_embed.each do |a|
        embedded_values_hash[a] = convert_nonstandard_types(goo_object.send(a), options, &block)
        embedded_values << embedded_values_hash
      end
    else
      embedded_values << convert_nonstandard_types(goo_object.send(attributes_to_embed.first), options, &block)
    end
  end

  def convert_value_hash(hash, options, &block)
    new_hash = Hash.new
    hash.each do |k, v|
      new_hash[convert_nonstandard_types(k, options, &block)] = convert_nonstandard_types(v, options, &block)
    end
    new_hash
  end

  def convert_goo_objects(object)
    # Convert linked objects to id
    new_value = object.is_a?(Goo::Base::Resource) ? object.id : object

    # Convert arrays of linked objects
    if object.kind_of?(Enumerable) && object.first.is_a?(Goo::Base::Resource)
      new_value = object.map {|e| e.id }
    end

    return new_value
  end

end
