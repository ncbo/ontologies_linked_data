source 'https://rubygems.org'

gemspec

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
gem 'request_store'


# Testing
group :test do
  gem 'email_spec'
  gem 'minitest', '~> 4'
  gem 'minitest-reporters', '>= 0.5.0'
  gem 'mocha', '~> 2.7'
  gem 'mock_redis', '~> 0.5'
  gem 'pry'
  gem 'rack-test', '~> 0.6'
  gem 'simplecov'
  gem 'simplecov-cobertura' # for codecov.io
end

group :development do
  gem 'rubocop', require: false
end
# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'ncbo/goo', branch: 'master'
gem 'sparql-client', github: 'ncbo/sparql-client', tag: 'v6.3.0'

gem 'public_suffix', '~> 5.1.1'
gem 'net-imap', '~> 0.4.18'
