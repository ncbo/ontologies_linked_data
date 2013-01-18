$GOO_PORT = 9000
$GOO_HOST = "localhost"

$REPOSITORY_FOLDER = "./test/data/ontology_files/repo"

# Settings in this file can be overridden in the custom.rb (warnings may happen)
custom = File.expand_path('../custom.rb', __FILE__)
require_relative "custom.rb" if File.exists?(custom)