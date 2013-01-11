require "test/unit"
require "json"
require_relative "../../lib/ontologies_linked_data"

class Person
  def initialize(name, age, height = 6)
    @name = name
    @age = age
    @height = height
  end

  def person_is_how_old
    "#{@name} is #{@age}"
  end

  def name_upcase
    @name.upcase
  end

  def relative_age
    if @age < 10
      "young"
    elsif @age < 20
      "teenager"
    elsif @age > 20
      "old"
    end
  end

  def serializable_methods
    [:relative_age, :name_upcase, :person_is_how_old]
  end
end

class TestSerializerOutput < Test::Unit::TestCase
  PERSON = Person.new("Simon", 21)

  def test_json
    json = LinkedData::Serializers.serialize(PERSON, :json)
    reference = {"name"=>"Simon","height"=>6,"age"=>21}
    assert_equal reference, JSON.parse(json)
  end

  def test_json_with_options
    json = LinkedData::Serializers.serialize(PERSON, :json, :only => [:name])
    reference = '{"name":"Simon"}'
    assert_equal reference, json
  end

end