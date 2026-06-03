module LinkedData
  module Services
    class OntologySubmissionIndexer < OntologySubmissionProcess

      def process(logger, options = nil)
        process_indexation(logger, options)
      end

      private

      def process_indexation(logger, options)
        options ||= {}

        status = LinkedData::Models::SubmissionStatus.find('INDEXED').first
        begin
          index(logger,
                commit: options[:commit],
                optimize: false,
                commit_within: options[:commit_within],
                generate_csv: generate_csv?(options),
                unindex_existing: unindex_existing?(options))
          @submission.add_submission_status(status)
        rescue StandardError => e
          logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
          FileUtils.rm(@submission.csv_path) if generate_csv?(options) && File.file?(@submission.csv_path)
        ensure
          @submission.save
        end
      end

      def generate_csv?(options)
        !options[:generate_csv].eql?(false)
      end

      def unindex_existing?(options)
        !options[:unindex_existing].eql?(false)
      end

      TERM_INDEX_PAGE_SIZE = 5000

      def index(logger, commit: true, optimize: true, commit_within: 30_000, generate_csv: true, unindex_existing: true, page_size: TERM_INDEX_PAGE_SIZE)
        page = 0
        size = page_size
        count_classes = 0
        previous_requested_lang = RequestStore.store[:requested_lang]

        time = Benchmark.realtime do
          @submission.bring(:ontology) if @submission.bring?(:ontology)
          @submission.ontology.bring(:acronym) if @submission.ontology.bring?(:acronym)
          @submission.ontology.bring(:provisionalClasses) if @submission.ontology.bring?(:provisionalClasses)
          LinkedData::Models::Class.reset_ontology_rank_cache
          csv_writer = nil
          if generate_csv
            csv_writer = LinkedData::Utils::OntologyCSVWriter.new
            csv_writer.open(@submission.ontology, @submission.csv_path)
          end

          LinkedData::Models::Class.ancestors_cache = compute_ancestors_map(logger)

          begin
            # Set once for the whole indexing run; restored in the ensure block below.
            # In the previous multi-threaded indexer this lived inside per-page worker
            # threads, so the change was thread-local. Single-threaded, it would otherwise
            # leak into @submission.save's after_save Solr callback and into the next
            # ontology's bring_remaining.
            RequestStore.store[:requested_lang] = :ALL

            logger.info("Indexing ontology terms: #{@submission.ontology.acronym}...")
            t0 = Time.now
            if unindex_existing
              @submission.ontology.unindex_by_acronym(false)
              logger.info("Removed ontology terms index (#{Time.now - t0}s)"); logger.flush
            else
              logger.info("Skipping unindex_by_acronym (fresh target collection)"); logger.flush
            end

            paging = LinkedData::Models::Class.in(@submission).include(:unmapped).aggregate(:count, :children).page(page, size)
            # a fix for SKOS ontologies, see https://github.com/ncbo/ontologies_api/issues/20
            @submission.bring(:hasOntologyLanguage) unless @submission.loaded_attributes.include?(:hasOntologyLanguage)
            cls_count = @submission.hasOntologyLanguage.skos? ? -1 : @submission.class_count(logger)
            first_page = nil
            if cls_count >= 0
              paging.page_count_set(cls_count)
              total_pages = (cls_count / size.to_f).ceil
            else
              first_page = paging.page(1, size).all
              total_pages = first_page.total_pages
            end
            # Fetch one page of classes from the triplestore. Used for the synchronous
            # fetch of page 1 and for the background prefetch of later pages.
            #
            # RequestStore is thread-local, so the :ALL language override set on the
            # main thread above does NOT propagate to a prefetch thread; it must be set
            # again here, or the background fetch would drop multilingual values.
            #
            # equivalent_predicates is identical for every page (same query shape) and
            # is returned alongside the page so the consumer never reads it from `paging`
            # concurrently with a background fetch.
            fetch_page = lambda do |pnum|
              RequestStore.store[:requested_lang] = :ALL
              t_fetch = Time.now
              page_classes = (pnum == 1 && first_page) ? first_page : paging.page(pnum, size).all
              # Measure the actual SPARQL fetch wall-time here so the per-page
              # retrieval timing remains meaningful even when the fetch runs on a
              # background prefetch thread. (Summing these across pages overcounts,
              # since prefetched pages overlap the previous page's work — the
              # overlap is the win; this metric is the raw per-page fetch cost.)
              [page_classes, paging.equivalent_predicates, Time.now - t_fetch]
            end

            # Prime page 1 synchronously, then overlap each page's mapping + Solr write
            # with the background fetch of the next page. `paging` is mutated by #page,
            # so only one thread ever touches it at a time: the main thread fetches
            # page 1, and thereafter each fetch runs on its own thread while the main
            # thread is busy mapping/indexing and never touching `paging`.
            current = total_pages >= 1 ? fetch_page.call(1) : nil
            page = 1

            while current && page <= total_pages
              page_classes, equivalent_predicates, fetch_seconds = current

              if page_classes.empty?
                logger.info("Page #{page} of #{total_pages} returned no classes. Completing indexing for #{@submission.id.to_s}.")
                break
              end

              count_classes += page_classes.length
              logger.info("Page #{page} of #{total_pages} - #{page_classes.length} ontology terms retrieved in #{fetch_seconds} sec.")

              # Kick off the next page's fetch before the CPU-bound mapping so the
              # triplestore round-trip overlaps with this page's mapping + Solr write.
              next_page = page + 1
              next_thread =
                if next_page <= total_pages
                  Thread.new(next_page) do |pn|
                    Thread.current.report_on_exception = false
                    fetch_page.call(pn)
                  end
                end

              t0 = Time.now
              docs = []
              page_classes.each do |c|
                begin
                  # this call is needed for indexing of properties
                  LinkedData::Models::Class.map_attributes(c, equivalent_predicates, include_languages: true)
                rescue StandardError => e
                  logger.error("Error mapping attributes for #{c.id.to_s}: #{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                  logger.flush
                end

                # TODO: Remove once precomputed ancestors are validated against production data
                validate_class_ancestors(c, logger) if ENV['OP_VALIDATE_ANCESTORS']

                csv_writer.write_class(c) if csv_writer
                docs << c.indexable_object
              end
              logger.info("Page #{page} of #{total_pages} attributes mapped in #{Time.now - t0} sec.")

              t0 = Time.now
              page_commit = commit && !commit_within.nil?
              LinkedData::Models::Class.search_client.index_document(
                docs,
                commit: page_commit,
                commit_within: page_commit ? commit_within : nil
              )
              logger.info("Page #{page} of #{total_pages} - #{page_classes.length} ontology terms indexed in #{Time.now - t0} sec.")
              logger.flush

              # Block until the prefetch completes (usually already done). Thread#value
              # re-raises a fetch error here on the main thread, where the rescue below
              # handles it — a failed fetch must not silently drop the remaining pages.
              current = next_thread&.value
              page = next_page
            end

            csv_writer.close if csv_writer

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
            csv_writer.close if csv_writer
            logger.error("\n\n#{e.class}: #{e.message}\n")
            logger.error(e.backtrace)
            raise e
          ensure
            LinkedData::Models::Class.ancestors_cache = nil
            RequestStore.store[:requested_lang] = previous_requested_lang
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

        sparql_ancestors = nil
        sparql_time = Benchmark.realtime do
          sparql_ancestors = cls.retrieve_hierarchy_ids(:ancestors)
          sparql_ancestors.select! { |x| !x["owl#Thing"] }
        end

        cached_ancestors = nil
        cache_time = Benchmark.realtime do
          cached_ancestors = (ancestors_cache[cls_id] || Set.new).reject { |x| x["owl#Thing"] }.to_set
        end

        if sparql_ancestors == cached_ancestors
          logger.info("Ancestor OK for #{cls_id}: #{sparql_ancestors.size} ancestors, sparql=#{sparql_time.round(4)}s cache=#{cache_time.round(4)}s")
        else
          only_sparql = sparql_ancestors - cached_ancestors
          only_cached = cached_ancestors - sparql_ancestors
          logger.warn("Ancestor MISMATCH for #{cls_id}: sparql=#{sparql_ancestors.size} (#{sparql_time.round(4)}s) cache=#{cached_ancestors.size} (#{cache_time.round(4)}s) only_in_sparql=#{only_sparql.to_a.first(5)} only_in_cache=#{only_cached.to_a.first(5)}")
        end
      rescue StandardError => e
        logger.warn("Ancestor validation failed for #{cls_id}: #{e.class}: #{e.message}")
      end

    end
  end
end
