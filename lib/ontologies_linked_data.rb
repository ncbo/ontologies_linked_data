require 'goo'

# Make sure we're in the load path
lib_dir = "#{File.dirname(__FILE__)}/../lib"
$LOAD_PATH.unshift lib_dir unless $LOAD_PATH.include?(lib_dir)

# Setup Goo (repo connection and namespaces)
require 'ontologies_linked_data/config/config'

# Include other dependent code
require "ontologies_linked_data/security/authorization"
require "ontologies_linked_data/security/access_control"
require "ontologies_linked_data/security/access_denied_middleware"
require "ontologies_linked_data/hypermedia/hypermedia"
require "ontologies_linked_data/serializer"
require "ontologies_linked_data/serializers/serializers"
require "ontologies_linked_data/utils/file"
require "ontologies_linked_data/utils/triples"
require "ontologies_linked_data/utils/notifications"
require "ontologies_linked_data/utils/notifier"
require "ontologies_linked_data/utils/ontology_csv_writer"
require "ontologies_linked_data/utils/multi_logger"
require "ontologies_linked_data/parser/parser"
require "ontologies_linked_data/diff/diff"
require "ontologies_linked_data/monkeypatches/class" # load before object
require "ontologies_linked_data/monkeypatches/object"
require "ontologies_linked_data/monkeypatches/logging"
require "ontologies_linked_data/sample_data/sample_data"
require "ontologies_linked_data/mappings/mappings"
require "ontologies_linked_data/http_cache/cacheable_resource"
require "ontologies_linked_data/metrics/metrics"

# Require base model
require 'ontologies_linked_data/models/base'

# Require all models and services
project_root = File.dirname(File.absolute_path(__FILE__))

require 'ontologies_linked_data/services/submission_process/submission_process'
models = Dir.glob("#{project_root}/ontologies_linked_data/concerns/**/*.rb").sort
models.each do |m|
  require m
end



# We need to require deterministic - that is why we have the sort.

models = Dir.glob("#{project_root}/ontologies_linked_data/services/**/*.rb").sort
models.each do |m|
  require m
end

# We need to require deterministic - that is why we have the sort.
models = Dir.glob("#{project_root}/ontologies_linked_data/models/concerns/**/*.rb").sort
models.each do |m|
  require m
end

models = Dir.glob("#{project_root}/ontologies_linked_data/concerns/**/*.rb").sort
models.each do |m|
  require m
end
# We need to require deterministic - that is why we have the sort.
models = Dir.glob("#{project_root}/ontologies_linked_data/models/**/*.rb").sort
models.each do |m|
  require m
end



module LinkedData
  def rootdir
    File.dirname(File.absolute_path(__FILE__))
  end

  def bindir
    File.expand_path("#{rootdir}/../bin")
  end
end
