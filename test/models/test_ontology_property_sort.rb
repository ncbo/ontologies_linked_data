require_relative '../test_case'

class TestOntologyPropertySort < LinkedData::TestCase
  # Stands in for a property model: property_sort_key only uses these methods.
  StubProp = Struct.new(:id, :labels, :label_not_loaded) do
    def bring?(_attr) = false
    def bring(*_attrs); end

    def label
      raise Goo::Base::AttributeNotLoaded, 'label' if label_not_loaded
      labels
    end
  end

  def prop(fragment, labels: [], label_not_loaded: false)
    StubProp.new(RDF::URI.new("http://example.org/props##{fragment}"), labels, label_not_loaded)
  end

  def sort_key(p)
    LinkedData::Models::OntologyProperty.property_sort_key(p)
  end

  def test_sort_key_uses_first_label_downcased
    assert_equal 'zeta', sort_key(prop('aaa', labels: %w[Zeta Alpha]))
  end

  def test_sort_key_falls_back_to_generated_label
    assert_equal 'betaprop', sort_key(prop('BetaProp'))
    assert_equal 'betaprop', sort_key(prop('BetaProp', labels: nil))
    assert_equal 'betaprop', sort_key(prop('BetaProp', label_not_loaded: true))
  end

  def test_sort_matches_compare_properties
    props = [prop('c', labels: ['Gamma']), prop('BetaProp', label_not_loaded: true),
             prop('a', labels: ['alpha']), prop('Delta')]
    expected = props.sort { |a, b| LinkedData::Models::OntologyProperty.compare_properties(a, b) }.map(&:id)

    assert_equal expected, LinkedData::Models::OntologyProperty.sort_properties(props).map(&:id)
    in_place = props.dup
    assert_same in_place, LinkedData::Models::OntologyProperty.sort_properties!(in_place)
    assert_equal expected, in_place.map(&:id)
    assert_equal %w[a BetaProp Delta c], expected.map { |id| id.to_s.split('#').last }
  end
end
