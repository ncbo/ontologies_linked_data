require_relative './test_ontology_common'
class TestClassMainLang < LinkedData::TestOntologyCommon

  def self.before_suite
    @@old_main_languages = Goo.main_languages
  end

  def self.after_suite
    Goo.main_languages = @@old_main_languages
  end

  def test_map_attribute_found
    cls = parse_and_get_class lang: ['fr']
    cls.bring :unmapped
    LinkedData::Models::Class.map_attributes(cls)
    assert_equal 'entité matérielle detaillée', cls.label.first
    assert_equal 'skos prefLabel fr', cls.prefLabel
    assert_equal ['entité fra', 'entite rien'], cls.synonym
  end

  def test_map_attribute_not_found
    cls = parse_and_get_class lang: ['es']
    cls.bring :unmapped
    LinkedData::Models::Class.map_attributes(cls)
    assert_equal ['material detailed entity', 'entité matérielle detaillée'], cls.label
    assert_equal 'skos prefLabel rien', cls.prefLabel
    assert_equal ['entita esp' , 'entite rien' ], cls.synonym
  end

  def test_map_attribute_secondary_lang
    cls = parse_and_get_class lang: %w[es fr]
    cls.bring :unmapped
    LinkedData::Models::Class.map_attributes(cls)
    assert_equal ['entité matérielle detaillée'], cls.label
    assert_equal 'skos prefLabel rien', cls.prefLabel
    assert_equal ['entita esp', 'entite rien'], cls.synonym
  end


  def test_label_main_lang_fr_found
    cls = parse_and_get_class lang: ['fr']
    assert_equal 'entité matérielle detaillée', cls.label.first
    assert_equal 'skos prefLabel fr', cls.prefLabel
    assert_equal ['entité fra', 'entite rien'], cls.synonym
  end

  def test_label_main_lang_not_found
    cls = parse_and_get_class lang: ['es']

    assert_equal ['material detailed entity', 'entité matérielle detaillée'], cls.label
    assert_equal 'skos prefLabel rien', cls.prefLabel
    assert_equal ['entita esp' , 'entite rien' ], cls.synonym
  end

  def test_label_secondary_lang
    # 'es' will not be found so will take 'fr' if fond or anything else
    cls = parse_and_get_class lang: %w[es fr]

    assert_equal ['entité matérielle detaillée'], cls.label
    assert_equal 'skos prefLabel rien', cls.prefLabel
    assert_equal ['entita esp', 'entite rien'], cls.synonym
  end

  def test_label_main_lang_en_found
    cls = parse_and_get_class lang: ['en']
    assert_equal 'material detailed entity', cls.label.first
    assert_equal 'skos prefLabel en', cls.prefLabel
    assert_equal ['entity eng', 'entite rien'], cls.synonym
  end


  private

  def parse_and_get_class(lang:, klass: 'http://lirmm.fr/2015/resource/AGROOE_c_03')
    lang_set lang
    submission_parse('AGROOE', 'AGROOE Test extract metadata ontology',
                     './test/data/ontology_files/agrooeMappings-05-05-2016.owl', 1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)


    cls = get_class(klass,'AGROOE')
    assert !cls.nil?
    cls.bring_remaining
    cls
  end

  def lang_set(lang)
    Goo.main_languages = lang
  end

  def get_ontology_last_submission(ont)
    LinkedData::Models::Ontology.find(ont).first.latest_submission()
  end

  def get_class(cls, ont)
    sub = LinkedData::Models::Ontology.find(ont).first.latest_submission()
    LinkedData::Models::Class.find(cls).in(sub).first
  end
end