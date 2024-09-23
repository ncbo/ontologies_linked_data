module LinkedData
  module Services
    class SubmissionMetricsCalculator < OntologySubmissionProcess
      def process(logger, options = nil)
        process_metrics(logger)
      end

      def generate_umls_metrics_file(tr_file_path=nil)
        tr_file_path ||= @submission.triples_file_path
        class_count = 0
        indiv_count = 0
        prop_count = 0
        max_depth = 0

        File.foreach(tr_file_path) do |line|
          class_count += 1 if line =~ /owl:Class/
          indiv_count += 1 if line =~ /owl:NamedIndividual/
          prop_count += 1 if line =~ /owl:ObjectProperty/
          prop_count += 1 if line =~ /owl:DatatypeProperty/
        end

        # Get max depth from the metrics.csv file which is already generated
        # by owlapi_wrapper when new submission of UMLS ontology is created.
        # Ruby code/sparql for calculating max_depth fails for large UMLS
        # ontologies with AllegroGraph backend
        metrics_from_owlapi = @submission.metrics_from_file
        max_depth = metrics_from_owlapi[1][3] unless metrics_from_owlapi.empty?

        generate_metrics_file(class_count, indiv_count, prop_count, max_depth)
      end

      private

      def process_metrics(logger)
        status = LinkedData::Models::SubmissionStatus.find('METRICS').first
        begin
          compute_metrics(logger)
          @submission.add_submission_status(status)
        rescue StandardError => e
          logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.metrics = nil
          @submission.add_submission_status(status.get_error_status)
        ensure
          @submission.save
        end
      end

      def compute_metrics(logger)
        metrics = metrics_for_submission(logger)
        metrics.id = RDF::URI.new(@submission.id.to_s + '/metrics')
        exist_metrics = LinkedData::Models::Metric.find(metrics.id).first
        exist_metrics.delete if exist_metrics
        metrics.save
        @submission.metrics = metrics
        @submission
      end

      def metrics_for_submission(logger)
        logger.info('metrics_for_submission start')
        logger.flush
        begin
          @submission.bring(:submissionStatus) if @submission.bring?(:submissionStatus)
          cls_metrics = LinkedData::Metrics.class_metrics(@submission, logger)
          logger.info('class_metrics finished')
          logger.flush
          metrics = LinkedData::Models::Metric.new

          cls_metrics.each do |k,v|
            unless v.instance_of?(Integer)
              begin
                v = Integer(v)
              rescue ArgumentError
                v = 0
              rescue TypeError
                v = 0
              end
            end
            metrics.send("#{k}=",v)
          end
          indiv_count = LinkedData::Metrics.number_individuals(logger, @submission)
          metrics.individuals = indiv_count
          logger.info('individuals finished')
          logger.flush
          prop_count = LinkedData::Metrics.number_properties(logger, @submission)
          metrics.properties = prop_count
          logger.info('properties finished')
          logger.flush
          # re-generate metrics file
          generate_metrics_file(cls_metrics[:classes], indiv_count, prop_count, cls_metrics[:maxDepth])
          logger.info('generation of metrics file finished')
          logger.flush
        rescue StandardError => e
          logger.error(e.message)
          logger.error(e)
          logger.flush
          metrics = nil
        end
        metrics
      end

      def generate_metrics_file(class_count, indiv_count, prop_count, max_depth)
        CSV.open(@submission.metrics_path, 'wb') do |csv|
          csv << ['Class Count', 'Individual Count', 'Property Count', 'Max Depth']
          csv << [class_count, indiv_count, prop_count, max_depth]
        end
      end

    end
  end
end
