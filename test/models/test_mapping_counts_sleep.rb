# frozen_string_literal: true

require_relative '../test_case'
require 'mocha/minitest'

class TestMappingCountsSleep < Minitest::Test
  def setup
    @submissions = {
      'TEST1' => Object.new,
      'TEST2' => Object.new
    }

    LinkedData::Mappings.stubs(:retrieve_latest_submissions).returns(@submissions)
    LinkedData::Mappings.stubs(:mapping_ontologies_count).returns({})
    Goo.stubs(:sparql_query_client)
  end

  def test_skips_sleep_for_non_4store_backends
    Goo.stubs(:backend_4s?).returns(false)
    LinkedData::Mappings.expects(:handle_triple_store_downtime).never
    LinkedData::Mappings.expects(:sleep).never

    counts = LinkedData::Mappings.mapping_counts

    assert_equal({ 'TEST1' => 0, 'TEST2' => 0 }, counts)
  end

  def test_preserves_sleep_for_4store
    Goo.stubs(:backend_4s?).returns(true)
    LinkedData::Mappings.expects(:handle_triple_store_downtime).twice
    LinkedData::Mappings.expects(:sleep).with(5).twice

    counts = LinkedData::Mappings.mapping_counts

    assert_equal({ 'TEST1' => 0, 'TEST2' => 0 }, counts)
  end
end
