require 'open3'
require 'csv'

module LinkedData
  module Mappings
    class BatchProcess
      def initialize(process_name,paging,dumper,
                     line_parser,ok_mapping,skip_mapping,
                     logger,sort_field,*onts)
        @record_tuple = Struct.new(:record_a,:record_b)
        @process_name = process_name
        @paging = paging
        @dumper = dumper
        @ok_mapping = ok_mapping
        @skip_mapping = skip_mapping
        @line_parser = line_parser
        @sort_field = sort_field
        @logger = logger || Logger.new(STDOUT)
        process = get_process(process_name)
        @logger.info("using process id #{process.id.to_ntriples}")
        mappings_folder = File.join([LinkedData.settings.repository_folder,"mappings"])
        if not Dir.exist?(mappings_folder)
          FileUtils.mkdir_p(mappings_folder)
        end

        @ontologies = onts
        @process = process
        raise Exception "Only support for two ontologies" if @ontologies.length != 2
      end

      def get_process(name)
        #process
        ps = LinkedData::Models::MappingProcess.where({:name => name })
        if ps.length > 0
          return ps.first
        end

        #just some user
        user = LinkedData::Models::User.where(username: "ncbo").include(:username).first
        if user.nil?
          #probably devel environment - create it
          user = LinkedData::Models::User.new(:username => "ncbo", :email => "admin@bioontology.org" ) 
          user.password = "test"
          user.save
        end

        p = LinkedData::Models::MappingProcess.new(:creator => user, :name => name)
        p.save
        ps = LinkedData::Models::MappingProcess.where({:name => name }).to_a
        return ps[0]
      end

      def create_record_tuple(record_a,record_b)
        tuple = @record_tuple.new
        if record_a.acronym < record_b.acronym
          tuple.record_a = record_a
          tuple.record_b = record_b
        else
          tuple.record_a = record_b
          tuple.record_b = record_a
        end
        return tuple
      end

      def self.mappings_ontology_folder(ont)
        ont_folder = File.join([LinkedData.settings.repository_folder,ont.acronym,'mappings'])
        if not Dir.exist?(ont_folder)
          FileUtils.mkdir_p(ont_folder)
        end
        return ont_folder
      end

      def start()
        t0 = Time.now 
        @logger.info("Starting batch ...")
        label_dumps_file_paths = dumps()
        sorted_file_path = sort(label_dumps_file_paths,@sort_field)
        mapping_pairs = process_sort_results(sorted_file_path)
        @logger.info("Mappings pairs found #{mapping_pairs.length}")
        onts_by_acronym = {}
        @ontologies.each do |ont|
          onts_by_acronym[ont.acronym] = ont
        end
        batch_triples = nil
        batch_triples_file = nil
        if mapping_pairs.length > 0
          ontologies_sorted = @ontologies.sort_by { |ont| ont.acronym }
          ont_acr_sorted = "#{ontologies_sorted[0].acronym}-#{ontologies_sorted[1].acronym}"
          ont_first = ontologies_sorted.first
          batch_triples = File.join([BatchProcess.mappings_ontology_folder(ont_first),
                                    "batch_triples-#{@process_name}-#{ont_acr_sorted}.nq"])
          batch_triples_file = File.open(batch_triples, 'w')
          @logger.info("Using batch file #{batch_triples}")
        end

        #file sort is of no use any more
        FileUtils.rm(sorted_file_path)

        mapping_pairs.each do |pair|
          id_t_a = LinkedData::Mappings.create_term_mapping([pair.record_a.term_id],
                                    pair.record_a.acronym, onts_by_acronym[pair.record_a.acronym],
                                                           batch_triples_file)
          id_t_b = LinkedData::Mappings.create_term_mapping([pair.record_b.term_id],
                                    pair.record_b.acronym, onts_by_acronym[pair.record_b.acronym],
                                                           batch_triples_file)
          mapping_id = LinkedData::Mappings.create_mapping([id_t_a, id_t_b],batch_triples_file)
          LinkedData::Mappings.connect_mapping_process(mapping_id, @process,
                                                      batch_triples_file)
        end
        if batch_triples_file
          batch_triples_file.close()
          @logger.info("Appending triples in batch ...")
          tt = Time.now
          begin
            #graphs are needed to invalidate the cache
            mapping_graphs = [LinkedData::Models::TermMapping.type_uri,
                             LinkedData::Models::Mapping.type_uri,
                             LinkedData::Models::MappingProcess.type_uri]
            if File.size(batch_triples) > 0
              Goo.sparql_data_client.append_triples_from_file(
                            mapping_graphs, batch_triples, "text/x-nquads")
            end
          rescue => e
            @logger.info("Error appending triples from #{batch_triples} error: #{e}")
          end
          @logger.info("Triples asserted in #{Time.now - tt} sec.")
        end
        @logger.info("Total batch process time #{Time.now - t0} sec.")
      end

      def process_sort_results(sorted_labels_file)
        record_a = nil
        record_b = nil
        tuples = []
        backlog = []
        t0 = Time.now
        @logger.info("process sort results ...")
        File.open(sorted_labels_file,"r").each do |line|
          if record_b && @ok_mapping.call(record_a,record_b)
            backlog << record_b
          else
            backlog = []
          end
          record_b = record_a
          record_a = @line_parser.call(line)
          if record_a && record_b
            next if @skip_mapping.call(record_a,record_b)
            if @ok_mapping.call(record_a,record_b)
              tuples << create_record_tuple(record_a,record_b)
              if backlog.length > 0
                backlog.each do |back_log_tuple|
                  tuples << create_record_tuple(record_a,back_log_tuple)
                end
              end
            end
          end
        end
        @logger.info("End process sort results in #{Time.now - t0} sec.")
        return tuples
      end

      def dumps()
        dump_paths = []
        @ontologies.each do |ont|
          ont.bring(submissions: [:submissionId])
          latest_submission = ont.latest_submission(status: [:rdf, :rdf_labels])
          dump_paths << create_ontology_dump(ont,@process_name,
                                            @paging,@dumper,logger=@logger)
        end
        return dump_paths
      end

      def sort(dump_files,field)
        ontologies_sorted = @ontologies.sort_by { |ont| ont.acronym }
        ont_first = ontologies_sorted.first
        sorted_file = File.join([BatchProcess.mappings_ontology_folder(ont_first),
                       "aggregated_#{@process_name}_labels_with_#{ontologies_sorted.last.acronym}.txt"])
        sort_command = "cat " + (dump_files.join " ") + "| sort -t, -k#{field}"
        if $TMP_SORT_FOLDER
          if not Dir.exist?($TMP_SORT_FOLDER)
            FileUtils.mkdir_p($TMP_SORT_FOLDER)
          end
          sort_command += " -T #{$TMP_SORT_FOLDER}"
        end
        sort_command += " > #{sorted_file}"
        @logger.info("sort_command: #{sort_command}")
        t0 = Time.now
        stdin, stdout, stderr, wait_thr = Open3.popen3(sort_command)
        unless wait_thr.value.success?
          @logger.error("error in sort command pid:#{wait_thr.pid}, exit code #{wait_thr.value}")
          @logger.error("error in sort command pid:#{wait_thr.pid}, err trace #{stderr.read}")
          @logger.error("error in sort command pid:#{wait_thr.pid}, out trace #{stdout.read}")
          raise Exception, "Error in sort command '#{sort_command}'"
        end
        @logger.info("sort success. run in #{Time.now - t0} sec.")
        return sorted_file
      end

      def create_ontology_dump(ont,proc_name,paging,dumper,logger=nil)
        ont.bring(submissions: [:submissionId])
        latest_submission = ont.latest_submission(status: [:rdf, :rdf_labels])
        dump_file_path = File.join([BatchProcess.mappings_ontology_folder(ont),
                       "#{proc_name}_dump_#{ont.acronym}_#{latest_submission.submissionId}.txt"])
        dump_file_lock = "#{dump_file_path}.lck"
        lock=false
        file_lock = File.open(dump_file_lock, File::RDWR|File::CREAT, 0644)
        begin
          while !lock
            lock = file_lock.flock(File::LOCK_NB|File::LOCK_EX)
            if !lock
              puts "locked on dumping #{ont.acronym} #{@proc_name}"
              sleep(5)
            end
          end
          if $MAPPING_RELOAD_LABELS || !File.exist?(dump_file_path)
              t0 = Time.now
              if logger
                logger.info("dumping labels in #{proc_name} for #{ont.acronym} ...")
              end
              page_i = 1
              page = nil
              entry_count = 0
              paging.in(latest_submission)
              paging.page(page_i,2500)
              CSV::open(dump_file_path,'wb') do |csv|
                begin
                  page = paging.all
                  page.each do |c|
                    dumper.call(c,ont).each do |entry|
                      csv << entry
                      entry_count += 1
                    end
                  end
                  page_i += 1
                  paging.page(page_i)
                end while(page.next?)
              end
              if logger
                logger.info("dumped #{entry_count} entries "+
                             " in #{Time.now - t0} sec.")
              end
          end
        ensure
          file_lock.close()
        end
        return dump_file_path
      end

      def finish()
        #place to detect deletes
      end

    end
  end
end

