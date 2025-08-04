require_relative "../test_case"
class TestContact < LinkedData::TestCase

  def self.before_suite
    self.new("before_suite").teardown
  end

  def self.after_suite
    self.new("after_suite").teardown
  end

  def setup
    @contact = LinkedData::Models::Contact.new({
        name: "Test Contact",
        email: "test@example.com"
      })
  end

  def teardown
    # Clean up any test contacts
    contacts = LinkedData::Models::Contact.where(name: "Test Contact").to_a
    contacts.each { |c| c.delete }
  end

  def test_contact_validation
    contact = LinkedData::Models::Contact.new
    refute contact.valid?

    contact.name = "Test Contact"
    contact.email = "test@example.com"
    assert contact.valid?
  end

  def test_contact_lifecycle
    contact = LinkedData::Models::Contact.new({
        name: "Lifecycle Test Contact",
        email: "lifecycle@example.com"
      })
    c = LinkedData::Models::Contact.where(email: contact.email).first
    refute c
    assert contact.valid?
    contact.save
    c = LinkedData::Models::Contact.where(email: contact.email).first
    assert c
    contact.delete
    c = LinkedData::Models::Contact.where(email: contact.email).first
    refute c
  end

  def test_contact_missing_name
    contact = LinkedData::Models::Contact.new({
        email: "test@example.com"
      })
    refute contact.valid?
    assert_includes contact.errors, :name
  end

  def test_contact_missing_email
    contact = LinkedData::Models::Contact.new({
        name: "Test Contact"
      })
    refute contact.valid?
    assert_includes contact.errors, :email
  end

  def test_contact_invalid_email
    contact = LinkedData::Models::Contact.new({
        name: "Test Contact",
        email: "invalid-email"
      })
    refute contact.valid?
    assert_includes contact.errors, :email
  end

  def test_contact_duplicate
    skip "Duplicate contact prevention mechanism not yet implemented"
    # Create and save first contact
    contact1 = LinkedData::Models::Contact.new({
        name: "Duplicate Test Contact",
        email: "duplicate@example.com"
      })
    assert contact1.valid?
    contact1.save

    # Try to create second contact with same name and email
    contact2 = LinkedData::Models::Contact.new({
        name: "Duplicate Test Contact",
        email: "duplicate@example.com"
      })
    refute contact2.valid?
    assert_includes contact2.errors, :name
    assert_includes contact2.errors, :email
    contact1.delete
  end

end 