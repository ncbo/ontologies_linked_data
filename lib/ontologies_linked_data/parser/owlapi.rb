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
      def initialize(input_file, output_repo, master_file=nil)
        @owlapi_wrapper_jar_path = "bin/owlapi_wrapper.jar"
        @input_file = input_file
        @output_repo = output_repo
        @master_file = master_file
        @file_triples_path = nil
      end
      
      def setup_environment
        if @output_repo.nil? or Utils::FileHelpers.exists_and_file(@output_repo)
          raise RepositoryFoldersError, "Outout repository folder are files in the system `#{@output_repo}`"
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
          rescue SystemCallError => e
            raise MkdirException, "Output folder #{@output_repo} folder cannot be created."  
          end
        end
      end

      def call_owlapi_java_command
        options = []
        if not @input_file.nil?
          if @master_file.nil?
            options << "-m #{@input_file}" #if no master file the input repo is a unique file.
          else
            options << "-i #{@input_file}"
          end
        end
        if not @master_file.nil?
          options << "-m #{@master_file}"
        end
        if not @output_repo.nil?
          options << "-o #{@output_repo}"
        end
        if options.length == 0
          raise ArgumentError, "Cannot call java OWLAPI command without options." 
        end
        options = options.join ' '
        command_call = "java -jar #{@owlapi_wrapper_jar_path} #{options}"
        Parser.logger.info("Java call [#{command_call}]")
        stdout,stderr,status = Open3.capture3(command_call)
        if not status.success?
          Parser.logger.error("OWLAPI java error in parse")
          Parser.logger.error(stderr)
          Parser.logger.error(stdout)
          raise Parser::OWLAPIParserException, "OWLAPI java command exited with #{status.exitstatus}. Check parser logs."
        else
          Parser.logger.info("OWLAPI java parse finished OK.")
          Parser.logger.info(stderr)
          Parser.logger.info(stdout)
        end
        if not File.exist?(File.join([@output_repo, "owlapi.xrdf"]))
          raise Parser::OWLAPIParserException, "OWLAPI java command exited with #{status.exitstatus}. " +\
          "Output file #{File.join([@output_repo, "owlapi.xrdf"])} cannot be found."
        else
          @file_triples_path = File.join([@output_repo, "owlapi.xrdf"])
          Parser.logger.info("Output size #{File.stat(@file_triples_path).size} in `#{@file_triples_path}`")
        end
        return @file_triples_path
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
        return @file_triples_path
      end
    end
  end
end
