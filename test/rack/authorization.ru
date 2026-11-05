# This is a test rack app for use with the linked data serializer tests

require 'json'
use LinkedData::Security::Authorization

map '/ontologies' do
  run Proc.new { |env|
    user = env["REMOTE_USER"]
    apikey = user ? user.apikey : "NO USER FOUND"
    [200, {'content-type' => 'text/html'}, [apikey.to_json]]
  }
end