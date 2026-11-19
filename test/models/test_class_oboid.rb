require 'minitest/autorun'
require 'mocha/minitest'
require_relative '../../lib/ontologies_linked_data'

# These tests use real models and serializers without Solr or a triplestore.
class TestClassOboId < Minitest::Test
  CLASS = LinkedData::Models::Class
  NCIT_IRI = 'http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl'.freeze
  NCIT_CLASS_IRI = "#{NCIT_IRI}#C20047".freeze

  def setup
    Goo.expects(:sparql_query_client).never
    CLASS.expects(:search_client).never
    LinkedData.settings.stubs(:rest_url_prefix).returns('http://data.bioontology.org/')
    LinkedData.settings.stubs(:ui_host).returns('bioportal.bioontology.org')
  end

  def test_derivation_preserves_existing_identifiers_and_index_flags
    cases = [
      ['http://purl.obolibrary.org/obo/GO_0050892', nil, 'GO', 'GO:0050892', true],
      [NCIT_CLASS_IRI, NCIT_IRI, 'NCIT', 'NCIT:C20047', true],
      ['http://purl.obolibrary.org/obo/CHEBI_46195', 'http://example.org/dron', 'DRON', 'CHEBI:46195', nil],
      ['http://external.org/word', 'http://example.org/ontology', 'TEST', nil, nil],
      [NCIT_CLASS_IRI, nil, 'NCIT', nil, nil],
      ['http://edamontology.org/data_1598', nil, 'EDAM', 'data:1598', nil],
      ['http://example.org/go_0001', nil, 'GO', 'go:0001', true],
      ['http://example.org/part_GO_0001', nil, 'GO', 'GO:0001', true],
      ['http://example.org/ont/nested/Code', 'http://example.org/ont', 'TEST', 'TEST:Code', true],
      ['http://example.org/ont#Code', 'http://example.org/ont', 'NDF-RT', 'NDF-RT:Code', true],
      ['http://purl.obolibrary.org/obo/NCIT_C20047', nil, 'NCIT', nil, nil]
    ]

    cases.each do |iri, ontology_iri, acronym, identifier, acronym_match|
      cls = build_class(iri: iri, ontology_iri: ontology_iri, acronym: acronym)
      doc = {}
      cls.set_oboid_fields(iri, ontology_iri, acronym, doc)
      expected = identifier ? { oboId: identifier } : {}
      expected[:idAcronymMatch] = true if acronym_match
      assert_equal expected, doc, iri
      identifier ? assert_equal(identifier, cls.oboId, iri) : assert_nil(cls.oboId, iri)
    end
  end

  def test_indexing_and_class_details_use_the_same_value_independently_of_notation
    cls = build_class
    cls.notation = 'Thesaurus:C20047'
    prepare_indexing(cls)

    doc = cls.index_doc

    assert_equal 'Thesaurus:C20047', doc[:notation]
    assert_equal 'NCIT:C20047', doc[:oboId]
    assert_equal cls.oboId, doc[:oboId]
    assert_equal true, doc[:idAcronymMatch]
  end

  def test_imported_identifier_does_not_clear_a_notation_acronym_match
    cls = build_class(iri: 'http://purl.obolibrary.org/obo/CHEBI_46195', acronym: 'DRON')
    cls.notation = 'DRON:local'
    prepare_indexing(cls)

    doc = cls.index_doc

    assert_equal 'CHEBI:46195', doc[:oboId]
    assert_equal true, doc[:idAcronymMatch]
  end

  def test_imported_prefix_does_not_add_an_acronym_match
    cls = build_class(iri: 'http://purl.obolibrary.org/obo/CHEBI_46195', acronym: 'DRON')
    cls.notation = 'CHEBI:46195'
    prepare_indexing(cls)

    refute cls.index_doc.key?(:idAcronymMatch)
  end

  def test_property_only_index_updates_do_not_add_identifier_fields
    cls = build_class
    cls.stubs(:properties_for_indexing).returns(property: ['text'])

    assert_equal({ property: ['text'], propertyRaw: nil }, cls.index_doc([:properties]))
  end

  def test_ordinary_obo_identifier_does_not_load_submission_metadata
    cls = CLASS.new(id: RDF::URI.new('http://purl.obolibrary.org/obo/GO_0050892'))
    cls.persistent = true
    cls.expects(:bring).never

    assert_equal 'GO:0050892', cls.oboId
  end

  def test_missing_ontology_iri_does_not_use_the_rest_submission_url
    cls = build_class(ontology_iri: nil)
    cls.submission.id = RDF::URI.new(NCIT_IRI)
    cls.notation = 'Thesaurus:C20047'

    assert_nil cls.oboId
  end

  def test_missing_submission_does_not_invent_an_identifier
    cls = CLASS.new(id: RDF::URI.new(NCIT_CLASS_IRI))

    assert_nil cls.oboId
  end

  def test_fallback_loads_an_unloaded_ontology_iri_once_for_a_shared_submission
    cls = build_class(ontology_iri: nil)
    sub = cls.submission
    sub.modified_attributes.delete(:uri)
    sub.loaded_attributes.delete(:uri)
    sub.persistent = true
    loads = []
    sub.define_singleton_method(:bring) do |*attrs|
      loads << attrs
      self.uri = RDF::URI.new(NCIT_IRI)
      self
    end
    second = CLASS.new(id: RDF::URI.new("#{NCIT_IRI}#C16670"), submission: sub)

    assert_equal 'NCIT:C20047', cls.oboId
    assert_equal 'NCIT:C16670', second.oboId
    assert_equal [[:uri]], loads
  end

  def test_a_loaded_but_absent_ontology_iri_is_not_reloaded_for_each_class
    cls = build_class(ontology_iri: nil)
    sub = cls.submission
    sub.modified_attributes.delete(:uri)
    sub.loaded_attributes.add(:uri)
    sub.persistent = true
    sub.expects(:bring).never
    second = CLASS.new(id: RDF::URI.new("#{NCIT_IRI}#C16670"), submission: sub)

    assert_nil cls.oboId
    assert_nil second.oboId
  end

  def test_preloaded_metadata_is_not_loaded_again
    cls = build_class
    cls.submission.expects(:bring).never
    cls.submission.ontology.expects(:bring).never

    2.times { assert_equal 'NCIT:C20047', cls.oboId }
  end

  def test_computed_value_tracks_metadata_changes
    cls = build_class
    assert_equal 'NCIT:C20047', cls.oboId

    cls.submission.ontology.acronym = 'OTHER'
    assert_equal 'OTHER:C20047', cls.oboId

    cls.submission.uri = nil
    assert_nil cls.oboId
  end

  def test_default_json_includes_identifier_and_preserves_existing_metadata
    result = json(build_class)

    assert_equal 'NCIT:C20047', result['oboId']
    assert_equal 'Label', result['prefLabel']
    assert_equal false, result['obsolete']
    assert_equal NCIT_CLASS_IRI, result['@id']
    assert_equal RDF::OWL.Class.to_s, result['@type']
    assert result.key?('links')
    assert result.key?('@context')
    assert result.key?('created'), 'Existing nil fields must retain their behavior'
  end

  def test_explicit_selection_keeps_its_existing_projection_semantics
    cls = build_class
    assert_equal 'NCIT:C20047', json(cls, only: [:oboId])['oboId']
    refute json(cls, only: [:oboId]).key?('prefLabel')
    refute json(cls, only: [:prefLabel]).key?('oboId')
  end

  def test_include_all_serializes_computed_identifier
    cls = build_class
    cls.stubs(:properties).returns({})
    cls.stubs(:childrenCount).returns(0)

    assert_equal 'NCIT:C20047', json(cls, all: true)['oboId']
  end

  def test_absent_identifier_is_omitted_from_default_and_explicit_responses
    cls = build_class(iri: 'http://external.org/word')

    refute json(cls).key?('oboId')
    refute json(cls, only: [:oboId]).key?('oboId')
    assert json(cls).key?('created'), 'Only oboId should opt into nil omission'
  end

  def test_xml_uses_the_same_identifier_and_omission_rules
    present = LinkedData::Serializers::XML.serialize(build_class, only: [:oboId])
    absent = LinkedData::Serializers::XML.serialize(build_class(ontology_iri: nil), only: [:oboId])

    assert_includes present, '<oboId>NCIT:C20047</oboId>'
    refute_includes absent, '<oboId'
  end

  def test_nested_classes_expose_their_own_identifier
    parent = build_class
    parent.parents = [build_class(iri: 'http://purl.obolibrary.org/obo/CHEBI_46195')]

    result = json(parent, only: [:oboId, :parents])

    assert_equal 'NCIT:C20047', result['oboId']
    assert_equal 'CHEBI:46195', result['parents'].first['oboId']
  end

  def test_search_objects_use_stored_values_and_retain_metadata
    cls = search_class(oboId: 'STORED:identifier')
    result = json(cls)

    assert_equal 'STORED:identifier', result['oboId']
    assert_equal false, result['obsolete']
    assert_equal 'prefLabel', result['matchType']
    assert_equal 'ONTOLOGY', result['ontologyType']
    assert_equal false, result['provisional']
    assert result.key?('links')
    assert result.key?('@context')
  end

  def test_search_objects_without_a_stored_value_do_not_recompute_it
    [search_class, search_class(oboId: nil)].each do |cls|
      refute json(cls).key?('oboId')
      refute json(cls, only: [:oboId]).key?('oboId')
    end
  end

  def test_load_plan_includes_metadata_but_does_not_query_an_oboid_predicate
    cls = build_class
    [[], [:oboId], [:all]].each do |selection|
      attrs = CLASS.goo_attrs_to_load(selection)
      sub_attrs = attrs.find { |attr| attr.is_a?(Hash) && attr.key?(:submission) }[:submission]
      assert_includes sub_attrs, :uri
      assert_includes sub_attrs, { ontology: [:acronym] }

      _, predicates, = Goo::SPARQL::Loader.send(:get_includes, cls.submission, [], attrs, CLASS)
      refute predicates.key?(:oboId)
    end
    refute_includes CLASS.attributes, :oboId
  end

  private

  def build_class(iri: NCIT_CLASS_IRI, ontology_iri: NCIT_IRI, acronym: 'NCIT')
    ontology = LinkedData::Models::Ontology.new(
      acronym: acronym, ontologyType: LinkedData::Models::OntologyType.new(code: 'ONTOLOGY')
    )
    submission = LinkedData::Models::OntologySubmission.new(
      id: RDF::URI.new("http://data.bioontology.org/ontologies/#{acronym}/submissions/1"),
      submissionId: 1, ontology: ontology,
      uri: ontology_iri && RDF::URI.new(ontology_iri),
      hasOntologyLanguage: LinkedData::Models::OntologyFormat.new(acronym: 'OWL'),
      naturalLanguage: []
    )
    CLASS.new(id: RDF::URI.new(iri), submission: submission, prefLabel: 'Label', obsolete: false)
  end

  def prepare_indexing(cls)
    cls.stubs(:childrenCount).returns(0)
    cls.stubs(:properties).returns({})
    cls.stubs(:properties_for_indexing).returns(nil)
    CLASS.stubs(:ancestors_cache).returns({})
    CLASS.stubs(:ontology_rank_for_index).returns(0.0)
  end

  def search_class(**fields)
    # Search builds read-only submissions with no ontology IRI to derive from.
    ontology = LinkedData::Models::Ontology.read_only(id: 'http://data.bioontology.org/ontologies/GO', acronym: 'GO')
    submission = LinkedData::Models::OntologySubmission.read_only(id: 'http://data.bioontology.org/ontologies/GO/submissions/1', ontology: ontology)
    CLASS.read_only({ id: 'http://purl.obolibrary.org/obo/GO_0050892', submission: submission,
                      prefLabel: 'Label', obsolete: false, matchType: 'prefLabel',
                      ontologyType: 'ONTOLOGY', provisional: false }.merge(fields))
  end

  def json(object, **options)
    MultiJson.load(LinkedData::Serializers::JSON.serialize(object, { lang: :en }.merge(options)))
  end
end
