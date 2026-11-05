# This is a test rack app for use with the linked data serializer tests

use LinkedData::Serializer

map '/' do
  run Proc.new { |env| [200, {'content-type' => 'text/html'}, ['success']] }
end