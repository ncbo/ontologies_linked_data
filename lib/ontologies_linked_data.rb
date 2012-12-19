require "goo"

require_relative "ontologies_linked_data/serializer"
require_relative "ontologies_linked_data/utils/file"
require_relative "ontologies_linked_data/utils/triples"
require_relative "ontologies_linked_data/utils/namespaces"
require_relative "ontologies_linked_data/parser/parser"
require_relative "ontologies_linked_data/monkeypatches/to_flex_hash/object"

# Require all models
project_root = File.dirname(File.absolute_path(__FILE__))
Dir.glob(project_root + '/ontologies_linked_data/models/*', &method(:require))

# Setup Goo (repo connection and namespaces)
module LinkedData
  def self.config(options = {})
    port = options[:port] || $GOO_PORT || 9000
    host = options[:host] || $GOO_HOST || "localhost"
    begin
      if Goo.store().nil?
        Goo.configure do |conf|
          conf[:stores] = [ { :name => :main , :host => host, :port => port, :options => { } } ]
          conf[:namespaces] = {
            :metadata => "http://data.bioontology.org/metadata/",
            :default => :metadata,
          }
        end
      end
    rescue Exception => e
      puts "Invalid triplestore configuration, moving on"
    end
  end
end
