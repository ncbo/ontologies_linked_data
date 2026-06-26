require_relative "../test_case"

require_relative "../test_case"

class TestSlice < LinkedData::TestCase

  def self.before_suite
    self.new("before_suite").delete_ontologies_and_submissions
    @@orig_slices_setting = LinkedData.settings.enable_slices
    LinkedData.settings.enable_slices = true
    @@onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 5, submission_count: 0)[2]
    @@group_acronym = "test-group"
    @@group = _create_group
    @@onts[0..2].each do |o|
      o.bring_remaining
      o.group = [@@group]
      o.save
    end
    LinkedData::Models::Slice.synchronize_groups_to_slices
  end

  def self.after_suite
    self.new("after_suite").delete_ontologies_and_submissions
    LinkedData.settings.enable_slices = @@orig_slices_setting
    LinkedData::Models::Slice.all.each {|s| s.delete}
    LinkedData::Models::Group.all.each {|g| g.delete}
  end

  def test_no_duplicate_slice_ids
    data = {
      :created => DateTime.parse("2012-10-04T07:00:00.000Z"),
      :name => "Test Slice",
      :description => "This is a test slice",
      :acronym => "tslc",
      :ontologies => [@@onts.first]
    }
    s1 = LinkedData::Models::Slice.new(data)
    s2 = LinkedData::Models::Slice.new(data)

    # Both should be valid before they are saved
    assert s1.valid?
    assert s2.valid?

    # Only c1 should be valid after save
    s1.save
    assert (not s2.valid?)
    assert s1.valid?

    # Cleanup
    s1.delete
  end

  def test_slice_lifecycle
    s = LinkedData::Models::Slice.new({
      :name => "Test Slice",
      :description => "This is a test slice",
      :acronym => "test-slice",
      :ontologies => @@onts[3..-1]
    })

    assert_equal false, s.exist?(reload=true)
    s.save
    assert_equal true, s.exist?(reload=true)
    s.delete
    assert_equal false, s.exist?(reload=true)
  end

  def test_synchronization
    slices = LinkedData::Models::Slice.where.include(:acronym).all
    assert slices.map {|s| s.acronym}.include?(@@group_acronym)
  end

  def test_synchronization_skips_groups_without_ontologies
    empty_group = LinkedData::Models::Group.new({
      acronym: "NOONTS",
      name: "Group Without Ontologies"
    }).save

    LinkedData::Models::Slice.synchronize_groups_to_slices

    assert_nil LinkedData::Models::Slice.find("noonts").first
  ensure
    empty_group&.delete
  end

  def test_slice_acronym_validity
    s = LinkedData::Models::Slice.new({
                                        :name => "Test Slice",
                                        :description => "This is a test slice",
                                        :acronym => "test_slice",
                                        :ontologies => @@onts[3..-1]
                                      })

    refute s.valid?

    s = LinkedData::Models::Slice.new({
                                        :name => "Test Slice",
                                        :description => "This is a test slice",
                                        :acronym => "test-slice",
                                        :ontologies => @@onts[3..-1]
                                      })

    assert s.valid?

  end

  private

  def self._create_group
    LinkedData::Models::Group.new({
      acronym: @@group_acronym,
      name: "Test Group"
    }).save
  end

end
