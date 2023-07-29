source 'https://rubygems.org'

gem 'activesupport', '~> 4'
gem 'addressable', '~> 2.8'
gem 'bcrypt', '~> 3.0'
gem 'cube-ruby', require: 'cube'
gem 'ffi'
gem 'libxml-ruby'
gem 'multi_json', '~> 1.0'
gem 'oj', '~> 3.0'
gem 'omni_logger'
gem 'pony'
gem 'rack'
gem 'rake', '~> 10.0'
gem 'rest-client'
gem 'rsolr'
gem 'rubyzip', '~> 1.0'
gem 'thin'

# Testing
group :test do
  gem 'email_spec'
  gem 'minitest', '~> 4'
  gem 'minitest-reporters', '>= 0.5.0'
  gem 'pry'
  gem 'rack-test', '~> 0.6'
  gem 'simplecov'
  gem 'simplecov-cobertura' # for codecov.io
end

group :development do
  gem 'rubocop', require: false
end

# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'ncbo/goo', branch: 'develop'
gem 'sparql-client', github: 'ncbo/sparql-client', branch: 'develop'
