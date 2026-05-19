require "tmpdir"

class TestLogFile < File
  def initialize
    super(File.join(Dir.tmpdir, "ontologies_linked_data-test-#{Process.pid}.log"), "w")
  end
end
