source 'https://rubygems.org'

gem 'rack'
gem 'rack-test'
gem 'json'
gem 'pry'
gem 'rubyzip'
gem 'simplecov', :require => false, :group => :test

# NCBO gems (can be from a local dev path or from rubygems/git)
gemfile_local = File.expand_path("../Gemfile.local", __FILE__)
if File.exists?(gemfile_local)
  self.instance_eval(Bundler.read_file(gemfile_local))
else
  gem 'goo', :git => 'https://github.com/ncbo/goo.git'
  gem 'sparql_http', :git => 'https://github.com/ncbo/sparql_http.git'
end

