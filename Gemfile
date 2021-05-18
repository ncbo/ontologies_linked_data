source 'https://rubygems.org'

gem 'rake', '~> 10.0'
gem 'rack', '~> 1.0'
gem 'rack-test', '~> 0.6'
gem 'activesupport', '~> 4.0'
gem 'rubyzip', '~> 1.0'
gem 'bcrypt', '~> 3.0'
gem 'multi_json', '~> 1.0'
gem 'oj', '~> 2.0'
gem 'libxml-ruby', '~> 2.0'
gem 'rsolr', '~> 1.0'
gem 'minitest', '~> 4.0'
gem 'cube-ruby', require: "cube"
gem 'pony'
gem 'addressable', '= 2.3.5'
gem 'omni_logger'
gem 'thin'
gem 'rubocop', require: false
gem 'ffi', '< 1.9.25'   # https://github.com/ffi/ffi/issues/621
gem 'rest-client'

# Testing
group :test do
	gem 'simplecov'
	gem 'pry'
	gem 'email_spec'
	gem 'test-unit-minitest'
	gem 'minitest-reporters', '>= 0.5.0'
end

# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'ncbo/goo', branch: 'master'
gem 'sparql-client', github: 'ncbo/sparql-client', branch: 'master'

# ResourceIndex dependencies (managed per-platform)
gem 'ncbo_resource_index', github: 'ncbo/resource_index'
