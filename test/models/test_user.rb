require_relative "../test_case"

class TestUser < LinkedData::TestCase
  def test_valid_user
    u = LinkedData::Models::User.new
    assert (not u.valid?)

    u.username = "test_user"
    assert u.valid?
  end

  def test_user_lifecycle
    u = LinkedData::Models::User.new({
        username: "test_user"
      })

    assert_equal false, u.exist?(reload=true)
    u.save
    assert_equal true, u.exist?(reload=true)
    u.delete
    assert_equal false, u.exist?(reload=true)
  end

  def test_user_default_datetime
    u = LinkedData::Models::User.new
    assert u.created.instance_of? DateTime
  end
end