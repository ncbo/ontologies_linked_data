require 'open3'
require 'shellwords'

module LinkedData
  module Parser
    class RepositoryFoldersError < Parser::ParserException
    end
    class InputFileNotFoundError < Parser::ParserException
    end
    class MasterFileMissingException < Parser::ParserException
    end
    class RDFFileNotGeneratedException < Parser::ParserException
    end
    class OWLAPITimeoutException < Parser::OWLAPIParserException
    end

    class OWLAPICommand
      def initialize(input_file, output_repo, opts = {})
        @owlapi_wrapper_jar_path = LinkedData.bindir + "/owlapi-wrapper-1.7.0.jar"
        @input_file = input_file
        @output_repo = output_repo
        @master_file = opts[:master_file]
        @logger = opts[:logger] || Parser.logger
        @file_triples_path = nil
        @missing_imports = nil
        @reasoning = true
        @java_heap_size = LinkedData.settings.java_max_heap_size
        @timeout = opts[:timeout] || LinkedData.settings.owlapi_parse_timeout
      end

      def setup_environment
        if @output_repo.nil? or Utils::FileHelpers.exists_and_file(@output_repo)
          raise RepositoryFoldersError, "Output repository folder are files in the system `#{@output_repo}`"
        end
        if @input_file.nil? or (not File.exist?(@input_file))
          raise InputFileNotFoundError, "#{@input_file} not found."
        end
        if @master_file.nil? and Utils::FileHelpers.zip?(@input_file)
          raise MasterFileMissingException , "Master file not provided and input is zipped archive."
        end
        if (not Dir.exist?(@output_repo))
          begin
            FileUtils.mkdir_p(@output_repo)
          rescue SystemCallError
            raise MkdirException, "Output folder #{@output_repo} folder cannot be created."
          end
        end
      end

      def disable_reasoner
        @reasoning = false
      end

      def call_owlapi_java_command
        options = []
        if not @input_file.nil?
          if @master_file.nil?
            options += ["-m", @input_file.to_s] #if no master file the input repo is a unique file.
          else
            options += ["-i", @input_file.to_s]
          end
        end
        if not @master_file.nil?
          options += ["-m", @master_file.to_s]
        end
        if not @output_repo.nil?
          options += ["-o", @output_repo.to_s]
        end
        options += ["-r", @reasoning ? "true" : "false"]

        errors_log = File.join([@output_repo, "errors.log"])
        if File.exist? errors_log
          File.delete errors_log
        end
        output_rdf = File.join([@output_repo, "owlapi.xrdf"])
        # An argument list runs java without a shell, so the pid we kill on
        # timeout is the JVM itself
        command = ["java", "-DentityExpansionLimit=2500000", "-Xmx#{@java_heap_size}",
                   "-jar", @owlapi_wrapper_jar_path, *options]
        command_call = Shellwords.join(command)
        @logger.info("Java call [#{command_call}]")
        Open3.popen3(*command) do |i, o, e, w|
          i.close
          # Drain both pipes at once; reading one to EOF first can block the
          # JVM on a full buffer of the other
          stdout_reader = Thread.new { o.read }
          stderr_reader = Thread.new { e.read }

          unless w.join(@timeout)
            begin
              Process.kill("KILL", w.pid)
            rescue Errno::ESRCH
              # exited between the timeout and the kill
            end
            w.join
            [stdout_reader, stderr_reader].each { |reader| reader.join(5) }
            # Whatever the killed run left behind is partial and must not be loaded
            FileUtils.rm_f(output_rdf)
            @logger.error("OWLAPI Java command: killed after #{@timeout} seconds.")
            @logger.error("cmd process: #{command_call}")
            @logger.flush
            raise OWLAPITimeoutException, "OWLAPI Java command did not finish within #{@timeout} seconds."
          end

          stdout = stdout_reader.value
          stderr = stderr_reader.value
          status = w.value

          if not status.success?
            @logger.error("OWLAPI Java command: parsing error occurred.")
            @logger.error("stderr: " + stderr)
            @logger.error("stdout: " + stdout)
            raise Parser::OWLAPIParserException, "OWLAPI Java command exited with status #{status.exitstatus}. Check parser log for details."
          end

          @logger.info(stdout)
          @logger.info("OWLAPI Java command: parsing finished successfully.")

          if not File.exist?(output_rdf)
            raise Parser::OWLAPIParserException, "OWLAPI java command exited with " +
            "#{status.exitstatus}. " + \
            "Output file #{output_rdf} cannot be found."
          else
            @file_triples_path = output_rdf
            @logger.info("Output size #{File.stat(@file_triples_path).size} in `#{@file_triples_path}`")
          end
        end
        @missing_imports = []
        if File.exist? errors_log
          ferrors = File.open(errors_log,"r")
          lines = ferrors.read().split("\n")
          lines.each_index do |i|
            if lines[i].include? "OWL_IMPORT_MISSING"
              @missing_imports << lines[i+1].gsub("Message: ","")
            end
          end
          ferrors.close()
        end
        return [@file_triples_path, @missing_imports]
      end

      def file_triples_path
        @file_triples_path
      end

      def parse
        setup_environment
        call_owlapi_java_command
        if @file_triples_path.nil?
          raise RDFFileNotGeneratedException, "Triple file nil"
        elsif not File.exist?(@file_triples_path)
          raise RDFFileNotGeneratedException, "Triple file not found in #{@file_triples_path}"
        end
        return @file_triples_path, @missing_imports
      end
    end
  end
end
