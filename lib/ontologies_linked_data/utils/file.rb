require 'zip/zipfilesystem'

module LinkedData
  module Utils
    module FileHelpers

      def self.zip?(file_path)
        unless File.exist? file_path
          raise ArgumentError, "File path #{file_path} not found"
        end
        file_type = `file --mime -b #{file_path}`
        return file_type.split(";")[0] == "application/zip"
      end

      def self.files_from_zip(file_path)
          unless File.exist? file_path
            raise ArgumentError, "File path #{file_path} not found"
          end
          files = []
          Zip::ZipFile.open(file_path) do |zipfile|
            zipfile.each do |file|
              if not file.is_directory()
                if not file.name.split("/")[-1].start_with? "." #a hidden file in __MACOSX or .DS_Store
                  files << file.name
                end
              end
            end
          end
          return files
      end

      def self.unzip(file_path, dst_folder)
          unless File.exist? file_path
            raise ArgumentError, "File path #{file_path} not found"
          end
          unless Dir.exist? dst_folder
            raise ArgumentError, "Folder path #{dst_folder} not found"
          end
          extracted_files = []
          Zip::ZipFile.open(file_path) do |zipfile|
            zipfile.each do |file|
              extracted_files << file.extract(File.join(dst_folder,file.name))
            end
          end
          return extracted_files
      end

      def self.repeated_names_in_file_list(file_list)
        return file_list.group_by {|x| x.split("/")[-1]}.select { |k,v| v.length > 1}
      end

      def self.exists_and_file(path)
        return (File.exist?(path) and (not File.directory?(path)))
      end
    end
  end
end
