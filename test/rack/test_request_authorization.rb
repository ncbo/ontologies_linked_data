require 'minitest/unit'
require "rack/test"
require "json"
require "logger"
require_relative "../../lib/ontologies_linked_data"
require_relative "../../config/config.rb"

LOGGER = Logger.new($stdout)
ENV["rack.test"] = "true"


class TestRackAuthorization < MiniTest::Unit::TestCase
  include Rack::Test::Methods

  def app
    eval "Rack::Builder.new {( " + File.read(File.dirname(__FILE__) + '/authorization.ru') + "\n )}"
  end

  def setup
    _variables
    _delete_user
    users = _create_user
    user = users.shift
    user1 = users.shift
    @apikey = user.apikey
    @userapikey = user1.apikey
    @security = LinkedData.settings.enable_security
    LinkedData.settings.enable_security = true
  end

  def teardown
    LinkedData.settings.enable_security = @security
    _delete_user
  end

  def _variables
    @usernames = ["test_username", "user2"]
  end

  def _create_user
    users = []
    @usernames.each do |username|
      user = LinkedData::Models::User.new({
        username: username,
        password: "test_password",
        email: "test_email@example.org"
      })
      user.save unless user.exist?
      users << user
    end
    users
  end

  def _delete_user
    @usernames.each do |username|
      user = LinkedData::Models::User.find(username).first
      user.delete unless user.nil?
    end
  end

  def test_authorize
    get "/ontologies"
    assert last_response.status == 401
    get "/ontologies", {}, {"Authorization" => 'apikey token="'+@apikey+''+'"'}
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @apikey.eql?(apikey)
    get "/ontologies", {}, {"Authorization" => "apikey token=#{@apikey}"}
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @apikey.eql?(apikey)
    get "/ontologies?apikey=#{@apikey}"
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @apikey.eql?(apikey)
    get "/ontologies", {}, {"Authorization" => 'apikey token="'+@apikey+'&userapikey='+@userapikey+'"'}
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @userapikey.eql?(apikey)
    get "/ontologies", {}, {"Authorization" => "apikey token=#{@apikey}&userapikey=#{@userapikey}"}
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @userapikey.eql?(apikey)
    get "/ontologies?apikey=#{@apikey}&userapikey=#{@userapikey}"
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @userapikey.eql?(apikey)
  end

end
