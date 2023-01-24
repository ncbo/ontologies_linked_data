require 'open3'

module LinkedData
  module Diff

    class RepositoryFoldersError < Diff::DiffException
    end
    class InputFileNotFoundError < Diff::DiffException
    end
    class DiffFileNotGeneratedException < Diff::DiffException
    end

    class BubastisDiffCommand < DiffTool

      # Bubastis version 1.2
      # 18th December 2014
      # ---
      #
      # Bubastis is an ontology change tool which is able to analyse two ontologies (typically two versions of the same ontology) to highlight logical changes which have occurred and to present these changes in more or less detail, as required.
      #
      #
      # Usage:
      # java -jar bubastis_1_2.jar parameters:
      # (required)  -ontology1 location of ontology 1 either a URL for an ontology on the web or a local file location in obo or owl format. Typically the older version of the ontologies being compared
      # (required)  -ontology2 location of ontology 2 either a URL or local file location of an obo or owl format ontology. Typically the newer version of the ontologies being compared.
      # (optional)  -output location of output file to send results, default is to console.
      # (optional)  -format required format of diff report, default is plain text, value 'xml' will produce xml
      # (optional)  -xslt for xml version of the diff report this will insert an xslt location into the header for rendering these in a customised manner in a web page. Value should be location of xslt file.
      #
      # Examples:
      # Loading two files locally and outputting results to console:
      # java -jar bubastis_1_2.jar -ontology1 "H://obi_nov_08.owl" -ontology2 "H://obi_jan_09.owl"
      #
      # Loading two files locally and output results to xml file with an xslt location inserted into header
      # java -jar bubastis_1_2.jar -1 "H://obi_nov_08.owl" -2 "H://obi_jan_09.owl" -output "H://OBIdiff.xml" -format xml -xslt "./stylesheets/bubastis.xslt"
      #
      # Loading one file locally and one from the web and outputting results to plain text:
      # java -jar bubastis_1_2.jar -ontology1 "H://disease_ontology_version_1.owl" -ontology2 "http://www.disease.org/diseaseontology_latest.owl" -output "C://my_diff.txt"

      def initialize(old_file_path, new_file_path)
        @bubastis_jar_path = LinkedData.bindir + "/bubastis.jar"
        @input_fileOld = old_file_path
        @input_fileNew = new_file_path
        @output_repo = File.expand_path(@input_fileNew).gsub(File.basename(@input_fileNew),'')
        @file_diff_path = nil
        @java_heap_size = LinkedData.settings.java_max_heap_size
      end


      def file_diff_path
        @file_diff_path
      end

      def diff
        setup_environment
        call_bubastis_java_cmd
        if @file_diff_path.nil?
          raise DiffFileNotGeneratedException, "Diff file nil"
        elsif not File.exist?(@file_diff_path)
          raise DiffFileNotGeneratedException, "Diff file not found in #{@file_diff_path}"
        end
        return @file_diff_path
      end

      private

      def setup_environment
        if @input_fileOld.nil? or (not File.exist?(@input_fileOld))
          raise InputFileNotFoundError, "#{@input_fileOld} not found."
        end
        if @input_fileNew.nil? or (not File.exist?(@input_fileNew))
          raise InputFileNotFoundError, "#{@input_fileNew} not found."
        end
        if @output_repo.nil? or Utils::FileHelpers.exists_and_file(@output_repo)
          raise RepositoryFoldersError, "Output repository folder are files in the system `#{@output_repo}`"
        end
        if (not Dir.exist?(@output_repo))
          begin
            FileUtils.mkdir_p(@output_repo)
          rescue SystemCallError => e
            raise MkdirException, "Output folder #{@output_repo} folder cannot be created."
          end
        end
      end

      def call_bubastis_java_cmd
        options = []
        if not @input_fileOld.nil?
          options << "-ontology1 #{Shellwords.escape(@input_fileOld)}"
        end
        if not @input_fileNew.nil?
          options << "-ontology2 #{Shellwords.escape(@input_fileNew)}"
        end
        if not @output_repo.nil?
          # Create output file in the repo for @input_fileNew.
          @file_diff_path = File.join(@output_repo, 'bubastis_diff.xml')
          options << "-output #{Shellwords.escape(@file_diff_path)} -format xml"
          # TODO: Add xslt link for better HTML display; requires reliable xslt file URI.
        end
        if options.length == 0
          raise ArgumentError, "Cannot call Bubastis diff command without options."
        end
        errors_log = File.join([@output_repo, "bubastis_diff_errors.log"])
        File.delete errors_log if File.exist? errors_log
        java_cmd = "java -DentityExpansionLimit=1500000 -Xmx#{@java_heap_size} -jar #{@bubastis_jar_path} #{options.join(' ')}"
        Diff.logger.info("Java call [#{java_cmd}]")
        stdout,stderr,status = Open3.capture3(java_cmd)
        if not status.success?
          Diff.logger.error("Bubastis diff error")
          Diff.logger.error(stderr)
          Diff.logger.error(stdout)
          raise Diff::BubastisDiffException, "Bubastis java command exited with #{status.exitstatus}. Check diff logs."
        else
          Diff.logger.info("Bubastis diff finished OK.")
          Diff.logger.info(stderr)
          Diff.logger.info(stdout)
        end
        if not File.exist?(@file_diff_path)
          raise Diff::BubastisDiffException, "Bubastis diff command exited with status=#{status.exitstatus}. " +\
          "Output file #{@file_diff_path} cannot be found."
        else
          Diff.logger.info("Output size #{File.stat(@file_diff_path).size} in `#{@file_diff_path}`")
        end
        return @file_diff_path
      end
    end
  end
end
