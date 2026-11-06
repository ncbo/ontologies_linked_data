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
# Reports the user each identity source holds while the request runs
map '/current_user' do
  run Proc.new { |env|
    body = {
      env: env["REMOTE_USER"]&.username,
      thread: Thread.current[:remote_user]&.username
    }
    [200, {'content-type' => 'application/json'}, [body.to_json]]
  }
end

# Changes another user's apikey through the model, which relies on the
# model-level write check (no user is passed to save)
map '/change_apikey' do
  run Proc.new { |env|
    username = Rack::Request.new(env).params["username"]
    user = LinkedData::Models::User.find(username).include(LinkedData::Models::User.attributes).first
    user.apikey = "changed-#{rand}"
    begin
      user.save
      [200, {'content-type' => 'application/json'}, [{ saved: true }.to_json]]
    rescue LinkedData::Security::WriteAccessDeniedError
      [403, {'content-type' => 'application/json'}, [{ saved: false }.to_json]]
    end
  }
end
