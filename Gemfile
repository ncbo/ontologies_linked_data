source 'https://rubygems.org'

gemspec

gem 'activesupport'
gem 'addressable', '~> 2.8'
gem 'bcrypt', '~> 3.0'
gem 'ffi'
gem 'libxml-ruby'
gem 'multi_json', '~> 1.0'
gem 'oj', '~> 3.0'
gem 'omni_logger'
gem 'pony'
gem 'rack'
gem 'rake'
gem 'request_store'
gem 'rest-client'
gem 'rsolr'
gem 'jwt'
gem 'json-ld', '~> 3.2.0'

# Testing
group :test do
  gem 'email_spec'
  gem 'minitest'
  gem 'minitest-reporters'
  gem 'mocha', '~> 2.7'
  gem 'mock_redis', '~> 0.5'
  gem 'ontoportal_testkit', github: 'alexskr/ontoportal_testkit', branch: 'main'
  gem 'pry'
  gem 'rack-test', '~> 0.6'
  gem 'simplecov'
  gem 'simplecov-cobertura' # for codecov.io
  gem "thin", "~> 1.8.2"
  gem 'webmock'
end

group :development do
  gem 'rubocop', require: false
end
# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'ncbo/goo', branch: 'development'
gem 'sparql-client', github: 'ncbo/sparql-client', branch: 'development'


gem 'public_suffix', '~> 5.1.1'
gem 'net-imap', '~> 0.4.18'
