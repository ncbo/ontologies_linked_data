# -*- encoding: utf-8 -*-
require_relative 'lib/ontologies_linked_data/version'

Gem::Specification.new do |gem|
  gem.name          = "ontologies_linked_data"
  gem.version       = LinkedData::VERSION
  gem.summary       = "Models and serializers for ontologies and related artifacts backed by an RDF database"
  gem.summary       = "This library can be used for interacting with an AllegroGraph or 4store instance that stores " \
                      "BioPortal-based ontology information. Models in the library are based on Goo. Serializers " \
                      "support RDF serialization as Rack Middleware and automatic generation of hypermedia links."
  gem.authors       = ["Paul R Alexander"]
  gem.email         = ["support@bioontology.org"]
  gem.homepage      = "https://github.com/ncbo/ontologies_linked_data"

  gem.files         = %x(git ls-files).split("\n")
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.require_paths = ["lib"]

  gem.required_ruby_version = ">= 3.1"

  gem.add_dependency("activesupport")
  gem.add_dependency("bcrypt")
  gem.add_dependency("goo")
  gem.add_dependency("json")
  gem.add_dependency("libxml-ruby")
  gem.add_dependency("multi_json")
  gem.add_dependency("net-ftp")
  gem.add_dependency("oj")
  gem.add_dependency("omni_logger")
  gem.add_dependency("pony")
  gem.add_dependency("rack")
  gem.add_dependency("rack-test")
  gem.add_dependency("rsolr")
  gem.add_dependency("rubyzip", "~> 3.0")

  gem.add_development_dependency("email_spec")

  # gem.executables = %w()
end
