require 'minitest/unit'
require "rack/test"
require "multi_json"
require_relative "../../lib/ontologies_linked_data"

class TestLinkedDataSerializer < MiniTest::Unit::TestCase
  include Rack::Test::Methods

  def app
    eval "Rack::Builder.new {( " + File.read(File.dirname(__FILE__) + '/serializer.ru') + "\n )}"
  end

  # DISABLED UNTIL WE SUPPORT CONTENT NEGOTIATION

  # def test_request_accept_header
  #   # Default is JSON
  #   req
  #   assert last_response.header["Content-Type"].eql?("application/json;charset=utf-8")

  #   # Try html
  #   req("text/html")
  #   assert last_request.env["HTTP_ACCEPT"].eql?("text/html")
  #   assert last_response.header["Content-Type"].eql?("text/html;charset=utf-8")

  #   # Alright, xml?
  #   req("application/rdf+xml")
  #   assert last_request.env["HTTP_ACCEPT"].eql?("application/rdf+xml")
  #   assert last_response.header["Content-Type"].eql?("application/rdf+xml;charset=utf-8")

  #   # JSONP?
  #   req("application/javascript")
  #   assert last_request.env["HTTP_ACCEPT"].eql?("application/javascript")
  #   assert last_response.header["Content-Type"].eql?("application/javascript;charset=utf-8")

  #   # Turtle, beautiful Turtle
  #   req("application/turtle")
  #   assert last_request.env["HTTP_ACCEPT"].eql?("application/turtle")
  #   assert last_response.header["Content-Type"].eql?("application/rdf+turtle;charset=utf-8")
  # end

  # def test_request_format_param
  #   # GO JSON
  #   req("", :format => "json")
  #   assert last_response.header["Content-Type"].eql?("application/json;charset=utf-8")

  #   # Try html
  #   req("", :format => "html")
  #   assert last_response.header["Content-Type"].eql?("text/html;charset=utf-8")

  #   # Alright, xml?
  #   req("", :format => "xml")
  #   assert last_response.header["Content-Type"].eql?("application/rdf+xml;charset=utf-8")

  #   # JSONP?
  #   req("", :format => "jsonp")
  #   assert last_response.header["Content-Type"].eql?("application/javascript;charset=utf-8")

  #   # Turtle, beautiful Turtle
  #   req("", :format => "turtle")
  #   assert last_response.header["Content-Type"].eql?("application/rdf+turtle;charset=utf-8")
  # end

  private

  def req(accept = nil, params = {})
    header "Accept", accept unless accept.nil?
    get "/", params
  end
end
