require "goo"

require_relative "../config/default.rb"
require_relative "ontologies_linked_data/serializer"
require_relative "ontologies_linked_data/utils/file"
require_relative "ontologies_linked_data/utils/triples"
require_relative "ontologies_linked_data/utils/namespaces"
require_relative "ontologies_linked_data/parser/parser"
require_relative "ontologies_linked_data/monkeypatches/to_flex_hash/object"

# Setup Goo (repo connection and namespaces)
port = $GOO_PORT || 9000
host = $GOO_HOST || "localhost"
begin
  if Goo.store().nil?
    Goo.configure do |conf|
      conf[:stores] = [ { :name => :main , :host => host, :port => port, :options => { } } ]
      conf[:namespaces] = {
        :metadata => "http://data.bioontology.org/metadata/",
        :omv => "http://omv.org/ontology/",
        :default => :metadata
      }
    end
  end
rescue Exception => e
  abort("EXITING: Cannot connect to triplestore")
end

# Require base model
require_relative "ontologies_linked_data/models/base"

# Require all models
project_root = File.dirname(File.absolute_path(__FILE__))
Dir.glob(project_root + '/ontologies_linked_data/models/*', &method(:require))

