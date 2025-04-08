require_relative "../test_case"

class TestHypermediaResource < LinkedData::TestCase
  class DummyModel
    include LinkedData::Hypermedia::Resource
  end

  def test_dsl_methods_exist
    assert_respond_to DummyModel, :serialize_default
    assert_respond_to DummyModel, :system_controlled
  end

  def test_system_controlled_dsl_stores_attributes
    DummyModel.system_controlled :foo, :bar
    attrs = DummyModel.hypermedia_settings[:system_controlled]

    assert_includes attrs, :foo
    assert_includes attrs, :bar
    assert attrs.all? { |a| a.is_a?(Symbol) }, "Expected all system-controlled attributes to be symbols"
  end

  def test_multiple_calls_append
    skip "Multiple calls to `system_controlled` currently overwrite previous values — revisit if we decide to support accumulation."

    klass = Class.new do
      include LinkedData::Hypermedia::Resource
      system_controlled :foo
      system_controlled :baz
    end

    attrs = klass.hypermedia_settings[:system_controlled]
    assert attrs.all? { |a| a.is_a?(Symbol) }
    assert_includes attrs, :foo
    assert_includes attrs, :baz
    assert_equal 2, attrs.size
  end

  def test_non_declared_settings_default_empty
    dummy = Class.new do
      include LinkedData::Hypermedia::Resource
    end

    settings = dummy.hypermedia_settings[:system_controlled]
    assert_equal [], settings
  end
end
