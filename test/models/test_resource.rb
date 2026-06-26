require_relative "../test_case"
require_relative './test_ontology_common'

class TestResource < LinkedData::TestOntologyCommon

  def self.before_suite
    LinkedData::TestCase.backend_4s_delete

    # Example
    data = %(
          <http://example.org/person1> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/name> "John Doe" .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/age> "30"^^<http://www.w3.org/2001/XMLSchema#integer> .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/gender> "male" .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/email> <mailto:john@example.com> .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/knows> <http://example.org/person3> .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/knows> _:blanknode1 .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/knows> _:blanknode2 .
          <http://example.org/person1> <http://www.w3.org/2004/02/skos/core#altLabel> "test/bonjour"@fr .
          <http://example.org/person1> <http://www.w3.org/2004/02/skos/core#prefLabel> "Person#human"@en .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/birthday> "2024-11-29"^^<http://www.w3.org/2001/XMLSchema#date> .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/homepage> "http://person1.org/test" .

          _:blanknode1 <http://xmlns.com/foaf/0.1/name> "Jane Smith" .
          _:blanknode1 <http://xmlns.com/foaf/0.1/age> "25"^^<http://www.w3.org/2001/XMLSchema#integer> .
          _:blanknode1 <http://xmlns.com/foaf/0.1/gender> "female" .
          _:blanknode1 <http://xmlns.com/foaf/0.1/email> <mailto:jane@example.com> .
          _:blanknode2 <http://xmlns.com/foaf/0.1/name> "Jane Smith 2" .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/hasInterest> "Hiking" .
          <http://example.org/person1> <http://xmlns.com/foaf/0.1/hasInterest> "Cooking" .

          <http://example.org/person2> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> .
          <http://example.org/person2> <http://xmlns.com/foaf/0.1/name> "Alice Cooper" .
          <http://example.org/person2> <http://xmlns.com/foaf/0.1/age> "35"^^<http://www.w3.org/2001/XMLSchema#integer> .
          <http://example.org/person2> <http://xmlns.com/foaf/0.1/gender> "female" .
          <http://example.org/person2> <http://xmlns.com/foaf/0.1/email> <mailto:alice@example.com> .
          <http://example.org/person2> <http://xmlns.com/foaf/0.1/hasSkill> _:skill1, _:skill2 .
          _:skill1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Programming" .
          _:skill1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:skill2 .
          _:skill2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Data Analysis" .
          _:skill2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          <http://example.org/person2> <http://xmlns.com/foaf/0.1/hasInterest> "Hiking" .
          <http://example.org/person2> <http://xmlns.com/foaf/0.1/hasInterest> "Cooking" .
          <http://example.org/person2> <http://xmlns.com/foaf/0.1/hasInterest> "Photography" .

          <http://example2.org/person2> <http://xmlns.com/foaf/0.1/mother> <http://example.org/person1> .
          <http://example2.org/person5> <http://xmlns.com/foaf/0.1/brother> <http://example.org/person1> .
          <http://example2.org/person5> <http://xmlns.com/foaf/0.1/friend> <http://example.org/person1> .

        )

    graph = "http://example.org/test_graph"
    Goo.sparql_data_client.execute_append_request(graph, data, '')

    # instance the resource model
    @@resource1 = LinkedData::Models::Resource.new("http://example.org/test_graph", "http://example.org/person1")
  end

  def self.after_suite
    Goo.sparql_data_client.delete_graph("http://example.org/test_graph")
    Goo.sparql_data_client.delete_graph("http://data.bioontology.org/ontologies/TEST-TRIPLES/submissions/2")
    @resource1&.destroy
  end

  def test_generate_model
    @object = @@resource1.to_object
    @model = @object.class

    assert_equal LinkedData::Models::Base, @model.ancestors[1]

    @model.model_settings[:attributes].map do |property, val|
      property_url = "#{val[:property]}#{property}"
      assert_includes @@resource1.to_hash.keys, property_url

      hash_value = @@resource1.to_hash[property_url]
      object_value = @object.send(property.to_sym)
      if property.to_sym == :knows
        assert_equal  hash_value.map{|x| x.is_a?(Hash) ? x.values : x}.flatten.map(&:to_s).sort,
                      object_value.map{|x| x.is_a?(String) ? x : x.to_h.values}.flatten.map(&:to_s).sort
      elsif property.to_sym == :birthday
        assert_equal Array(hash_value).map(&:object), Array(object_value)
      else
        assert_equal Array(hash_value).map(&:to_s), Array(object_value).map(&:to_s)
      end
    end

    assert_equal "http://example.org/person1", @object.id.to_s

    assert_equal Goo.namespaces[:foaf][:Person].to_s, @model.type_uri.to_s
  end

  def test_resource_fetch_related_triples
    result = @@resource1.to_hash
    assert_instance_of Hash, result

    refute_empty result

    expected_result = {
      "id" => "http://example.org/person1",
      "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" => "http://xmlns.com/foaf/0.1/Person",
      "http://xmlns.com/foaf/0.1/gender" => "male",
      "http://xmlns.com/foaf/0.1/hasInterest" => %w[Cooking Hiking],
      "http://xmlns.com/foaf/0.1/age" => "30",
      "http://xmlns.com/foaf/0.1/birthday"=>"2024-11-29",
      "http://xmlns.com/foaf/0.1/email" => "mailto:john@example.com",
      "http://www.w3.org/2004/02/skos/core#altLabel" => "test/bonjour",
      "http://www.w3.org/2004/02/skos/core#prefLabel" => "Person#human",
      "http://xmlns.com/foaf/0.1/knows" =>
        ["http://example.org/person3",
        {
          "http://xmlns.com/foaf/0.1/gender" => "female",
          "http://xmlns.com/foaf/0.1/age" => "25",
          "http://xmlns.com/foaf/0.1/email" => "mailto:jane@example.com",
          "http://xmlns.com/foaf/0.1/name" => "Jane Smith"
        },
        {
          "http://xmlns.com/foaf/0.1/name" => "Jane Smith 2"
          }
        ],
      "http://xmlns.com/foaf/0.1/name" => "John Doe",
      "http://xmlns.com/foaf/0.1/homepage"=>"http://person1.org/test",
      "reverse" => {
        "http://example2.org/person2" => "http://xmlns.com/foaf/0.1/mother",
        "http://example2.org/person5" => ["http://xmlns.com/foaf/0.1/brother", "http://xmlns.com/foaf/0.1/friend"]
      }
    }
    result = JSON.parse(MultiJson.dump(result))
    a = sort_nested_hash(result)
    b = sort_nested_hash(expected_result)
    assert_equal b, a
  end

  def test_resource_serialization_json
    result = @@resource1.to_json

    refute_empty result
    expected_result = %(
      {
        "@context": {"ns0": "http://example.org/", "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#", "foaf": "http://xmlns.com/foaf/0.1/", "ns1": "http://example2.org/", "skos":"http://www.w3.org/2004/02/skos/core#"},
        "@graph":
          [
            {
              "@id": "ns0:person1",
              "@type": "foaf:Person",
              "foaf:name": "John Doe",
              "foaf:birthday":{"@value":"2024-11-29", "@type":"http://www.w3.org/2001/XMLSchema#date"},
              "foaf:hasInterest":["Cooking", "Hiking"],
              "foaf:age": {"@type": "http://www.w3.org/2001/XMLSchema#integer", "@value": "30"},
              "foaf:email": {"@id": "mailto:john@example.com"},
              "foaf:gender": "male",
              "skos:altLabel":{"@value":"test/bonjour", "@language":"fr"},
              "skos:prefLabel":{"@value":"Person#human", "@language":"en"},
              "foaf:knows": [{"@id": "ns0:person3"}, {"@id": "_:g447140"}, {"@id": "_:g447160"}],
              "foaf:homepage":"http://person1.org/test"},
          { 
            "@id": "_:g447140",
            "foaf:name": "Jane Smith",
            "foaf:age": {"@type": "http://www.w3.org/2001/XMLSchema#integer", "@value": "25"},
            "foaf:email": {"@id": "mailto:jane@example.com"},
            "foaf:gender": "female"
          },
          {"@id": "_:g447160", "foaf:name": "Jane Smith 2"},
          {"@id": "ns1:person5", "foaf:friend": {"@id": "ns0:person1"}, "foaf:brother": {"@id": "ns0:person1"}},
          {"@id": "ns1:person2", "foaf:mother": {"@id": "ns0:person1"}}
        ]
      }
    )
    result = JSON.parse(result.gsub(' ', '').gsub("\n", '').gsub(/_:g\d+/, 'blanke_nodes'))
    expected_result = JSON.parse(expected_result.gsub(' ', '').gsub("\n", '').gsub(/_:g\d+/, 'blanke_nodes'))

    a = sort_nested_hash(result)
    b = sort_nested_hash(expected_result)

    assert_equal b, a
  end

  def test_resource_serialization_xml
    result = @@resource1.to_xml

    refute_empty result
    expected_result = %(<?xml version="1.0" encoding="UTF-8"?>
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ns0="http://example.org/" xmlns:foaf="http://xmlns.com/foaf/0.1/" xmlns:skos="http://www.w3.org/2004/02/skos/core#">
        <foaf:Person rdf:about="http://example.org/person1">
          <foaf:birthday rdf:datatype="http://www.w3.org/2001/XMLSchema#date">2024-11-29</foaf:birthday>
          <foaf:gender>male</foaf:gender>
          <foaf:hasInterest>Cooking</foaf:hasInterest>
          <foaf:hasInterest>Hiking</foaf:hasInterest>
          <foaf:age rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">30</foaf:age>
          <foaf:email rdf:resource="mailto:john@example.com"/>
          <skos:altLabel xml:lang="fr">test/bonjour</skos:altLabel>
          <skos:prefLabel xml:lang="en">Person#human</skos:prefLabel>
          <foaf:knows rdf:resource="http://example.org/person3"/>
          <foaf:knows>
            <rdf:Description rdf:nodeID="g447100">
              <foaf:gender>female</foaf:gender>
              <foaf:age rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">25</foaf:age>
              <foaf:email rdf:resource="mailto:jane@example.com"/>
              <foaf:name>Jane Smith</foaf:name>
            </rdf:Description>
          </foaf:knows>
          <foaf:knows>
            <rdf:Description rdf:nodeID="g447120">
              <foaf:name>Jane Smith 2</foaf:name>
            </rdf:Description>
          </foaf:knows>
          <foaf:name>John Doe</foaf:name>
          <foaf:homepage>http://person1.org/test</foaf:homepage>
        </foaf:Person>
        <rdf:Description rdf:about="http://example2.org/person2">
          <foaf:mother rdf:resource="http://example.org/person1"/>
        </rdf:Description>
        <rdf:Description rdf:about="http://example2.org/person5">
          <foaf:brother rdf:resource="http://example.org/person1"/>
          <foaf:friend rdf:resource="http://example.org/person1"/>
        </rdf:Description>
      </rdf:RDF>           
    )
    a = result.gsub(' ', '').gsub(/rdf:nodeID="[^"]*"/, '').split("\n").reject(&:empty?)
    b = expected_result.gsub(' ', '').gsub(/rdf:nodeID="[^"]*"/, '').split("\n").reject(&:empty?)

    assert_equal b.sort, a.sort
  end

  def test_resource_serialization_ntriples
    result = @@resource1.to_ntriples

    refute_empty result

    expected_result = %(
      <http://example.org/person1> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/birthday> "2024-11-29"^^<http://www.w3.org/2001/XMLSchema#date> .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/gender> "male" .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/hasInterest> "Cooking" .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/hasInterest> "Hiking" .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/age> "30"^^<http://www.w3.org/2001/XMLSchema#integer> .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/email> <mailto:john@example.com> .
      <http://example.org/person1> <http://www.w3.org/2004/02/skos/core#altLabel> "test/bonjour"@fr .
      <http://example.org/person1> <http://www.w3.org/2004/02/skos/core#prefLabel> "Person#human"@en .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/knows> <http://example.org/person3> .
      _:g447260 <http://xmlns.com/foaf/0.1/gender> "female" .
      _:g447260 <http://xmlns.com/foaf/0.1/age> "25"^^<http://www.w3.org/2001/XMLSchema#integer> .
      _:g447260 <http://xmlns.com/foaf/0.1/email> <mailto:jane@example.com> .
      _:g447260 <http://xmlns.com/foaf/0.1/name> "Jane Smith" .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/knows> _:g447260 .
      _:g447280 <http://xmlns.com/foaf/0.1/name> "Jane Smith 2" .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/knows> _:g447280 .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/name> "John Doe" .
      <http://example.org/person1> <http://xmlns.com/foaf/0.1/homepage> "http://person1.org/test" .
      <http://example2.org/person2> <http://xmlns.com/foaf/0.1/mother> <http://example.org/person1> .
      <http://example2.org/person5> <http://xmlns.com/foaf/0.1/brother> <http://example.org/person1> .
      <http://example2.org/person5> <http://xmlns.com/foaf/0.1/friend> <http://example.org/person1> .
    )
    a = result.gsub(' ', '').gsub(/_:g\d+/, 'blanke_nodes').split("\n").reject(&:empty?)
    b = expected_result.gsub(' ', '').gsub(/_:g\d+/, 'blanke_nodes').split("\n").reject(&:empty?)

    assert_equal b.sort, a.sort
  end

  def test_resource_serialization_turtle
    result = @@resource1.to_turtle
    refute_empty result
    expected_result = %(
      @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
      @prefix ns0: <http://example.org/> .
      @prefix foaf: <http://xmlns.com/foaf/0.1/> .
      @prefix skos: <http://www.w3.org/2004/02/skos/core#> .
      @prefix ns1: <http://example2.org/> .

      ns0:person1
          a foaf:Person ;
          skos:altLabel "test/bonjour"@fr ;
          skos:prefLabel "Person#human"@en ;
          foaf:age 30 ;
          foaf:birthday "2024-11-29"^^<http://www.w3.org/2001/XMLSchema#date> ;
          foaf:email <mailto:john@example.com> ;
          foaf:gender "male" ;
          foaf:hasInterest "Cooking", "Hiking" ;
          foaf:homepage "http://person1.org/test" ;
          foaf:knows ns0:person3, [
              foaf:age 25 ;
              foaf:email <mailto:jane@example.com> ;
              foaf:gender "female" ;
              foaf:name "Jane Smith"
          ], [
              foaf:name "Jane Smith 2"
          ] ;
          foaf:name "John Doe" .

      ns1:person2
          foaf:mother ns0:person1 .

      ns1:person5
          foaf:brother ns0:person1 ;
          foaf:friend ns0:person1 .
    )
    a = result.gsub(' ', '').split("\n").reject(&:empty?)
    b = expected_result.gsub(' ', '').split("\n").reject(&:empty?)

    assert_equal b.sort, a.sort
  end

  private

  def sort_nested_hash(hash)
    sorted_hash = {}

    hash.each do |key, value|
      if value.is_a?(Hash)
        sorted_hash[key] = sort_nested_hash(value)
      elsif value.is_a?(Array)
        sorted_hash[key] = value.map { |item| item.is_a?(Hash) ? sort_nested_hash(item) : item }.sort_by { |item| item.to_s }
      else
        sorted_hash[key] = value
      end
    end

    sorted_hash.sort.to_h
  end

end