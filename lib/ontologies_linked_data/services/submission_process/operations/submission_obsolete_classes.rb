module LinkedData
  module Services

    class ObsoleteClassesGenerator < OntologySubmissionProcess

      def process(logger, options)
        status = LinkedData::Models::SubmissionStatus.find('OBSOLETE').first
        begin
          generate_obsolete_classes(logger, options[:file_path])
          @submission.add_submission_status(status)
          @submission.save
        rescue Exception => e
          logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
          @submission.save
          # if obsolete fails the parsing fails
          raise e
        end
        @submission
      end

      private

      def generate_obsolete_classes(logger, file_path)
        @submission.bring(:obsoleteProperty) if @submission.bring?(:obsoleteProperty)
        @submission.bring(:obsoleteParent) if @submission.bring?(:obsoleteParent)
        classes_deprecated = []
        if @submission.obsoleteProperty &&
          @submission.obsoleteProperty.to_s != "http://www.w3.org/2002/07/owl#deprecated"

          predicate_obsolete = RDF::URI.new(@submission.obsoleteProperty.to_s)
          query_obsolete_predicate = <<eos
SELECT ?class_id ?deprecated
FROM #{@submission.id.to_ntriples}
WHERE { ?class_id #{predicate_obsolete.to_ntriples} ?deprecated . }
eos
          Goo.sparql_query_client.query(query_obsolete_predicate).each_solution do |sol|
            classes_deprecated << sol[:class_id].to_s unless ["0", "false"].include? sol[:deprecated].to_s
          end
          logger.info("Obsolete found #{classes_deprecated.length} for property #{@submission.obsoleteProperty.to_s}")
        end
        if @submission.obsoleteParent.nil?
          # try to find oboInOWL obsolete.
          obo_in_owl_obsolete_class = LinkedData::Models::Class
                                        .find(LinkedData::Utils::Triples.obo_in_owl_obsolete_uri)
                                        .in(@submission).first
          @submission.obsoleteParent = LinkedData::Utils::Triples.obo_in_owl_obsolete_uri if obo_in_owl_obsolete_class
        end
        if @submission.obsoleteParent
          class_obsolete_parent = LinkedData::Models::Class
                                    .find(@submission.obsoleteParent)
                                    .in(@submission).first
          if class_obsolete_parent
            descendents_obsolete = class_obsolete_parent.descendants
            logger.info("Found #{descendents_obsolete.length} descendents of obsolete root #{@submission.obsoleteParent.to_s}")
            descendents_obsolete.each do |obs|
              classes_deprecated << obs.id
            end
          else
            logger.error("Submission #{@submission.id.to_s} obsoleteParent #{@submission.obsoleteParent.to_s} not found")
          end
        end
        if classes_deprecated.length > 0
          classes_deprecated.uniq!
          logger.info("Asserting owl:deprecated statement for #{classes_deprecated} classes")
          save_in_file = File.join(File.dirname(file_path), "obsolete.ttl")
          fsave = File.open(save_in_file, "w")
          classes_deprecated.each do |class_id|
            fsave.write(LinkedData::Utils::Triples.obselete_class_triple(class_id) + "\n")
          end
          fsave.close()
          Goo.sparql_data_client.append_triples_from_file(
            @submission.id,
            save_in_file,
            mime_type = "application/x-turtle")
        end
      end
    end
  end
end