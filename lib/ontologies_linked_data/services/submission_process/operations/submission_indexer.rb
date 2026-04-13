module LinkedData
  module Services
    class OntologySubmissionIndexer < OntologySubmissionProcess

      def process(logger, options = nil)
        process_indexation(logger, options)
      end

      private

      def process_indexation(logger, options)

        status = LinkedData::Models::SubmissionStatus.find('INDEXED').first
        begin
          index(logger, options[:commit], false)
          @submission.add_submission_status(status)
        rescue StandardError => e
          logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
          FileUtils.rm(@submission.csv_path) if File.file?(@submission.csv_path)
        ensure
          @submission.save
        end
      end

      def index(logger, commit = true, optimize = true)
        page = 0
        size = 2500
        count_classes = 0

        time = Benchmark.realtime do
          @submission.bring(:ontology) if @submission.bring?(:ontology)
          @submission.ontology.bring(:acronym) if @submission.ontology.bring?(:acronym)
          @submission.ontology.bring(:provisionalClasses) if @submission.ontology.bring?(:provisionalClasses)
          csv_writer = LinkedData::Utils::OntologyCSVWriter.new
          csv_writer.open(@submission.ontology, @submission.csv_path)

          LinkedData::Models::Class.ancestors_cache = compute_ancestors_map(logger)

          begin
            logger.info("Indexing ontology terms: #{@submission.ontology.acronym}...")
            t0 = Time.now
            @submission.ontology.unindex(false)
            logger.info("Removed ontology terms index (#{Time.now - t0}s)"); logger.flush

            paging = LinkedData::Models::Class.in(@submission).include(:unmapped).aggregate(:count, :children).page(page, size)
            # a fix for SKOS ontologies, see https://github.com/ncbo/ontologies_api/issues/20
            @submission.bring(:hasOntologyLanguage) unless @submission.loaded_attributes.include?(:hasOntologyLanguage)
            cls_count = @submission.hasOntologyLanguage.skos? ? -1 : @submission.class_count(logger)
            paging.page_count_set(cls_count) unless cls_count < 0
            total_pages = paging.page(1, size).all.total_pages
            num_threads = [total_pages, LinkedData.settings.indexing_num_threads].min
            threads = []
            page_classes = nil

            num_threads.times do |num|
              threads[num] = Thread.new {
                Thread.current['done'] = false
                Thread.current['page_len'] = -1
                Thread.current['prev_page_len'] = -1

                while !Thread.current['done']
                  @submission.synchronize do
                    page = (page == 0 || page_classes.next?) ? page + 1 : nil

                    if page.nil?
                      Thread.current['done'] = true
                    else
                      Thread.current['page'] = page || 'nil'
                      RequestStore.store[:requested_lang] = :ALL
                      page_classes = paging.page(page, size).all
                      count_classes += page_classes.length
                      Thread.current['page_classes'] = page_classes
                      Thread.current['page_len'] = page_classes.length
                      Thread.current['t0'] = Time.now

                      # nothing retrieved even though we're expecting more records
                      if total_pages > 0 && page_classes.empty? && (Thread.current['prev_page_len'] == -1 || Thread.current['prev_page_len'] == size)
                        j = 0
                        num_calls = LinkedData.settings.num_retries_4store

                        while page_classes.empty? && j < num_calls do
                          j += 1
                          logger.error("Thread #{num + 1}: Empty page encountered. Retrying #{j} times...")
                          sleep(2)
                          page_classes = paging.page(page, size).all
                          logger.info("Thread #{num + 1}: Success retrieving a page of #{page_classes.length} classes after retrying #{j} times...") unless page_classes.empty?
                        end

                        if page_classes.empty?
                          msg = "Thread #{num + 1}: Empty page #{Thread.current["page"]} of #{total_pages} persisted after retrying #{j} times. Indexing of #{@submission.id.to_s} aborted..."
                          logger.error(msg)
                          raise msg
                        else
                          Thread.current['page_classes'] = page_classes
                        end
                      end

                      if page_classes.empty?
                        if total_pages > 0
                          logger.info("Thread #{num + 1}: The number of pages reported for #{@submission.id.to_s} - #{total_pages} is higher than expected #{page - 1}. Completing indexing...")
                        else
                          logger.info("Thread #{num + 1}: Ontology #{@submission.id.to_s} contains #{total_pages} pages...")
                        end

                        break
                      end

                      Thread.current['prev_page_len'] = Thread.current['page_len']
                    end
                  end

                  break if Thread.current['done']

                  logger.info("Thread #{num + 1}: Page #{Thread.current["page"]} of #{total_pages} - #{Thread.current["page_len"]} ontology terms retrieved in #{Time.now - Thread.current["t0"]} sec.")
                  Thread.current['t0'] = Time.now

                  Thread.current['page_classes'].each do |c|
                    begin
                      # this cal is needed for indexing of properties
                      LinkedData::Models::Class.map_attributes(c, paging.equivalent_predicates, include_languages: true)
                    rescue Exception
                      i = 0
                      num_calls = LinkedData.settings.num_retries_4store
                      success = nil

                      while success.nil? && i < num_calls do
                        i += 1
                        logger.error("Thread #{num + 1}: Exception while mapping attributes for #{c.id.to_s}. Retrying #{i} times...")
                        sleep(2)

                        begin
                          LinkedData::Models::Class.map_attributes(c, paging.equivalent_predicates, include_languages: true)
                          logger.info("Thread #{num + 1}: Success mapping attributes for #{c.id.to_s} after retrying #{i} times...")
                          success = true
                        rescue Exception => e1
                          success = nil

                          if i == num_calls
                            logger.error("Thread #{num + 1}: Error mapping attributes for #{c.id.to_s}:")
                            logger.error("Thread #{num + 1}: #{e1.class}: #{e1.message} after retrying #{i} times...\n#{e1.backtrace.join("\n\t")}")
                            logger.flush
                          end
                        end
                      end
                    end

                    # TODO: Remove once precomputed ancestors are validated against production data
                    validate_class_ancestors(c, logger)

                    @submission.synchronize do
                      csv_writer.write_class(c)
                    end
                  end
                  logger.info("Thread #{num + 1}: Page #{Thread.current["page"]} of #{total_pages} attributes mapped in #{Time.now - Thread.current["t0"]} sec.")

                  Thread.current['t0'] = Time.now
                  LinkedData::Models::Class.indexBatch(Thread.current['page_classes'])
                  logger.info("Thread #{num + 1}: Page #{Thread.current["page"]} of #{total_pages} - #{Thread.current["page_len"]} ontology terms indexed in #{Time.now - Thread.current["t0"]} sec.")
                  logger.flush
                end
              }
            end

            threads.map { |t| t.join }
            csv_writer.close

            begin
              # index provisional classes
              @submission.ontology.provisionalClasses.each { |pc| pc.index }
            rescue Exception => e
              logger.error("Error while indexing provisional classes for ontology #{@submission.ontology.acronym}:")
              logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
              logger.flush
            end

            if commit
              t0 = Time.now
              LinkedData::Models::Class.indexCommit()
              logger.info("Ontology terms index commit in #{Time.now - t0} sec.")
            end
          rescue StandardError => e
            csv_writer.close
            logger.error("\n\n#{e.class}: #{e.message}\n")
            logger.error(e.backtrace)
            raise e
          ensure
            LinkedData::Models::Class.ancestors_cache = nil
          end
        end
        logger.info("Completed indexing ontology terms: #{@submission.ontology.acronym} in #{time} sec. #{count_classes} classes.")
        logger.flush

        if optimize
          logger.info('Optimizing ontology terms index...')
          time = Benchmark.realtime do
            LinkedData::Models::Class.indexOptimize()
          end
          logger.info("Completed optimizing ontology terms index in #{time} sec.")
        end
      end

      def compute_ancestors_map(logger)
        @submission.bring(:hasOntologyLanguage) unless @submission.loaded_attributes.include?(:hasOntologyLanguage)
        tree_property = LinkedData::Models::Class.tree_view_property(@submission)
        graph = @submission.id.to_s

        logger.info("Precomputing ancestor hierarchy for indexing...")
        t0 = Time.now

        direct_parents = fetch_all_parent_edges(graph, tree_property)
        edge_count = direct_parents.values.sum(&:length)
        logger.info("Fetched #{edge_count} parent-child edges for #{direct_parents.size} classes in #{Time.now - t0}s")

        ancestors_map = {}
        direct_parents.each_key do |cls|
          compute_ancestors_for(cls, direct_parents, ancestors_map)
        end

        logger.info("Computed ancestor map for #{ancestors_map.size} classes in #{Time.now - t0}s")
        ancestors_map
      end

      def fetch_all_parent_edges(graph, tree_property)
        direct_parents = {}
        page_size = 50_000
        offset = 0

        loop do
          query = "SELECT ?child ?parent WHERE { " \
                  "GRAPH <#{graph}> { " \
                  "?child <#{tree_property}> ?parent . " \
                  "FILTER(isIRI(?parent)) " \
                  "} } LIMIT #{page_size} OFFSET #{offset}"

          count = 0
          Goo.sparql_query_client.query(query, query_options: { rules: :NONE }, graphs: [graph]).each do |sol|
            child = sol[:child].to_s
            parent = sol[:parent].to_s
            next unless child.start_with?("http") && parent.start_with?("http")
            (direct_parents[child] ||= []) << parent
            count += 1
          end

          break if count < page_size
          offset += page_size
        end

        direct_parents
      end

      def compute_ancestors_for(cls, direct_parents, ancestors_map)
        return ancestors_map[cls] if ancestors_map.key?(cls)

        visited = Set.new
        queue = (direct_parents[cls] || []).dup

        while queue.any?
          parent = queue.shift
          next if visited.include?(parent)
          visited.add(parent)

          if ancestors_map.key?(parent)
            visited.merge(ancestors_map[parent])
          else
            (direct_parents[parent] || []).each do |grandparent|
              queue.push(grandparent) unless visited.include?(grandparent)
            end
          end
        end

        ancestors_map[cls] = visited
      end

      # TODO: Remove once precomputed ancestors are validated against production data
      def validate_class_ancestors(cls, logger)
        cls_id = cls.id.to_s
        ancestors_cache = LinkedData::Models::Class.ancestors_cache
        return unless ancestors_cache

        old_ancestors = cls.retrieve_hierarchy_ids(:ancestors)
        old_ancestors.select! { |x| !x["owl#Thing"] }
        new_ancestors = (ancestors_cache[cls_id] || Set.new).reject { |x| x["owl#Thing"] }.to_set

        unless old_ancestors == new_ancestors
          only_old = old_ancestors - new_ancestors
          only_new = new_ancestors - old_ancestors
          logger.warn("Ancestor mismatch for #{cls_id}: old=#{old_ancestors.size} new=#{new_ancestors.size} only_in_old=#{only_old.to_a.first(5)} only_in_new=#{only_new.to_a.first(5)}")
        end
      rescue StandardError => e
        logger.warn("Ancestor validation failed for #{cls_id}: #{e.class}: #{e.message}")
      end

    end
  end
end

