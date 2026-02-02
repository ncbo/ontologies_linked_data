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
    new('').submission_parse('APTO', 'Test parse ontology has iri label',
                             'test/data/ontology_files/apto.owl', 1,
                             process_rdf: true, index_search: false,
                             run_metrics: false, reasoning: false
    )
  end

  def teardown
    reset_lang
  end

  def test_parse_ontology_has_iri_label
    cls_labels_1 = get_class_by_lang('http://aims.fao.org/aos/agrovoc/c_3376', 'APTO',
                                     requested_lang: :'pt-br').label

    assert_includes cls_labels_1 , 'Hortaliça de folha'

    cls_labels_2 = get_class_by_lang('http://aims.fao.org/aos/agrovoc/c_3376', 'APTO',
                                     requested_lang: :en).label

    assert_includes cls_labels_2,  'Leaf vegetable'
  end

  def test_requested_language_found

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817', 'INRAETHES',
                            requested_lang: :FR)
    assert_equal 'industrialisation', cls.prefLabel
    assert_equal ['développement industriel'], cls.synonym

    properties = cls.properties
    assert_equal ['développement industriel'], properties.select { |x| x.to_s['altLabel'] }.values.first.map(&:to_s)
    assert_equal ['industrialisation'], properties.select { |x| x.to_s['prefLabel'] }.values.first.map(&:to_s)

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817', 'INRAETHES',
                            requested_lang: :EN)
    assert_equal 'industrialization', cls.prefLabel
    assert_equal ['industrial development'], cls.synonym

    properties = cls.properties
    assert_equal ['industrial development'], properties.select { |x| x.to_s['altLabel'] }.values.first.map(&:to_s)
    assert_equal ['industrialization'], properties.select { |x| x.to_s['prefLabel'] }.values.first.map(&:to_s)

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_13078', 'INRAETHES',
                            requested_lang: :FR)
    assert_equal 'carbone renouvelable', cls.prefLabel

  end

  def test_requeststore_not_set
    skip 'Needs to be fixed in the future for Virtuoso'
    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817', 'INRAETHES',
                            requested_lang: nil)
    assert_equal 'industrialization', cls.prefLabel
    assert_equal cls.prefLabel, cls.prefLabel(include_languages: true)
    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817', 'INRAETHES',
                            requested_lang: :ALL)
    assert_equal 'industrialization', cls.prefLabel
    assert_equal Hash, cls.prefLabel(include_languages: true).class
    assert_equal 2, cls.prefLabel(include_languages: true).keys.length
    assert_equal 'industrialization', cls.prefLabel(include_languages: true)[:en]
    assert_equal 'industrialisation', cls.prefLabel(include_languages: true)[:fr]
  end

  def test_requested_language_not_found

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817', 'INRAETHES',
                            requested_lang: :ES)
    assert_nil cls.prefLabel
    assert_empty cls.synonym

    properties = cls.properties
    assert_empty properties.select { |x| x.to_s['altLabel'] }.values
    assert_empty properties.select { |x| x.to_s['prefLabel'] }.values
  end

  def test_request_multiple_languages

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817', 'INRAETHES',
                            requested_lang: [:EN, :FR])
    pref_label_all_languages = { en: 'industrialization', fr: 'industrialisation' }
    assert_includes pref_label_all_languages.values, cls.prefLabel
    assert_equal pref_label_all_languages, cls.prefLabel(include_languages: true)
  end

  def test_request_all_languages

    cls = get_class_by_lang('http://opendata.inrae.fr/thesaurusINRAE/c_22817', 'INRAETHES',
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

  def get_class_by_lang(cls, ont, requested_lang:, portal_languages: nil)
    lang_set requested_lang: requested_lang, portal_languages: portal_languages
    cls = get_class(cls, ont)
    refute_nil cls
    cls.bring_remaining
    cls.bring :unmapped
    cls
  end
end