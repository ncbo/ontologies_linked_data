module LinkedData
  module Services
    class OntologySubmissionArchiver < OntologySubmissionProcess

      FILES_TO_DELETE = ['labels.ttl', 'mappings.ttl', 'obsolete.ttl', 'owlapi.xrdf', 'errors.log']
      FOLDERS_TO_DELETE = ['unzipped']
      FILE_SIZE_ZIPPING_THRESHOLD = 100 * 1024 * 1024 # 100MB

      def process
        archive_submission
      end

      private

      def archive_submission
        @submission.ontology.bring(:submissions)
        submissions = @submission.ontology.submissions
        return if submissions.nil?

        submissions.each { |s| s.bring(:submissionId) }
        submission = submissions.sort { |a, b| b.submissionId <=> a.submissionId }.first

        return unless @submission.submissionId < submission.submissionId

        @submission.submissionStatus = nil
        status = LinkedData::Models::SubmissionStatus.find("ARCHIVED").first
        @submission.add_submission_status(status)

        @submission.unindex

        # Delete everything except for original ontology file.
        delete_old_submission_files
        @submission.uploadFilePath = zip_submission_uploaded_file
      end

      def zip_submission_uploaded_file
        @submission.bring(:uploadFilePath) if @submission.bring?(:uploadFilePath)
        return @submission.uploadFilePath if @submission.zipped?

        return @submission.uploadFilePath if @submission.uploadFilePath.nil? || @submission.uploadFilePath.empty?

        return @submission.uploadFilePath if File.size(@submission.uploadFilePath) < FILE_SIZE_ZIPPING_THRESHOLD

        old_path = @submission.uploadFilePath
        zip_file = Utils::FileHelpers.zip_file(old_path)
        FileUtils.rm(old_path, force: true)
        zip_file
      end

      def delete_old_submission_files
        path_to_repo = @submission.data_folder
        submission_files = FILES_TO_DELETE.map { |f| File.join(path_to_repo, f) }
        submission_files.push(@submission.csv_path)
        submission_files.push(@submission.parsing_log_path) unless @submission.parsing_log_path.nil?
        FileUtils.rm(submission_files, force: true)
        submission_folders = FOLDERS_TO_DELETE.map { |f| File.join(path_to_repo, f) }
        submission_folders.each { |d| FileUtils.remove_dir(d) if File.directory?(d) }
      end

    end

  end
end
