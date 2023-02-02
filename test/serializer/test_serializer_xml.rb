require 'minitest/unit'
require "date"
require "multi_json"
require_relative "../../lib/ontologies_linked_data"

class TestSerializerXML < MiniTest::Unit::TestCase
  class Person
    attr_accessor :name
    def initialize(name)
      @name = name
    end
  end

  PERSON = Person.new("Simon")
  PEOPLE = [Person.new("Simon"), Person.new("Gloria")]
  DATE = DateTime.now

  USER_XML = <<-EOS.gsub(/\s+/, "")
    <user>
      <created>#{DATE.to_s}</created>
      <email>alejandra@example.com</email>
      <username>alejandra</username>
      <roleCollection>
        <role>LIBRARIAN</role>
      </roleCollection>
      <id>http://data.bioontology.org/metadata/user/alejandra</id>
    </user>
  EOS

  USERS_XML = <<-EOS.gsub(/\s+/, "")
    <userCollection>
      <user>
        <created>#{DATE.to_s}</created>
        <email>alejandra@example.com</email>
        <username>alejandra</username>
        <roleCollection>
          <role>LIBRARIAN</role>
        </roleCollection>
        <id>http://data.bioontology.org/metadata/user/alejandra</id>
      </user>
      <user>
        <created>#{DATE.to_s}</created>
        <email>alessandra@example.com</email>
        <username>alessandra</username>
        <roleCollection>
          <role>LIBRARIAN</role>
        </roleCollection>
        <id>http://data.bioontology.org/metadata/user/alessandra</id>
      </user>
      <user>
        <created>#{DATE.to_s}</created>
        <email>amelia@example.com</email>
        <username>amelia</username>
        <roleCollection>
          <role>LIBRARIAN</role>
        </roleCollection>
        <id>http://data.bioontology.org/metadata/user/amelia</id>
      </user>
      <user>
        <created>#{DATE.to_s}</created>
        <email>anderson@example.com</email>
        <username>anderson</username>
        <roleCollection>
          <role>LIBRARIAN</role>
        </roleCollection>
        <id>http://data.bioontology.org/metadata/user/anderson</id>
      </user>
      <user>
        <created>#{DATE.to_s}</created>
        <email>anisa@example.com</email>
        <username>anisa</username>
        <roleCollection>
          <role>LIBRARIAN</role>
        </roleCollection>
        <id>http://data.bioontology.org/metadata/user/anisa</id>
      </user>
      <user>
        <created>#{DATE.to_s}</created>
        <email>arlena@example.com</email>
        <username>arlena</username>
        <roleCollection>
          <role>LIBRARIAN</role>
        </roleCollection>
        <id>http://data.bioontology.org/metadata/user/arlena</id>
      </user>
    </userCollection>
  EOS

  PERSON_XML = <<-EOS.gsub(/\s+/, "")
    <?xml version="1.0" encoding="UTF-8"?>
    <person>
      <name>Simon</name>
    </person>
  EOS

  PEOPLE_XML = <<-EOS.gsub(/\s+/, "")
    <?xml version="1.0" encoding="UTF-8"?>
    <personCollection>
      <person>
        <name>Simon</name>
      </person>
      <person>
        <name>Gloria</name>
      </person>
    </personCollection>
  EOS

  NIL_XML = <<-EOS.gsub(/\s+/, "")
    <?xml version="1.0" encoding="UTF-8"?>
    <empty/>
  EOS

  USERS_HASH = {
    :created=>DATE,
    :email=>"alejandra@example.com",
    :username=>"alejandra",
    :role=>["LIBRARIAN"],
    :id=>"http://data.bioontology.org/metadata/user/alejandra"
  }

  USERS_ARRAY = [
   {:created=>DATE,
    :email=>"alejandra@example.com",
    :username=>"alejandra",
    :role=>["LIBRARIAN"],
    :id=>"http://data.bioontology.org/metadata/user/alejandra"},
   {:created=>DATE,
    :email=>"alessandra@example.com",
    :username=>"alessandra",
    :role=>["LIBRARIAN"],
    :id=>"http://data.bioontology.org/metadata/user/alessandra"},
   {:created=>DATE,
    :email=>"amelia@example.com",
    :username=>"amelia",
    :role=>["LIBRARIAN"],
    :id=>"http://data.bioontology.org/metadata/user/amelia"},
   {:created=>DATE,
    :email=>"anderson@example.com",
    :username=>"anderson",
    :role=>["LIBRARIAN"],
    :id=>"http://data.bioontology.org/metadata/user/anderson"},
   {:created=>DATE,
    :email=>"anisa@example.com",
    :username=>"anisa",
    :role=>["LIBRARIAN"],
    :id=>"http://data.bioontology.org/metadata/user/anisa"},
   {:created=>DATE,
    :email=>"arlena@example.com",
    :username=>"arlena",
    :role=>["LIBRARIAN"],
    :id=>"http://data.bioontology.org/metadata/user/arlena"}
  ]

  def test_hash_to_xml
    xml = LinkedData::Serializers::XML.send("convert_hash", USERS_HASH, "user")
    assert_equal USER_XML, xml.to_s.gsub(/\s+/, "")
  end

  def test_array_to_xml
    xml = LinkedData::Serializers::XML.send("convert_array", USERS_ARRAY, "user")
    assert_equal USERS_XML, xml.to_s.gsub(/\s+/, "")
  end

  def test_person_to_xml
    xml = LinkedData::Serializers::XML.serialize(PERSON, {})
    assert_equal PERSON_XML, xml.to_s.gsub(/\s+/, "")
  end

  def test_people_to_xml
    xml = LinkedData::Serializers::XML.serialize(PEOPLE, {})
    assert_equal PEOPLE_XML, xml.to_s.gsub(/\s+/, "")
  end

  def test_nil_to_xml
    xml = LinkedData::Serializers::XML.serialize(nil, {})
    assert_equal NIL_XML, xml.to_s.gsub(/\s+/, "")
  end

end
