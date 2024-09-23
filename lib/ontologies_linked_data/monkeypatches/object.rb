require 'set'
require 'ontologies_linked_data/monkeypatches/class'

class Object

  DO_NOT_SERIALIZE = %w(attributes table _cached_exist internals captures splat uuid password inverse_atttributes loaded_attributes modified_attributes previous_values persistent aggregates unmapped errors object_id)
  CONVERT_TO_STRING = Set.new([RDF::IRI, RDF::URI, RDF::Literal].map {|c| [c.descendants, c]}.flatten)

  def to_flex_hash(options = {}, &block)
    return self if is_a?(String) || is_a?(Integer) || is_a?(Float) || is_a?(TrueClass) || is_a?(FalseClass) || is_a?(NilClass)

    # Make sure special include_for_class params are separated out
    options[:include_for_class] = options[:params]["include_for_class"] if options[:params]

    # Recurse to handle sets, arrays, etc
    recursed_object = enumerable_handling(options, &block)
    return recursed_object unless recursed_object.nil?

    # Get sets for passed parameters from users
    all = options[:all] ||= false
    only = Set.new(options[:only]).map! {|e| e.to_sym }
    methods = Set.new(options[:methods]).map! {|e| e.to_sym }
    except = Set.new(options[:except]).map! {|e| e.to_sym }

    hash = {}

    # This is used in places where the class is not a top-level object
    # For example, in the Annotator response. For these endpoints, we
    # assume that include=prefLabel applies to the annotatedClass
    # or wherever a class object appears in the response.
    cls = self.respond_to?(:klass) ? self.klass : self.class
    if cls == LinkedData::Models::Class && options[:include_for_class]
      only = Set.new(options[:include_for_class] || [])
    end

    if all # Get everything
      methods = self.class.hypermedia_settings[:serialize_methods] if self.is_a?(LinkedData::Hypermedia::Resource)
    end

    # Check to see if we're nested, if so remove necessary properties
    only = only - do_not_serialize_nested(options)

    # Determine whether to use defaults from the DSL or all attributes
    hash = populate_attributes(hash, all, only, options)

    # Remove banned attributes (from DSL or defined here)
    hash = remove_bad_attributes(hash)

    # Infer methods from only
    only.each do |prop|
      methods << prop unless hash.key?(prop)
    end

    # Add methods
    methods = methods - do_not_serialize_nested(options)
    methods.each do |method|
      populate_attribute(hash, method) if self.respond_to?(method) rescue next
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

      # Convert RDF literals to their equivalent Ruby typed value
      if v.is_a?(RDF::Literal)
        hash[k] = v.value
        next
      end

      # Look at the Hypermedia DSL to determine if we should embed this attribute
      hash, modified = embed_goo_objects(hash, k, v, options, &block)
      next if modified

      # Look at the Hypermedia DSL to determine if we should embed this attribute
      begin
        hash, modified = embed_goo_objects_just_values(hash, k, v, options, &block)
      rescue Exception => e
        puts "Bad data found in submission: #{hash}"
        puts "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
        raise e
      end

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
  # Get a list of attributes that aren't allowed to be serialized
  # when the object is nested. If the object is not nested or there
  # is no restriction, return an empty array.
  def do_not_serialize_nested(options, cls = nil)
    return [] if options && options[:params] && options[:params]["serialize_nested"]

    cls ||= self
    if options[:nested] && cls.is_a?(LinkedData::Hypermedia::Resource)
      do_not_serialize = cls.class.hypermedia_settings[:prevent_serialize_when_nested]
    end
    do_not_serialize || []
  end


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
    tmp = Array(value).map do |val|
      LinkedData::Models::Base.replace_url_id_to_prefix(val)
    end
    value.is_a?(Array) || value.is_a?(Set) ? tmp : tmp.first
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
      totalCount: self.aggregate,
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

  def populate_attributes(hash, all = false, only = [], options = {})
    current_cls = self.respond_to?(:klass) ? self.klass : self.class

    # Look for default attributes or use all
    if !current_cls.ancestors.include?(LinkedData::Hypermedia::Resource) || current_cls.hypermedia_settings[:serialize_default].empty? || all
      attributes = self.is_a?(Struct) ? self.members : self.instance_variables.map {|e| e.to_s.delete("@").to_sym }

      attributes = attributes - do_not_serialize_nested(options)

      attributes.each do |attribute|
        next unless self.respond_to?(attribute)
        populate_attribute(hash, attribute)
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

  def populate_attribute(hash, attribute)
    if self.method(attribute).parameters.eql?([[:rest, :args]])
      hash[attribute] = self.send(attribute, include_languages: true)
    else
      # a serialized method
      hash[attribute] = self.send(attribute)
    end
  end

  def populate_hash_from_list(hash, attributes)
    attributes.each do |attribute|
      attribute = attribute.to_sym

      next unless self.respond_to?(attribute)
      begin
        populate_attribute(hash, attribute)
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
    options = sample_object.class == self.class ? options : {include_for_class: options[:include_for_class]}

    # If we're using a struct here, we should get it's class
    sample_class = self.is_a?(Struct) && self.respond_to?(:klass) ? self.klass : self.class

    # Don't process if we're recursing and this attribute is forbidden in nested elements
    disallow_nested = !do_not_serialize_nested(options).empty?
    return hash, false if disallow_nested

    embedded = sample_class.ancestors.include?(LinkedData::Hypermedia::Resource) && sample_class.hypermedia_settings[:embed].include?(attribute)
    if embedded
      # Options gets shared between attributes on the top level
      # so we should dup it so if one attr is embedded it doesn't
      # think that all of them are (by setting nested in the next line)
      options = options.dup
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
    return if goo_object.nil?

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
