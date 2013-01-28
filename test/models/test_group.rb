require_relative "../test_case"

class TestGroup < LinkedData::TestCase
  def test_valid_group
    g = LinkedData::Models::Group.new
    assert (not g.valid?)

    # Not valid because not all attributes are present
    g.name = "Test Group"
    g.created = DateTime.parse("2012-10-04T07:00:00.000Z")
    assert (not g.valid?)

    # All attributes now present, should be valid
    g.acronym = "TGRP"
    g.description = "Test group description"
    assert g.valid?
  end

  def test_no_duplicate_project_ids
    g1 = LinkedData::Models::Group.new({
        :created => DateTime.parse("2012-10-04T07:00:00.000Z"),
        :name => "Test Group",
        :description => "This is a test group",
        :acronym => "TGRP"
      })

    g2 = LinkedData::Models::Group.new({
        :created => DateTime.parse("2012-10-04T07:00:00.000Z"),
        :name => "Test Group",
        :description => "This is a test group",
        :acronym => "TGRP"
      })

    # Both should be valid before they are saved
    assert g1.valid?
    assert g2.valid?

    # Only c1 should be valid after save
    g1.save
    assert (not g2.valid?)
    assert g1.valid?

    # Cleanup
    g1.delete
  end

  def test_group_lifecycle
    g = LinkedData::Models::Group.new({
        :created => DateTime.parse("2012-10-04T07:00:00.000Z"),
        :name => "Test Group",
        :description => "This is a test group",
        :acronym => "TGRP"
      })

    assert_equal false, g.exist?(reload=true)
    g.save
    assert_equal true, g.exist?(reload=true)
    g.delete
    assert_equal false, g.exist?(reload=true)
  end

  def test_group_default_datetime
    g = LinkedData::Models::Group.new
    assert g.created.instance_of? DateTime
  end
end