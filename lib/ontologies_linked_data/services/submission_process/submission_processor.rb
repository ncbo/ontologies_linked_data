module LinkedData
  module Services
    class OntologyProcessor < OntologySubmissionProcess

      ################################################################
      # Possible options with their defaults:
      #   process_rdf       = false
      #   index_search      = false
      #   index_properties  = false
      #   index_commit      = false
      #   run_metrics       = false
      #   reasoning         = false
      #   diff              = false
      #   archive           = false
      #   if no options passed, ALL actions, except for archive = true
      ################################################################
      def process(logger, options = nil)
        process_submission(logger, options)
      end

      private

      def process_submission(logger, options = {})
        # Wrap the whole process so we can email results
        begin
          archive, diff, index_commit, index_properties,
            index_search, process_rdf, reasoning, run_metrics = get_options(options)

          @submission.bring_remaining
          @submission.ontology.bring_remaining

          logger.info("Starting to process #{@submission.ontology.acronym}/submissions/#{@submission.submissionId}")
          logger.flush
          LinkedData::Parser.logger = logger

          if archive
            @submission.archive
          else

            @submission.generate_rdf(logger, reasoning: reasoning) if process_rdf

            parsed = @submission.ready?(status: [:rdf, :rdf_labels])

            if index_search
              unless parsed
                raise StandardError, "The submission #{@submission.ontology.acronym}/submissions/#{@submission.submissionId}
                                cannot be indexed because it has not been successfully parsed"
              end
              @submission.index(logger, commit: index_commit)
            end

            if index_properties
              unless parsed
                raise Exception, "The properties for the submission #{@submission.ontology.acronym}/submissions/#{@submission.submissionId}
                                cannot be indexed because it has not been successfully parsed"

              end
              @submission.index_properties(logger, commit: index_commit)
            end

            if run_metrics
              unless parsed
                raise StandardError, "Metrics cannot be generated on the submission
                        #{@submission.ontology.acronym}/submissions/#{@submission.submissionId}
                        because it has not been successfully parsed"
              end
              @submission.generate_metrics(logger)
            end
            @submission.generate_diff(logger) if diff
          end

          @submission.save
          logger.info("Submission processing of #{@submission.id} completed successfully")
          logger.flush
        ensure
          # make sure results get emailed
          notify_submission_processed(logger)
        end
        @submission
      end

      def notify_submission_processed(logger)
        begin
          LinkedData::Utils::Notifications.submission_processed(@submission) unless archive
        rescue StandardError => e
          logger.error("Email sending failed: #{e.message}\n#{e.backtrace.join("\n\t")}"); logger.flush
        end
      end

      def get_options(options)

        if options.empty?
          process_rdf = true
          index_search = true
          index_properties = true
          index_commit = true
          run_metrics = true
          reasoning = true
          diff = true
          archive = false
        else
          process_rdf = options[:process_rdf] == true
          index_search = options[:index_search] == true
          index_properties = options[:index_properties] == true
          run_metrics = options[:run_metrics] == true

          reasoning = if !process_rdf || options[:reasoning] == false
                        false
                      else
                        true
                      end

          index_commit = if (!index_search && !index_properties) || options[:index_commit] == false
                           false
                         else
                           true
                         end

          diff = options[:diff] == true
          archive = options[:archive] == true
        end
        [archive, diff, index_commit, index_properties, index_search, process_rdf, reasoning, run_metrics]
      end
    end
  end
end
