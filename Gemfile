source 'https://rubygems.org'

gem 'rake', '~> 10.0'
gem 'rack', '~> 1.0'
gem 'rack-test', '~> 0.6'
gem 'activesupport', '~> 4.0'
gem 'rubyzip', '~> 1.0'
gem 'bcrypt', '~> 3.0'
gem 'multi_json', '~> 1.0'
gem 'rsolr', '~> 1.0'
gem 'minitest', '~> 4.0'
gem 'cube-ruby', require: "cube"
gem 'pony'
gem 'addressable', '= 2.3.5'

# Platform-specific gems
platforms :jruby do
  gem 'libxml-jruby'
  gem 'gson'
end

platforms :ruby do
  gem 'libxml-ruby', '~> 2.0'
  gem 'oj', '~> 2.0'
end

# Testing
gem 'simplecov', :group => :test
gem 'pry', :group => :test
gem 'email_spec', :group => :test

# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'ncbo/goo', branch: 'staging'
gem 'sparql-client', github: 'ncbo/sparql-client', branch: 'staging'
