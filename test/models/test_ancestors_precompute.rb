require_relative '../test_case'

class TestAncestorsPrecompute < LinkedData::TestCase

  def setup
    @indexer = LinkedData::Services::OntologySubmissionIndexer.new(nil)
  end

  # A -> B -> C (linear chain)
  def test_linear_chain
    direct_parents = {
      "http://example.org/C" => ["http://example.org/B"],
      "http://example.org/B" => ["http://example.org/A"]
    }
    ancestors_map = {}

    compute_all(direct_parents, ancestors_map)

    assert_equal Set.new(["http://example.org/B", "http://example.org/A"]),
                 ancestors_map["http://example.org/C"]
    assert_equal Set.new(["http://example.org/A"]),
                 ancestors_map["http://example.org/B"]
  end

  # Root node with no parents
  def test_root_node
    direct_parents = {
      "http://example.org/A" => []
    }
    ancestors_map = {}

    compute_all(direct_parents, ancestors_map)

    assert_equal Set.new, ancestors_map["http://example.org/A"]
  end

  #     A
  #    / \
  #   B   C
  #    \ /
  #     D
  def test_diamond_inheritance
    direct_parents = {
      "http://example.org/D" => ["http://example.org/B", "http://example.org/C"],
      "http://example.org/B" => ["http://example.org/A"],
      "http://example.org/C" => ["http://example.org/A"]
    }
    ancestors_map = {}

    compute_all(direct_parents, ancestors_map)

    assert_equal Set.new(["http://example.org/B", "http://example.org/C", "http://example.org/A"]),
                 ancestors_map["http://example.org/D"]
    assert_equal Set.new(["http://example.org/A"]),
                 ancestors_map["http://example.org/B"]
    assert_equal Set.new(["http://example.org/A"]),
                 ancestors_map["http://example.org/C"]
  end

  #   A   B
  #   |   |
  #   C   D
  def test_multiple_roots
    direct_parents = {
      "http://example.org/C" => ["http://example.org/A"],
      "http://example.org/D" => ["http://example.org/B"]
    }
    ancestors_map = {}

    compute_all(direct_parents, ancestors_map)

    assert_equal Set.new(["http://example.org/A"]),
                 ancestors_map["http://example.org/C"]
    assert_equal Set.new(["http://example.org/B"]),
                 ancestors_map["http://example.org/D"]
  end

  # A -> B -> A (cycle)
  def test_cycle
    direct_parents = {
      "http://example.org/A" => ["http://example.org/B"],
      "http://example.org/B" => ["http://example.org/A"]
    }
    ancestors_map = {}

    compute_all(direct_parents, ancestors_map)

    assert_includes ancestors_map["http://example.org/A"], "http://example.org/B"
    assert_includes ancestors_map["http://example.org/B"], "http://example.org/A"
  end

  # Class not in direct_parents (leaf with no edges)
  def test_class_not_in_map
    direct_parents = {}
    ancestors_map = {}

    @indexer.send(:compute_ancestors_for, "http://example.org/X", direct_parents, ancestors_map)

    assert_equal Set.new, ancestors_map["http://example.org/X"]
  end

  # Memoization: computing ancestors for a child reuses already-computed parent ancestors
  def test_memoization
    direct_parents = {
      "http://example.org/C" => ["http://example.org/B"],
      "http://example.org/B" => ["http://example.org/A"]
    }
    ancestors_map = {}

    # Compute B first
    @indexer.send(:compute_ancestors_for, "http://example.org/B", direct_parents, ancestors_map)
    assert ancestors_map.key?("http://example.org/B")
    refute ancestors_map.key?("http://example.org/C")

    # Now compute C — should reuse B's cached result
    @indexer.send(:compute_ancestors_for, "http://example.org/C", direct_parents, ancestors_map)
    assert_equal Set.new(["http://example.org/B", "http://example.org/A"]),
                 ancestors_map["http://example.org/C"]
  end

  #       A
  #      / \
  #     B   C
  #    / \   \
  #   D   E   F
  #        \ /
  #         G
  def test_complex_dag
    direct_parents = {
      "http://example.org/D" => ["http://example.org/B"],
      "http://example.org/E" => ["http://example.org/B"],
      "http://example.org/F" => ["http://example.org/C"],
      "http://example.org/G" => ["http://example.org/E", "http://example.org/F"],
      "http://example.org/B" => ["http://example.org/A"],
      "http://example.org/C" => ["http://example.org/A"]
    }
    ancestors_map = {}

    compute_all(direct_parents, ancestors_map)

    assert_equal Set.new(["http://example.org/E", "http://example.org/F",
                          "http://example.org/B", "http://example.org/C",
                          "http://example.org/A"]),
                 ancestors_map["http://example.org/G"]

    assert_equal Set.new(["http://example.org/B", "http://example.org/A"]),
                 ancestors_map["http://example.org/D"]
  end

  def test_empty_ontology
    direct_parents = {}
    ancestors_map = {}

    compute_all(direct_parents, ancestors_map)

    assert_equal({}, ancestors_map)
  end

  private

  def compute_all(direct_parents, ancestors_map)
    direct_parents.each_key do |cls|
      @indexer.send(:compute_ancestors_for, cls, direct_parents, ancestors_map)
    end
  end
end
