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
        if LinkedData.settings.replace_url_prefix == true
          note_url = "http://#{LinkedData.settings.ui_host}/notes/#{CGI.escape(note.id.to_s.gsub("http://data.bioontology.org", LinkedData.settings.rest_url_prefix))}"
        else
          note_url = "http://#{LinkedData.settings.ui_host}/notes/#{CGI.escape(note.id.to_s)}"
        end
        subject = "[#{LinkedData.settings.ui_name} Notes] [#{ontologies}] #{note.subject}"
        body = NEW_NOTE.gsub("%username%", note.creator.username)
                       .gsub("%ontologies%", ontologies)
                       .gsub("%note_subject%", note.subject || "")
                       .gsub("%note_body%", note.body || "")
                       .gsub("%note_url%",  note_url)
                       .gsub('%ui_name%', LinkedData.settings.ui_name)

        note.relatedOntology.each do |ont|
          Notifier.notify_subscribed_separately subject, body, ont, 'NOTES'
        end
      end

      def self.submission_processed(submission)
        submission.bring_remaining
        ontology = submission.ontology
        ontology.bring(:name, :acronym)
        result = submission.ready? ? 'Success' : 'Failure'
        status = LinkedData::Models::SubmissionStatus.readable_statuses(submission.submissionStatus)

        subject = "[#{LinkedData.settings.ui_name}] #{ontology.name} Parsing #{result}"
        body = SUBMISSION_PROCESSED.gsub('%ontology_name%', ontology.name)
                                   .gsub('%ontology_acronym%', ontology.acronym)
                                   .gsub('%statuses%', status.join('<br/>'))
                                   .gsub('%admin_email%', LinkedData.settings.email_sender)
                                   .gsub('%ontology_location%', LinkedData::Hypermedia.generate_links(ontology)['ui'])
                                   .gsub('%ui_name%', LinkedData.settings.ui_name)

        Notifier.notify_subscribed_separately subject, body, ontology, 'PROCESSING'
        Notifier.notify_mails_grouped subject, body, Notifier.support_mails + Notifier.admin_mails(ontology)
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
                                  .gsub('%support_mail%', Notifier.support_mails.first || '')
                                  .gsub('%ui_name%', LinkedData.settings.ui_name)
        recipients = []
        ontology.administeredBy.each do |user|
          user.bring(:email) if user.bring?(:email)
          recipients << user.email
        end
        if !LinkedData.settings.admin_emails.nil? && LinkedData.settings.admin_emails.kind_of?(Array)
          LinkedData.settings.admin_emails.each do |admin_email|
            recipients << admin_email
          end
        end

        Notifier.notify_mails_grouped subject, body, [Notifier.admin_mails(ontology) + Notifier.support_mails]
      end

      def self.new_user(user)
        user.bring_remaining

        subject = "[#{LinkedData.settings.ui_name}] New User: #{user.username}"
        body = NEW_USER_CREATED.gsub('%username%', user.username.to_s)
                               .gsub('%email%', user.email.to_s)
                               .gsub('%site_url%', LinkedData.settings.ui_host)
                               .gsub('%ui_name%', LinkedData.settings.ui_name)
        recipients = LinkedData.settings.admin_emails

        Notifier.notify_support_grouped subject, body
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
        recipients = LinkedData.settings.admin_emails

        Notifier.notify_support_grouped subject, body
      end

      def self.reset_password(user, token)
        ui_name = LinkedData.settings.ui_name
        subject = "[#{ui_name}] User #{user.username} password reset"
        password_url = "https://#{LinkedData.settings.ui_host}/reset_password?tk=#{token}&em=#{CGI.escape(user.email)}&un=#{CGI.escape(user.username)}"

        body = <<~HTML
          Someone has requested a password reset for user #{user.username}. If this was 
          you, please click on the link below to reset your password. Otherwise, please 
          ignore this email.<br/><br/>

          <a href="#{password_url}">#{password_url}</a><br/><br/>

          Thanks,<br/>
          BioPortal Team
          #{ui_name} Team
        HTML
        Notifier.notify_mails_separately subject, body, [user.mail]
      end

      def self.obofoundry_sync(missing_onts, obsolete_onts)
        body = ''
        ui_name = LinkedData.settings.ui_name
        if missing_onts.size > 0
          body << "<strong>The following OBO Library ontologies are missing from #{ui_name}:</strong><br/><br/>"
          missing_onts.each do |ont|
            body << "<a href='#{ont['homepage']}'>#{ont['id']}</a> (#{ont['title']})<br/><br/>"
          end
        end

        if obsolete_onts.size > 0
          body << '<strong>The following OBO Library ontologies have been deprecated:</strong><br/><br/>'
          obsolete_onts.each do |ont|
            body << "<a href='#{ont['homepage']}'>#{ont['id']}</a> (#{ont['title']})<br/><br/>"
          end
        end

        if body.empty?
          body << "#{ui_name} and the OBO Foundry are in sync.<br/><br/>"
        end

        Notifier.notify_mails_separately subject, body, [LinkedData.settings.email_sender]
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
Please contact %admin_email% if you have questions.
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
If you need further assistance, please <a href="mailto:%support_mail%">contact us</a> via the %ui_name% support mailing list.
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

    end
  end
end
