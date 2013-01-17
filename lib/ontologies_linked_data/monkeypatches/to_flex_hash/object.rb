require 'set'

class Object
  def to_flex_hash(options = {})
    if kind_of?(Hash) || kind_of?(String) || kind_of?(Fixnum) || kind_of?(Float); then return self; end

    # Handle enumerables by recursing
    if kind_of?(Enumerable) && !kind_of?(Hash)
      new_enum = self.class.new
      each do |item|
        new_enum << item.to_flex_hash
      end
      return new_enum
    end

    all = options[:all] ||= false
    only = Set.new(options[:only]).map! {|e| e.to_sym }
    methods = Set.new(options[:methods]).map! {|e| e.to_sym }
    except = Set.new(options[:except]).map! {|e| e.to_sym }

    hash = {}

    # Look for table attribute or get all instance variables
    if instance_variables.include?(:@attributes)
      hash.replace(instance_variable_get("@attributes"))
    else
      instance_variables.each {|var| hash[var.to_s.delete("@").to_sym] = instance_variable_get(var) }
    end

    # Remove known bad data
    bad_attributes = %w(internals captures splat)
    bad_attributes.each do |bad_attribute|
      hash.delete(bad_attribute)
      hash.delete(bad_attribute.to_sym)
    end

    if all # Get everything
      methods = serializable_methods if respond_to? "serializable_methods"
    end

    # Infer methods from only
    only.each do |prop|
      methods << prop unless hash.key?(prop)
    end

    # Add methods
    methods.each do |method|
      hash[method] = self.send(method.to_s)
    end

    # Get rid of everything except the 'only'
    hash.keep_if {|k,v| only.include?(k) } unless only.empty?

    # Make sure we're not returning things to be excepted
    hash.delete_if {|k,v| except.include?(k) } unless except.empty?

    # Symbolize keys and convert linked objects to their ids
    hash.dup.each do |k,v|
      unless k.kind_of? Symbol
        hash[k.to_sym] = v
        hash.delete(k)
      end

      # Convert IRIs
      v = v.value if v.kind_of?(RDF::IRI)

      # Convert linked objects to id
      value = v.respond_to?(:resource_id) ? LinkedData::Utils::Namespaces.last_iri_fragment(v.resource_id.value) : v
      # Convert arrays of linked objects
      if v.kind_of?(Enumerable) && v.first.respond_to?(:resource_id)
        value = v.map {|e| LinkedData::Utils::Namespaces.last_iri_fragment(e.resource_id.value) }
      end

      hash[k] = value
    end

    hash
  end
end
