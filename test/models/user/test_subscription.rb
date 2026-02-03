require_relative "../../test_case"

class TestSubscription < LinkedData::TestCase

  def self.before_suite
    @@ont = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 1, submission_count: 1)[2].first
    @@ont.bring_remaining
    @@user = @@ont.administeredBy.first
    @@user.bring_remaining
  end

  def self.after_suite
    @@ont.delete if defined?(@@ont)
    @@user.delete if defined?(@@user)
    self.new("after_suite")._delete_subscriptions
  end

  def setup
    _delete_subscriptions
  end

  def _subscription(ont, type = "ALL")
    @@subscriptions ||= []
    subscription = LinkedData::Models::Users::Subscription.new
    subscription.ontology = ont
    subscription.notification_type = LinkedData::Models::Users::NotificationType.find(type).first
    subscription.save
    @@subscriptions << subscription
    subscription
  end

  def _delete_subscriptions
    if self.class.class_variable_defined?(:@@subscriptions)
      @@subscriptions.each { |s| s.delete }
    end
    @@subscriptions = nil
  end

  def test_subscribe
    subscription = _subscription(@@ont)
    @@user.subscription = [subscription]
    @@user.save

    user = LinkedData::Models::User.find(@@user.id).include(:subscription).first
    assert_equal 1, user.subscription.length
    assert_equal subscription.id, user.subscription.first.id

    ont = LinkedData::Models::Ontology.find(@@ont.id).include(:subscriptions).first
    assert_equal 1, ont.subscriptions.length
    ont.subscriptions.first.bring(:user)
    assert_equal @@user.id, ont.subscriptions.first.user.first.id
  end

  def test_subscription_type
    # Default
    subscription = _subscription(@@ont)
    @@user.subscription = [subscription]
    @@user.save

    user = LinkedData::Models::User.find(@@user.id).include(:subscription).first
    assert_equal 1, user.subscription.length
    assert_equal subscription.id, user.subscription.first.id

    # Type processing
    subscription = _subscription(@@ont, "PROCESSING")
    @@user.subscription = [subscription]
    @@user.save

    user = LinkedData::Models::User.find(@@user.id).include(:subscription).first
    assert_equal 1, user.subscription.length
    assert_equal subscription.id, user.subscription.first.id

    # Type notes
    subscription = _subscription(@@ont, "NOTES")
    @@user.subscription = [subscription]
    @@user.save

    user = LinkedData::Models::User.find(@@user.id).include(:subscription).first
    assert_equal 1, user.subscription.length
    assert_equal subscription.id, user.subscription.first.id
  end

end
