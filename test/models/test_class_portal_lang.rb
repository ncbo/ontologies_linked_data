require_relative './test_ontology_common'
class TestClassPortalLang < LinkedData::TestOntologyCommon

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
    new('').submission_parse('AGROOE', 'AGROOE Test extract metadata ontology',
                              './test/data/ontology_files/agrooeMappings-05-05-2016.owl', 1,
                              process_rdf: true, index_search: false,
                              run_metrics: false, reasoning: true)
  end

  def test_map_attribute_found
    cls = parse_and_get_class lang: [:FR]
    cls.bring :unmapped
    LinkedData::Models::Class.map_attributes(cls)
    assert_equal ['entité matérielle detaillée'], cls.label
    assert_includes ['skos prefLabel fr', 'skos prefLabel rien'], cls.prefLabel
    assert_equal ['entité fra', 'entite rien'].sort, cls.synonym.sort
  end

  def test_map_attribute_not_found
    cls = parse_and_get_class lang: [:ES]
    cls.bring :unmapped
    LinkedData::Models::Class.map_attributes(cls)
    assert_empty cls.label
    assert_equal 'skos prefLabel rien', cls.prefLabel
    assert_equal ['entita esp', 'entite rien'].sort, cls.synonym.sort
  end

  def test_map_attribute_secondary_lang
    cls = parse_and_get_class lang: %i[ES FR]
    cls.bring :unmapped
    LinkedData::Models::Class.map_attributes(cls)
    assert_empty cls.label
    assert_equal 'skos prefLabel rien', cls.prefLabel
    assert_equal ['entita esp', 'entite rien'].sort, cls.synonym.sort
  end


  def test_label_main_lang_fr_found
    cls = parse_and_get_class lang: [:FR]
    assert_equal ['entité matérielle detaillée'], cls.label
    assert_includes ['skos prefLabel fr', 'skos prefLabel rien'], cls.prefLabel
    assert_equal ['entité fra', 'entite rien'].sort, cls.synonym.sort
  end

  def test_label_main_lang_not_found
    cls = parse_and_get_class lang: [:ES]

    assert_empty cls.label
    assert_equal 'skos prefLabel rien', cls.prefLabel
    assert_equal ['entita esp' , 'entite rien' ].sort, cls.synonym.sort
  end

  def test_label_secondary_lang
    # This feature is obsolete with the request language feature
    # 'es' will not be found
    cls = parse_and_get_class lang: %i[ES FR]

    assert_empty cls.label
    assert_equal 'skos prefLabel rien', cls.prefLabel
    assert_equal ['entita esp', 'entite rien'].sort, cls.synonym.sort
  end

  def test_label_main_lang_en_found
    cls = parse_and_get_class lang: [:EN]
    assert_equal 'material detailed entity', cls.label.first
    assert_includes ['skos prefLabel en', 'skos prefLabel rien'], cls.prefLabel # TODO fix in Goo to show en in priority
    assert_equal ['entity eng', 'entite rien'].sort, cls.synonym.sort
  end


  private

  def parse_and_get_class(lang:, klass: 'http://lirmm.fr/2015/resource/AGROOE_c_03')
    portal_lang_set portal_languages: lang

    cls = get_class(klass,'AGROOE')
    assert !cls.nil?
    cls.bring_remaining
    cls
  end


  def portal_lang_set(portal_languages: nil)
    Goo.main_languages = portal_languages if portal_languages
    RequestStore.store[:requested_lang] = nil
  end


  def get_class(cls, ont)
    sub = LinkedData::Models::Ontology.find(ont).first.latest_submission
    LinkedData::Models::Class.find(cls).in(sub).first
  end
end