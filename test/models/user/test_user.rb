require_relative "../../test_case"

class TestUser < LinkedData::TestCase

  def self.before_suite
    self.new("before_suite").teardown
  end

  def self.after_suite
    self.new("after_suite").teardown
  end

  def setup
    @u = LinkedData::Models::User.new({
        username: "test_user",
        email: "test@example.com",
        password: "a_password"
      })
    assert @u.valid?
  end

  def teardown
    ["test_user1", "test_user", "test_user_datetime", "test_user_uuid"].each do |username|
      u = LinkedData::Models::User.where(username: username).first
      u.delete unless u.nil?
    end
  end

  def test_valid_user
    u = LinkedData::Models::User.new
    refute u.valid?

    u.username = "test_user1"
    u.email = "test@example.com"
    u.password = "a_password"
    assert u.valid?

    u.username = "really_really_really_really_really_really_really_long_username"
    refute u.valid?

    u.username = 'username_with_🌍_character'
    refute u.valid?

    u.username = "username_with\nnewline"
    refute u.valid?

    u.username = "username_with\ntab"
    refute u.valid?

    u.username = "username_<1>!"
    refute u.valid?

    u.username = "username_with\u200Bhidden_char"
    refute u.valid?

    # u.username = "test bad username"
    # refute u.valid?
    # u.username = "test.bad.username"
    # refute u.valid?
    # u.username = "<test_bad_username>"
    # refute u.valid?
  end

  def test_user_lifecycle
    refute @u.exist?(reload=true)
    assert @u.valid?
    @u.save
    assert @u.exist?(reload=true)
    @u.delete
    refute @u.exist?(reload=true)
  end

  def test_user_role_assign
    u = @u
    u.role = [ LinkedData::Models::Users::Role.find("ADMINISTRATOR").include(:role).first ]

    assert u.valid?
    u.save
    assert u.role.length == 1

    assert_equal u.role.first.role, "ADMINISTRATOR"
    u.delete
  end

  def test_user_default_datetime
    u = LinkedData::Models::User.new({
        username: "test_user_datetime",
        email: "test@example.com",
        password: "a_password"
      })
    assert u.created.nil?
    assert u.valid?
    u.save
    assert u.created.instance_of?(DateTime)
    u.delete
  end

  def test_user_default_uuid
    u = LinkedData::Models::User.new({
        username: "test_user_uuid",
        email: "test@example.com",
        password: "a_password"
      })
    assert u.apikey.nil?
    assert u.valid?
    u.save
    assert u.apikey.instance_of?(String)
    u.delete
  end

  def test_user_email_validation_missing_email
    u = LinkedData::Models::User.new({
        username: "test_user_no_email",
        password: "a_password"
      })
    refute u.valid?
    assert u.errors.include?(:email)
  end

  def test_user_email_validation_empty_email
    u = LinkedData::Models::User.new({
        username: "test_user_empty_email",
        email: "",
        password: "a_password"
      })
    refute u.valid?
    assert u.errors.include?(:email)
  end

  def test_user_email_validation_nil_email
    u = LinkedData::Models::User.new({
        username: "test_user_nil_email",
        email: nil,
        password: "a_password"
      })
    refute u.valid?
    assert u.errors.include?(:email)
  end

  def test_user_email_validation_invalid_formats
    invalid_emails = [
      "invalid-email",
      "@example.com",
      "test@",
      "test@.com",
      "test..test@example.com",
      "test@example..com",
      "test@example",
      "test space@example.com",
      "test@example com",
      "test@example.com.",
      ".test@example.com"
    ]

    invalid_emails.each_with_index do |email, index|
      u = LinkedData::Models::User.new({
          username: "test_user_invalid_email_#{index}",
          email: email,
          password: "a_password"
        })
      refute u.valid?, "Email '#{email}' should be invalid"
      assert u.errors.include?(:email), "Email '#{email}' should have email validation error"
    end
  end

  def test_user_email_validation_valid_formats
    valid_emails = [
      "test@example.com",
      "user.name@example.com",
      "user+tag@example.com",
      "user@subdomain.example.com",
      "user@example.co.uk",
      "user@example-domain.com",
      "user123@example.com",
      "user-name@example.com"
    ]

    valid_emails.each_with_index do |email, index|
      u = LinkedData::Models::User.new({
          username: "test_user_valid_email_#{index}",
          email: email,
          password: "a_password"
        })
      assert u.valid?, "Email '#{email}' should be valid"
      refute u.errors.include?(:email), "Email '#{email}' should not have email validation error"
    end
  end

end
