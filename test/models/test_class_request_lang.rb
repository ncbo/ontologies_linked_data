require_relative './test_ontology_common'
require 'request_store'

class TestClassRequestedLang < LinkedData::TestOntologyCommon

  def self.before_suite
    @@old_main_languages = Goo.main_languages
    RequestStore.store[:requested_lang] = nil

    parse
  end

  def self.after_suite
    Goo.main_languages = @@old_main_languages
    RequestStore.store[:requested_lang] = nil
  end

  def self.parse
    new('').submission_parse('INRAETHES', 'Testing skos',
                             'test/data/ontology_files/thesaurusINRAE_nouv_structure.skos', 1,
                             process_rdf: true, index_search: false,
                             run_metrics: false, reasoning: false
    )
  end

  def teardown
    reset_lang
  end

  def test_requested_language_found

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817',
                            requested_lang: :FR)
    assert_equal 'industrialisation', cls.prefLabel
    assert_equal ['développement industriel'], cls.synonym

    properties = cls.properties
    assert_equal ['développement industriel'], properties.select { |x| x.to_s['altLabel'] }.values.first.map(&:to_s)
    assert_equal ['industrialisation'], properties.select { |x| x.to_s['prefLabel'] }.values.first.map(&:to_s)

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817',
                            requested_lang: :EN)
    assert_equal 'industrialization', cls.prefLabel
    assert_equal ['industrial development'], cls.synonym

    properties = cls.properties
    assert_equal ['industrial development'], properties.select { |x| x.to_s['altLabel'] }.values.first.map(&:to_s)
    assert_equal ['industrialization'], properties.select { |x| x.to_s['prefLabel'] }.values.first.map(&:to_s)

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_13078',
                            requested_lang: :FR)
    assert_equal 'carbone renouvelable', cls.prefLabel

  end

  def test_requested_language_not_found

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817',
                            requested_lang: :ES)
    assert_nil cls.prefLabel
    assert_empty cls.synonym

    properties = cls.properties
    assert_empty properties.select { |x| x.to_s['altLabel'] }.values
    assert_empty properties.select { |x| x.to_s['prefLabel'] }.values
  end

  def test_context_language
    cls = get_class('http://opendata.inrae.fr/thesaurusINRAE/c_22817', 'INRAETHES')
    cls.submission.bring_remaining
    cls.submission.ontology.bring_remaining

    # Default portal language
    cls.bring_remaining
    response = MultiJson.load(LinkedData::Serializers::JSON.serialize(cls, all: 'all'))
    assert_equal response["@context"]["@language"], Goo.main_languages.first.to_s
    assert_equal  "http://www.w3.org/2000/01/rdf-schema#parents", response["@context"]["parents"]

    # Request specific language
    response = MultiJson.load(LinkedData::Serializers::JSON.serialize(cls, lang: 'fr'))
    assert_equal response["@context"]["@language"], 'fr'

    response = MultiJson.load(LinkedData::Serializers::JSON.serialize(cls, lang: %w[fr en es]))
    assert_equal response["@context"]["@language"], %w[fr en es]

    # Submission Natural Language
    s = cls.submission
    s.naturalLanguage = %w[fr en]
    s.save

    cls = get_class('http://opendata.inrae.fr/thesaurusINRAE/c_22817', 'INRAETHES')
    cls.submission.bring_remaining
    cls.submission.ontology.bring_remaining

    # Default get submission first Natural Language
    response = MultiJson.load(LinkedData::Serializers::JSON.serialize(cls))
    assert_equal response["@context"]["@language"],  'fr'

    # Request specific language
    response = MultiJson.load(LinkedData::Serializers::JSON.serialize(cls, lang: 'fr'))
    assert_equal response["@context"]["@language"], 'fr'

    response = MultiJson.load(LinkedData::Serializers::JSON.serialize(cls, lang: %w[fr en es]))
    assert_equal response["@context"]["@language"], %w[fr en es]
  end

  def test_request_all_languages

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817',
                            requested_lang: :ALL)

    pref_label_all_languages = { en: 'industrialization', fr: 'industrialisation' }
    assert_includes pref_label_all_languages.values, cls.prefLabel
    assert_equal pref_label_all_languages, cls.prefLabel(include_languages: true)

    synonym_all_languages = { en: ['industrial development'], fr: ['développement industriel'] }

    assert_equal synonym_all_languages.values.flatten.sort, cls.synonym.sort
    assert_equal synonym_all_languages, cls.synonym(include_languages: true)

    properties = cls.properties

    assert_equal synonym_all_languages.values.flatten.sort, properties.select { |x| x.to_s['altLabel'] }.values.first.map(&:to_s).sort
    assert_equal pref_label_all_languages.values.sort, properties.select { |x| x.to_s['prefLabel'] }.values.first.map(&:to_s).sort

    properties = cls.properties(include_languages: true)

    assert_equal synonym_all_languages,
                 properties.select { |x| x.to_s['altLabel'] }.values.first.transform_values{|v| v.map(&:object)}
    assert_equal pref_label_all_languages,
                 properties.select { |x| x.to_s['prefLabel'] }.values.first.transform_values{|v| v.first.object}
  end

  private

  def lang_set(requested_lang: nil, portal_languages: nil)
    Goo.main_languages = portal_languages if portal_languages
    RequestStore.store[:requested_lang] = requested_lang
  end

  def reset_lang
    lang_set requested_lang: nil, portal_languages: @@old_main_languages
  end

  def get_class(cls, ont)
    sub = LinkedData::Models::Ontology.find(ont).first.latest_submission
    LinkedData::Models::Class.find(cls).in(sub).first
  end

  def get_class_by_lang(cls, requested_lang:, portal_languages: nil)
    lang_set requested_lang: requested_lang, portal_languages: portal_languages
    cls = get_class(cls, 'INRAETHES')
    refute_nil cls
    cls.bring_remaining
    cls.bring :unmapped
    cls
  end
end