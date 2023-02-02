require 'minitest/unit'
require "multi_json"
require_relative "../../lib/ontologies_linked_data"
require_relative "../../config/config"

class TestSerializerOutput < MiniTest::Unit::TestCase
  class Car < LinkedData::Models::Base
    model :car, name_with: :model, namespace: :omv
    attribute :model, enforce: [:unique]
  end

  class House < LinkedData::Models::Base
    model :house, name_with: :location, namespace: :rdfs
    attribute :location, enforce: [:unique]
  end

  class Person < LinkedData::Models::Base
    model :person, name_with: :name
    attribute :name, enforce: [:unique]
    attribute :age
    attribute :height
    attribute :carOwned, enforce: [:car]
    attribute :houseOwned, enforce: [House]
  end

  def setup
    @attrs = {name: "Simon", age: 21}
    @car_attrs = {model: "Firebird"}
    @house_attrs = {location: "San Martin"}
    teardown
    @car = Car.new(@car_attrs)
    @car.save
    @house = House.new(@house_attrs)
    @house.save
    @person = Person.new(@attrs)
    @person.carOwned = @car
    @person.houseOwned = @house
    @person.save
  end

  def teardown
    house = House.where(@house_attrs).first rescue nil
    house.delete unless house.nil?
    car = Car.where(@car_attrs).first rescue nil
    car.delete unless car.nil?
    person = Person.where(@attrs).first rescue nil
    person.delete unless person.nil?
  end

  def test_person_to_json
    json = LinkedData::Serializers.serialize(@person, :json)
    reference = MultiJson.load(json)
    assert reference.key?("name")
    assert reference.key?("age")
    assert reference.key?("@type")
    assert reference.key?("@id")
    assert reference.key?("@context")
    assert reference["@context"].key?("@vocab")
    assert reference["@context"].key?("carOwned")
    assert reference["@context"].key?("houseOwned")
  end

  def test_hash_to_json
    hash = {test: "value", name: "testing"}
    json = LinkedData::Serializers.serialize(hash, :json)
    reference = MultiJson.load(json)
    assert reference.key?("test")
    assert reference.key?("name")
  end

  def test_sparql_http_object_serialization
    iri = "http://example.org"
    int = 1
    bool = false
    hash = {iri: iri, int: int, bool: bool}
    json = LinkedData::Serializers.serialize(hash, :json)
    reference = MultiJson.load(json)
    assert reference["iri"].eql?(iri)
    assert reference["int"] == 1
    assert reference["bool"] == false
  end
end
