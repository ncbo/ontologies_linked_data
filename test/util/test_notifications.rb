require_relative '../test_case'

require 'email_spec'
require 'logger'
require 'mocha/minitest'

class TestNotifications < LinkedData::TestCase
  include EmailSpec::Helpers

  def self.before_suite
    # Store original settings
    @original_settings = {
      notifications_enabled: LinkedData.settings.enable_notifications,
      disable_override: LinkedData.settings.email_disable_override,
      admin_emails: LinkedData.settings.ontoportal_admin_emails
    }

    LinkedData.settings.email_disable_override = true
    LinkedData.settings.enable_notifications = true
    LinkedData.settings.ontoportal_admin_emails = ['ontoportal-support@mail.com']

    @@ui_name = LinkedData.settings.ui_name
    @@support_mails = LinkedData.settings.ontoportal_admin_emails
    @@ont = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 1,
                                                                               submission_count: 1)[2].first
    @@ont.bring_remaining
    @@user = @@ont.administeredBy.first
    @@subscription = new('before_suite')._subscription(@@ont)
    @@user.bring_remaining
    @@user.subscription = [@@subscription]
    @@user.save
  end

  def self.after_suite
    # Restore original settings
    LinkedData.settings.enable_notifications = @original_settings[:notifications_enabled]
    LinkedData.settings.email_disable_override = @original_settings[:disable_override]
    LinkedData.settings.ontoportal_admin_emails = @original_settings[:admin_emails]

    [@@ont, @@subscription, @@user].each(&:delete)
  end

  def setup
    LinkedData.settings.email_disable_override = true
    reset_mailer
  end

  def _subscription(ont)
    subscription = LinkedData::Models::Users::Subscription.new
    subscription.ontology = ont
    subscription.notification_type = LinkedData::Models::Users::NotificationType.find('ALL').first
    subscription.save
  end

  def test_send_notification
    recipients = ['test@example.org']
    subject = 'Test subject'
    body = 'My test body'

    # Email recipient address will be overridden
    LinkedData.settings.email_disable_override = false
    LinkedData::Utils::Notifier.notify(recipients: recipients)
    assert_equal [LinkedData.settings.email_override], last_email_sent.to

    # Disable override
    LinkedData.settings.email_disable_override = true
    LinkedData::Utils::Notifier.notify({ recipients: recipients, subject: subject, body: body })
    assert_equal recipients, last_email_sent.to
    assert_equal [LinkedData.settings.email_sender], last_email_sent.from
    assert_equal last_email_sent.body.raw_source, body
    assert_equal last_email_sent.subject, subject
  end

  def test_new_note_notification
    recipients = ['test@example.org']
    subject = 'Test note subject'
    body = 'Test note body'
    note = LinkedData::Models::Note.new
    note.creator = @@user
    note.subject = subject
    note.body = body
    note.relatedOntology = [@@ont]
    note.save
    assert_match "[#{@@ui_name} Notes]", last_email_sent.subject
    assert_equal [@@user.email], last_email_sent.to
  ensure
    note&.delete
  end

  def test_processing_complete_notification
    options = { ont_count: 1, submission_count: 2, acronym: 'NOTIFY' }
    ont = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(options)[2].first
    subscription = _subscription(ont)
    @@user.subscription = @@user.subscription.dup << subscription
    @@user.save
    ont.latest_submission(status: :any).process_submission(Logger.new(TestLogFile.new))
    subscription.bring :user
    admin_mails = LinkedData::Utils::Notifier.ontology_admin_emails(ont)
    mail_sent_count = subscription.user.size + 2
    assert_equal mail_sent_count, all_emails.size, 'number of send emails'

    first_user = subscription.user.first
    first_user.bring :email
    assert_match 'Parsing Success', all_emails.first.subject
    assert_equal [first_user.email], all_emails.first.to

    assert_match 'Parsing Success', all_emails.last.subject
    assert_equal @@support_mails.uniq.sort, all_emails[1].to.sort
    assert_equal admin_mails.uniq.sort, all_emails.last.to.sort

    reset_mailer
    sub = ont.submissions.sort_by { |s| s.id }.first
    sub.process_submission(Logger.new(TestLogFile.new), { archive: true })

    assert_empty all_emails
  ensure
    ont&.delete
    subscription&.delete
  end

  def test_disable_administrative_notifications
    LinkedData.settings.enable_administrative_notifications = false
    options = { ont_count: 1, submission_count: 1, acronym: 'DONTNOTIFY' }
    ont = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(options)[2].first
    ont.latest_submission(status: :any).process_submission(Logger.new(TestLogFile.new))
    admin_mails = LinkedData::Utils::Notifier.ontology_admin_emails(ont)
    assert_equal 1, all_emails.size, 'number of send emails'

    refute_match @@support_mails, last_email_sent.to.sort
    assert_equal admin_mails, last_email_sent.to.sort
    assert_match 'Parsing Success', all_emails.last.subject
    LinkedData.settings.enable_administrative_notifications = true
  ensure
    ont&.delete
  end

  def test_remote_ontology_pull_notification
    recipients = ['test@example.org']
    _ont_count, _acronyms, ontologies = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(
      ont_count: 1, submission_count: 1, process_submission: false
    )

    ont = LinkedData::Models::Ontology.find(ontologies[0].id)
                                      .include(:acronym, :administeredBy, :name, :submissions).first
    ont_admins = Array.new(3) { LinkedData::Models::User.new }
    ont_admins.each_with_index do |user, i|
      user.username = "Test User #{i}"
      user.email = "tester_#{i}@example.org"
      user.password = 'password'
      user.save
      assert user.valid?, user.errors
    end
    ont.administeredBy = ont_admins
    ont.save
    assert ont.valid?, ont.errors

    sub = ont.submissions.first
    sub.bring_remaining
    assert sub.valid?, sub.errors
    LinkedData::Utils::Notifications.remote_ontology_pull(sub)

    admin_mails = LinkedData::Utils::Notifier.ontology_admin_emails(ont)

    assert_includes "[#{@@ui_name}] Load from URL failure for #{ont.name}", last_email_sent.subject
    assert_equal @@support_mails, all_emails.first.to
    assert_equal admin_mails, last_email_sent.to.sort
  ensure
    ont_admins.each do |user|
      user&.delete
    end
  end

  def test_cloudflare_analytics_success_notification
    start_time = Time.now - 3600
    end_time = Time.now
    result_data = {
      start_time: start_time,
      end_time: end_time,
      duration: 3600,
      status: 'success',
      error: nil
    }

    LinkedData::Utils::Notifications.cloudflare_analytics(result_data)

    assert_equal 1, all_emails.size
    assert_match 'success', last_email_sent.subject
    assert_includes last_email_sent.body.raw_source, 'completed successfully'
    assert_includes last_email_sent.body.raw_source, start_time.to_s
  end

  def test_cloudflare_analytics_failure_notification
    start_time = Time.now - 3600
    end_time = Time.now
    result_data = {
      start_time: start_time,
      end_time: end_time,
      duration: 3600,
      status: 'error',
      error: 'Connection timeout'
    }

    LinkedData::Utils::Notifications.cloudflare_analytics(result_data)

    assert_equal 1, all_emails.size
    assert_match 'error', last_email_sent.subject
    assert_includes last_email_sent.body.raw_source, 'Connection timeout'
  end

  def test_render_template
    gem_path = '/fake/gem/path'
    Gem.loaded_specs.stubs(:[]).with('ontologies_linked_data').returns(
      stub(full_gem_path: gem_path)
    )

    template_content = 'Hello <%= name %>!'
    File.expects(:read).with("#{gem_path}/views/emails/test.erb").returns(template_content)

    result = LinkedData::Utils::Notifications.render_template('test.erb', { name: 'World' })
    assert_equal 'Hello World!', result
  end

  def test_render_template_file_not_found
    gem_path = '/fake/gem/path'
    Gem.loaded_specs.stubs(:[]).with('ontologies_linked_data').returns(
      stub(full_gem_path: gem_path)
    )

    File.expects(:read).raises(Errno::ENOENT)

    assert_raises(RuntimeError, 'Template not found') do
      LinkedData::Utils::Notifications.render_template('nonexistent.erb', {})
    end
  end

  def test_mail_options
    current_auth_type = LinkedData.settings.smtp_auth_type

    LinkedData.settings.smtp_auth_type = :none
    options = LinkedData::Utils::Notifier.mail_options
    expected_options = {
      address: LinkedData.settings.smtp_host,
      port: LinkedData.settings.smtp_port,
      domain: LinkedData.settings.smtp_domain
    }
    assert_equal options, expected_options

    # testing SMTP authentification-based login

    LinkedData.settings.smtp_auth_type = :plain
    options = LinkedData::Utils::Notifier.mail_options
    expected_options = {
      address: LinkedData.settings.smtp_host,
      port: LinkedData.settings.smtp_port,
      domain: LinkedData.settings.smtp_domain,
      user_name: LinkedData.settings.smtp_user,
      password: LinkedData.settings.smtp_password,
      authentication: LinkedData.settings.smtp_auth_type
    }
    assert_equal options, expected_options

    LinkedData.settings.smtp_auth_type = current_auth_type
  end
end
