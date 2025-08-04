# frozen_string_literal: true

require_relative '../test_case'
require 'mocha/minitest'
require 'mock_redis'

class TestOntologyAnalytics < LinkedData::TestCase
  def setup
    super
    LinkedData::Models::Ontology.class_variable_set(:@@redis, nil)

    LinkedData.settings.stubs(:ontology_analytics_redis_host).returns('localhost')
    LinkedData.settings.stubs(:ontology_analytics_redis_port).returns('6379')
    LinkedData.settings.stubs(:ontology_analytics_redis_field).returns('test_analytics')

    @mock_redis = MockRedis.new
    Redis.stubs(:new).returns(@mock_redis)

    prepare_test_data
  end

  def test_return_empty_hash_if_no_data_in_redis
    @mock_redis.flushdb
    result = LinkedData::Models::Ontology.analytics
    assert_equal({}, result)
  end

  def test_return_all_analytics
    result = LinkedData::Models::Ontology.analytics
    assert_equal @analytics, result
    assert_equal 6, result.keys.length
  end

  def test_return_analytics_for_specific_acronyms
    acronyms = %w[NCIT CMPO AEO]
    result = LinkedData::Models::Ontology.analytics(nil, nil, acronyms)

    assert_equal 3, result.size
    assert_includes result.keys, 'NCIT'
    assert_includes result.keys, 'CMPO'
    assert_includes result.keys, 'AEO'
    refute_includes result.keys, 'SNOMEDCT'
  end

  def test_filter_analytics_by_year
    result = LinkedData::Models::Ontology.analytics('2014')

    assert_equal 6, result.size
    assert_equal @analytics['NCIT']['2014'], result['NCIT']['2014']
    assert_equal 17_212, result['SNOMEDCT']['2014']['2']
    assert_empty result['NCIT'].keys.map(&:to_s) & %w[2013 2015 2016 2017 2018 2019 2020 2021 2022]
  end

  def test_filter_analytics_by_year_and_month_and_sort_results
    result = LinkedData::Models::Ontology.analytics('2013', '10')

    # Expected order based on ontology_analytics_data.json for 2013-10:
    # SNOMEDCT (20721), NCIT (2850), TST (234), AEO (129), CMPO (64), ONTOMA (6)
    expected_keys = %w[SNOMEDCT NCIT TST AEO CMPO ONTOMA]

    assert_equal expected_keys, result.keys
    assert_equal 20_721, result['SNOMEDCT']['2013']['10']
    assert_equal 6, result['ONTOMA']['2013']['10']
  end

  def test_retrieve_analytics_for_a_single_ontology
    result = @snomed_ont.analytics
    assert_equal @analytics['SNOMEDCT'], result['SNOMEDCT']
    assert_equal 1, result.size
  end

  def test_retrieve_filtered_analytics_for_a_single_ontology
    result = @ncit_ont.analytics('2014', '3')
    assert_equal 2183, result['NCIT']['2014']['3']
  end

  def teardown
    @mock_redis.flushdb
    super
  end

  private

  def prepare_test_data
    @analytics = JSON.parse(
      File.read(File.expand_path('../data/ontology_analytics_data.json', __dir__))
    )
    @mock_redis.set('test_analytics', Marshal.dump(@analytics))

    @snomed_ont = LinkedData::Models::Ontology.new(acronym: 'SNOMEDCT')
    @ncit_ont = LinkedData::Models::Ontology.new(acronym: 'NCIT')
  end
end
