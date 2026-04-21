require 'rake/testtask'

task default: %w[test]

Rake::TestTask.new do |t|
  t.libs = []
  t.warning = false
  t.test_files = FileList['test/**/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
  t.warning = false
  t.name = "test:models"
  t.test_files = FileList['test/models/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
  t.warning = false
  t.name = "test:rack"
  t.test_files = FileList['test/rack/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
  t.warning = false
  t.name = "test:serializer"
  t.test_files = FileList['test/serializer/test*.rb']
end

desc "Run test coverage analysis"
task :coverage do
  puts "Code coverage reports will be visible in the /coverage folder"
  ENV["COVERAGE"] = "true"
  Rake::Task["test"].invoke
end

namespace :data do
  desc "Create sample data"
  task :create do
    require_relative "test/data/generate_test_data"
    LinkedData::TestData::Generate.create
  end

  desc "Remove sample data"
  task :delete do
    require_relative "test/data/generate_test_data"
    LinkedData::TestData::Generate.delete
  end

  desc "Delete all data"
  task :destroy do
    require_relative "test/data/destroy_test_data"
  end

  desc "Console for working with data"
  task :console do
    require_relative "test/data/generate_test_data"
    binding.pry
  end
end

namespace :test do
  if ENV['TESTOPTS']
    if (not (ENV['TESTOPTS'].index "--skip-parsing").nil?)
      test_opts = ENV['TESTOPTS'].dup
      test_opts["--skip-parsing"]=""
      ENV['TESTOPTS'] = test_opts
      ENV['SKIP_PARSING'] = "please" #be nice
    end
  end
end

require_relative 'test/docker_infrastructure'
namespace :docker do
  desc "Run tests with a docker environment"
  task :test do
    docker_tests
  end

  desc "Run tests with parallel docker environments"
  task :test_parallel do
    docker_tests_parallel
  end
end