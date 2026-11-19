module LinkedData
  module Services
    class OntologySubmissionArchiver < OntologySubmissionProcess

      FILES_TO_DELETE = ['labels.ttl', 'mappings.ttl', 'obsolete.ttl', 'owlapi.xrdf', 'errors.log']
      FOLDERS_TO_DELETE = ['unzipped']
      FILE_SIZE_ZIPPING_THRESHOLD = 100 * 1024 * 1024 # 100MB

      def process(force: false)
        archive_submission(force: force)
      end

      private

      def archive_submission(force: false)
        @submission.ontology.bring(:submissions)
        submissions = @submission.ontology.submissions
        return if submissions.nil?

        submissions.each { |s| s.bring(:submissionId) }
        submission = submissions.sort { |a, b| b.submissionId <=> a.submissionId }.first
        latest_submission_id = submission&.submissionId || 0
        @submission.bring(:submissionId) if @submission.bring?(:submissionId)

        return if (@submission.submissionId >= latest_submission_id) && !force

        @submission.submissionStatus = nil
        status = LinkedData::Models::SubmissionStatus.find("ARCHIVED").first
        @submission.add_submission_status(status)

        @submission.unindex

        # Delete everything except for original ontology file.
        delete_old_graph
        delete_old_submission_files
        zip_submission_uploaded_file
      end

      # The original is deleted only once the submission is saved pointing at the zip, so a
      # submission that fails to save keeps the file its uploadFilePath names.
      def zip_submission_uploaded_file
        @submission.bring(:uploadFilePath) if @submission.bring?(:uploadFilePath)
        old_path = @submission.uploadFilePath&.to_s
        return if old_path.nil? || old_path.empty?
        return if @submission.zipped?
        return repoint_to_leftover_zip(old_path) unless File.file?(old_path)
        return if File.size(old_path) < FILE_SIZE_ZIPPING_THRESHOLD

        zip_path = Utils::FileHelpers.zip_file(old_path)
        @submission.uploadFilePath = zip_path
        begin
          @submission.save
        rescue StandardError => e
          @submission.uploadFilePath = old_path
          # An invalid submission is rejected before anything is written. After any other
          # error the store may hold either path, so both files are kept.
          FileUtils.rm_f(zip_path) if e.is_a?(Goo::Base::NotValidException)
          raise
        end
        FileUtils.rm_f(old_path)
      end

      # Earlier versions deleted the original before saving, so a failed save left the
      # submission pointing at a missing file with its zip next to it.
      def repoint_to_leftover_zip(old_path)
        zip_path = "#{old_path}.zip"
        @submission.uploadFilePath = zip_path if Utils::FileHelpers.zip?(zip_path)
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

      def delete_old_graph
        Goo.sparql_data_client.delete_graph(@submission.id)
      end

    end

  end
end