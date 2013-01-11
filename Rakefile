require 'rake/testtask'
require 'pry'

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

namespace :test do
  if (not (ENV['TESTOPTS'].index "--skip-parsing").nil?)
    test_opts = ENV['TESTOPTS'].dup
    test_opts["--skip-parsing"]=""
    ENV['TESTOPTS'] = test_opts
    ENV['SKIP_PARSING'] = "please" #be nice
  end
end
