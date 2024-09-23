module LinkedData
  module Services
    class SubmissionPropertiesIndexer < OntologySubmissionProcess

      def process(logger, options = nil)
        process_indexation(logger, options)
      end

      private

      def process_indexation(logger, options)
        status = LinkedData::Models::SubmissionStatus.find('INDEXED_PROPERTIES').first
        begin
          index_properties(logger, commit: options[:commit], optimize: false)
          @submission.add_submission_status(status)
        rescue StandardError => e
          logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
        ensure
          @submission.save
        end
      end

      def index_properties(logger, commit: true, optimize: true)
        page = 1
        size = 2500
        count_props = 0

        time = Benchmark.realtime do
          @submission.bring(:ontology) if @submission.bring?(:ontology)
          @submission.ontology.bring(:acronym) if @submission.ontology.bring?(:acronym)
          logger.info("Indexing ontology properties: #{@submission.ontology.acronym}...")
          t0 = Time.now
          @submission.ontology.unindex_properties(commit)
          logger.info("Removed ontology properties index in #{Time.now - t0} seconds."); logger.flush

          props = @submission.ontology.properties
          count_props = props.length
          total_pages = (count_props/size.to_f).ceil
          logger.info("Indexing a total of #{total_pages} pages of #{size} properties each.")

          props.each_slice(size) do |prop_batch|
            t = Time.now
            LinkedData::Models::Class.indexBatch(prop_batch, :property)
            logger.info("Page #{page} of ontology properties indexed in #{Time.now - t} seconds."); logger.flush
            page += 1
          end

          if commit
            t0 = Time.now
            LinkedData::Models::Class.indexCommit(nil, :property)
            logger.info("Ontology properties index commit in #{Time.now - t0} seconds.")
          end
        end
        logger.info("Completed indexing ontology properties of #{@submission.ontology.acronym} in #{time} sec. Total of #{count_props} properties indexed.")
        logger.flush

        if optimize
          logger.info('Optimizing ontology properties index...')
          time = Benchmark.realtime do
            LinkedData::Models::Class.indexOptimize(nil, :property)
          end
          logger.info("Completed optimizing ontology properties index in #{time} seconds.")
        end
      end
    end
  end
end

