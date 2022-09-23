require 'open3'

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

    class OWLAPICommand
      def initialize(input_file, output_repo, opts = {})
        @owlapi_wrapper_jar_path = LinkedData.bindir + "/owlapi-wrapper.jar"
        @input_file = input_file
        @output_repo = output_repo
        @master_file = opts[:master_file]
        @logger = opts[:logger] || Parser.logger
        @file_triples_path = nil
        @missing_imports = nil
        @reasoning = true
        @java_heap_size = LinkedData.settings.java_max_heap_size
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
            options << "-m #{Shellwords.escape(@input_file.to_s)}" #if no master file the input repo is a unique file.
          else
            options << "-i #{Shellwords.escape(@input_file.to_s)}"
          end
        end
        if not @master_file.nil?
          options << "-m #{Shellwords.escape(@master_file.to_s)}"
        end
        if not @output_repo.nil?
          options << "-o #{Shellwords.escape(@output_repo.to_s)}"
        end
        options << "-r #{@reasoning ? "true" : "false"}"

        if options.length == 0
          raise ArgumentError, "Cannot call OWLAPI Java command without options."
        end
        options = options.join ' '
        errors_log = File.join([@output_repo, "errors.log"])
        if File.exist? errors_log
          File.delete errors_log
        end
        command_call = "java -DentityExpansionLimit=2500000 -Xmx#{@java_heap_size} -jar #{@owlapi_wrapper_jar_path} #{options}"
        @logger.info("Java call [#{command_call}]")
        Open3.popen3(command_call) do |i,o,e,w|
          i.close

          begin
            Timeout.timeout(60 * 40) do #20 minutes
              buffer = []
              stdout = ""
              stderr = ""

              read_array = [o, e]
              loop do
                ready_to_read = IO.select(read_array)

                if ready_to_read[0].include? o
                  o.each_line do |line|
                    buffer << line
                  end
                  stdout = buffer.join "\n"
                  read_array.delete(o)
                end

                if ready_to_read[0].include? e
                  e.each_line do |line|
                    buffer << line
                  end
                  stderr = buffer.join "\n"
                  read_array.delete(e)
                end

                break if read_array.empty?
              end
              
              if not w.value.success?
                @logger.error("OWLAPI Java command: parsing error occurred.")
                @logger.error("stderr: " + stderr)
                @logger.error("stdout: " + stdout)
                raise Parser::OWLAPIParserException, "OWLAPI Java command exited with status #{w.value.exitstatus}. Check parser log for details."
              else
                @logger.info(stdout)
                @logger.info("OWLAPI Java command: parsing finished successfully.")
              end

            end
          rescue Timeout::Error
            Process.kill("KILL", w.pid)
            @logger.error("OWLAPI Java command: killed due to timeout.")
            @logger.error("cmd process: #{command_call}")
          end
          if not File.exist?(File.join([@output_repo, "owlapi.xrdf"]))
            raise Parser::OWLAPIParserException, "OWLAPI java command exited with"+
            "  #{w.value.exitstatus}. " +\
            "Output file #{File.join([@output_repo, "owlapi.xrdf"])} cannot be found."
          else
            @file_triples_path = File.join([@output_repo, "owlapi.xrdf"])
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
