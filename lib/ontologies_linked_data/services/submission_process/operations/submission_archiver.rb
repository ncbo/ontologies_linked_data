module LinkedData
  module Services
    class OntologySubmissionArchiver < OntologySubmissionProcess

      FILES_TO_DELETE = %w[labels.ttl mappings.ttl obsolete.ttl owlapi.xrdf errors.log]


      def process
        submission_archive
      end

      private
      def submission_archive
        @submission.submissionStatus = nil
        status = LinkedData::Models::SubmissionStatus.find("ARCHIVED").first
        @submission.add_submission_status(status)


        # Delete everything except for original ontology file.
        @submission.ontology.bring(:submissions)
        submissions = @submission.ontology.submissions
        unless submissions.nil?
          submissions.each { |s| s.bring(:submissionId) }
          submission = submissions.sort { |a, b| b.submissionId <=> a.submissionId }.first
          # Don't perform deletion if this is the most recent submission.
          delete_old_submission_files if @submission.submissionId < submission.submissionId
        end
      end

      def delete_old_submission_files
        path_to_repo = @submission.data_folder
        submission_files = FILES_TO_DELETE.map { |f| File.join(path_to_repo, f) }
        submission_files.push(@submission.csv_path)
        submission_files.push(@submission.parsing_log_path) unless @submission.parsing_log_path.nil?
        FileUtils.rm(submission_files, force: true)
      end

    end


  end
end
