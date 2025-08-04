require 'cgi'
require 'pony'

module LinkedData
  module Utils
    class Notifications
      def self.new_note(note)
        note.bring_remaining
        note.creator.bring(:username) if note.creator.bring?(:username)
        note.relatedOntology.each { |o| o.bring(:name) if o.bring?(:name); o.bring(:subscriptions) if o.bring?(:subscriptions) }
        ontologies = note.relatedOntology.map { |o| o.name }.join(", ")
        # Fix the note URL when using replace_url_prefix (in another VM than NCBO)
        if LinkedData.settings.replace_url_prefix
          note_id = CGI.escape(note.id.to_s.gsub(LinkedData.settings.id_url_prefix, LinkedData.settings.rest_url_prefix))
        else
          note_id = CGI.escape(note.id.to_s)
        end
        note_url = "http://#{LinkedData.settings.ui_host}/notes/#{note_id}"
        subject = "[#{LinkedData.settings.ui_name} Notes] [#{ontologies}] #{note.subject}"
        body = NEW_NOTE.gsub("%username%", note.creator.username)
                       .gsub("%ontologies%", ontologies)
                       .gsub("%note_subject%", note.subject || "")
                       .gsub("%note_body%", note.body || "")
                       .gsub("%note_url%", note_url)
                       .gsub('%ui_name%', LinkedData.settings.ui_name)

        note.relatedOntology.each do |ont|
          Notifier.notify_subscribed_separately subject, body, ont, 'NOTES'
        end
      end

      def self.submission_processed(submission)
        submission.bring_remaining
        ontology = submission.ontology
        ontology.bring(:name, :acronym)
        result = submission.ready? || submission.archived? ? 'Success' : 'Failure'
        status = LinkedData::Models::SubmissionStatus.readable_statuses(submission.submissionStatus)

        subject = "[#{LinkedData.settings.ui_name}] #{ontology.name} Parsing #{result}"
        body = SUBMISSION_PROCESSED.gsub('%ontology_name%', ontology.name)
                                   .gsub('%ontology_acronym%', ontology.acronym)
                                   .gsub('%statuses%', status.join('<br/>'))
                                   .gsub('%support_contact%', LinkedData.settings.support_contact_email)
                                   .gsub('%ontology_location%', LinkedData::Hypermedia.generate_links(ontology)['ui'])
                                   .gsub('%ui_name%', LinkedData.settings.ui_name)

        Notifier.notify_subscribed_separately subject, body, ontology, 'PROCESSING'
        Notifier.notify_ontoportal_admins_grouped subject, body
        Notifier.notify_administrators_grouped subject, body, ontology
      end

      def self.remote_ontology_pull(submission)
        submission.bring_remaining
        ontology = submission.ontology
        ontology.bring(:name, :acronym, :administeredBy)

        subject = "[#{LinkedData.settings.ui_name}] Load from URL failure for #{ontology.name}"
        body = REMOTE_PULL_FAILURE.gsub('%ont_pull_location%', submission.pullLocation.to_s)
                                  .gsub('%ont_name%', ontology.name)
                                  .gsub('%ont_acronym%', ontology.acronym)
                                  .gsub('%ontology_location%', LinkedData::Hypermedia.generate_links(ontology)['ui'])
                                  .gsub('%support_contact%', LinkedData.settings.support_contact_email)
                                  .gsub('%ui_name%', LinkedData.settings.ui_name)

        Notifier.notify_ontoportal_admins_grouped subject, body
        Notifier.notify_administrators_grouped subject, body, ontology
      end

      def self.new_user(user)
        user.bring_remaining

        subject = "[#{LinkedData.settings.ui_name}] New User: #{user.username}"
        body = NEW_USER_CREATED.gsub('%username%', user.username.to_s)
                               .gsub('%email%', user.email.to_s)
                               .gsub('%site_url%', LinkedData.settings.ui_host)
                               .gsub('%ui_name%', LinkedData.settings.ui_name)

        Notifier.notify_ontoportal_admins_grouped subject, body
      end

      def self.new_ontology(ont)
        ont.bring_remaining

        subject = "[#{LinkedData.settings.ui_name}] New Ontology: #{ont.acronym}"
        body = NEW_ONTOLOGY_CREATED.gsub('%acronym%', ont.acronym)
                                   .gsub('%name%', ont.name.to_s)
                                   .gsub('%addedby%', ont.administeredBy[0].to_s)
                                   .gsub('%site_url%', LinkedData.settings.ui_host)
                                   .gsub('%ont_url%', LinkedData::Hypermedia.generate_links(ont)['ui'])
                                   .gsub('%ui_name%', LinkedData.settings.ui_name)

        Notifier.notify_ontoportal_admins_grouped subject, body
      end

      def self.reset_password(user, token)
        ui_name = LinkedData.settings.ui_name
        subject = "[#{ui_name}] User #{user.username} password reset"
        password_url = "https://#{LinkedData.settings.ui_host}/reset_password?tk=#{token}&em=#{CGI.escape(user.email)}&un=#{CGI.escape(user.username)}"

        body = REST_PASSWORD.gsub('%ui_name%', ui_name)
                             .gsub('%username%', user.username.to_s)
                             .gsub('%password_url%', password_url.to_s)

        Notifier.notify_mails_separately subject, body, [user.email]
      end

      def self.obofoundry_sync(missing_onts, obsolete_onts)
        ui_name = LinkedData.settings.ui_name
        subject = "[#{ui_name}] OBO Foundry synchronization report"
        recipients = Notifier.ontoportal_admin_emails
        body = render_template('obofoundry_sync.erb', {
          ui_name: ui_name,
          missing_onts: missing_onts,
          obsolete_onts: obsolete_onts,
        })

        Notifier.notify_mails_grouped(subject, body, recipients)
      end

      def self.cloudflare_analytics(result_data)
        ui_name = LinkedData.settings.ui_name
        subject = "[#{ui_name}] Cloudflare Analytics daily collection result: #{result_data[:status]}"
        recipients = Notifier.ontoportal_admin_emails
        body = render_template('cloudflare_analytics.erb', {
          result_data: result_data
        })

        Notifier.notify_mails_grouped(subject, body, recipients)
      end

      private

      def self.render_template(template_name, locals = {})
        gem_path = Gem.loaded_specs['ontologies_linked_data'].full_gem_path
        template_path = File.join(gem_path, 'views', 'emails', template_name)
        template = File.read(template_path)

        b = binding
        locals.each { |k, v| b.local_variable_set(k, v) }

        ERB.new(template).result(b)
      rescue Errno::ENOENT => e
        raise "Template not found: #{template_path}"
      end

      NEW_NOTE = <<EOS
A new note was added to %ontologies% by <b>%username%</b>.<br/><br/>

----------------------------------------------------------------------------------<br/>
<b>Subject:</b> %note_subject%<br/><br/>

%note_body%<br/>
----------------------------------------------------------------------------------<br/><br/>

You can respond by visiting: <a href="%note_url%">%ui_name%</a>.<br/><br/>
EOS

      SUBMISSION_PROCESSED = <<EOS
%ontology_name% (%ontology_acronym%) was processed for use in %ui_name%. Here are the results:
<br><br>
%statuses%
<br><br>
Please contact %support_contact% if you have questions.
<br><br>
The ontology can be <a href="%ontology_location%">browsed in %ui_name%</a>.
<br><br>
Thank you,<br>
The %ui_name% Team
EOS

      REMOTE_PULL_FAILURE = <<EOS
%ui_name% failed to load %ont_name% (%ont_acronym%) from URL: %ont_pull_location%.
<br><br>
Please verify the URL you provided for daily loading of your ontology:
<ol>
<li>Make sure you are signed in to %ui_name%.</li>
<li>Navigate to your ontology summary page: <a href="%ontology_location%">%ontology_location%</a>.</li>
<li>Click the &quot;Edit submission information&quot; link.</li>
<li>In the Location row, verify that you entered a valid URL for daily loading of your ontology in the URL text area.</li>
</ol>
If you need further assistance, please <a href="mailto:%support_contact%">contact us</a> via the %ui_name% support mailing list.
<br><br>
Thank you,<br>
The %ui_name% Team
EOS

      NEW_USER_CREATED = <<EOS
A new user have been created on %site_url%
<br>
Username: %username%
<br>
Email: %email%
<br><br>
The %ui_name% Team
EOS

      NEW_ONTOLOGY_CREATED = <<EOS
A new ontology have been created by %addedby% on %site_url%
<br>
Acronym: %acronym%
<br>
Name: %name%
<br>
At <a href="%ont_url%">%ont_url%</a>
<br><br>
The %ui_name% Team
EOS

      REST_PASSWORD = <<~HTML
        Someone has requested a password reset for user %username% . If this action
        was initiated by you, please click on the link below to reset your password.
        <br/><br/>

        <a href="%password_url%">%password_url%</a><br/><br/>

        Please note that the password link is valid for one hour only.  If you did not 
        request this password reset or no longer require it, you may safely ignore this email.
        <br/><br/>

        Thanks,<br/>
        %ui_name% Team
HTML
    end
  end
end
