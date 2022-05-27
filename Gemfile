source 'https://rubygems.org'

gem 'activesupport', '~> 4'
gem 'addressable', '~> 2.8'
gem 'bcrypt', '~> 3.0'
gem 'cube-ruby', require: 'cube'
gem 'faraday', '~> 1.9'
gem 'ffi'
gem 'libxml-ruby', '~> 2.0'
gem 'minitest'
gem 'multi_json', '~> 1.0'
gem 'oj', '~> 2.0'
gem 'omni_logger'
gem 'pony'
gem 'rack', '~> 1.0'
gem 'rack-test', '~> 0.6'
gem 'rake', '~> 10.0'
gem 'rest-client'
gem 'rsolr', '~> 1.0'
gem 'rubyzip', '~> 1.0'
gem 'thin'

# Testing
group :test do
  gem 'email_spec'
  gem 'minitest-reporters', '>= 0.5.0'
  gem 'pry'
  gem 'simplecov'
  gem 'test-unit-minitest'
end

group :development do
  gem 'rubocop', require: false
end

# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'ncbo/goo', branch: 'develop'
gem 'sparql-client', github: 'ncbo/sparql-client', branch: 'develop'
