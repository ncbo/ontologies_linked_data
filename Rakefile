require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs = []
  t.test_files = FileList['test/**/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
  t.name = "test:models"
  t.test_files = FileList['test/models/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
  t.name = "test:rack"
  t.test_files = FileList['test/rack/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
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
    GenerateTestData.create
  end

  desc "Remove sample data"
  task :delete do
    require_relative "test/data/generate_test_data"
    GenerateTestData.delete
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
