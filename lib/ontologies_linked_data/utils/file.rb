require 'net/http'
require 'uri'
require 'zip'
require 'zlib'
require 'tmpdir'

module LinkedData
  module Utils
    module FileHelpers
      
      class GzipFile
        attr_accessor :name
        def initialize(gz)
          self.name = gz.orig_name
        end
      end


      def self.zip?(file_path)
        file_path = file_path.to_s
        raise ArgumentError, "File path #{file_path} not found" unless File.exist? file_path

        file_type = `file --mime -b #{Shellwords.escape(file_path)}`
        file_type.split(';')[0] == 'application/zip'
      end

      def self.gzip?(file_path)
        file_path = file_path.to_s
        raise ArgumentError, "File path #{file_path} not found" unless File.exist? file_path

        file_type = `file --mime -b #{Shellwords.escape(file_path)}`
        file_type.split(';')[0] == 'application/gzip' || file_type.split(';')[0] == 'application/x-gzip'
      end

      def self.files_from_zip(file_path)
        file_path = file_path.to_s
        unless File.exist? file_path
          raise ArgumentError, "File path #{file_path} not found"
        end

        files = []
        if gzip?(file_path)
          Zlib::GzipReader.open(file_path) do |file|
            files << file.orig_name unless File.directory?(file) || file.orig_name.split('/')[-1].start_with?('.') # a hidden file in __MACOSX or .DS_Store
          end
        elsif zip?(file_path)
          Zip::File.open(file_path) do |zip_files|
            zip_files.each do |file|
              unless file.directory? || file.name.split('/')[-1].start_with?('.') # a hidden file in __MACOSX or .DS_Store
                files << file.name
              end
            end
          end
        else
          raise StandardError, "Unsupported file format: #{File.extname(file_path)}"
        end

        return files
      end

      def self.unzip(file_path, dst_folder)
        file_path = file_path.to_s
        dst_folder = dst_folder.to_s
        raise ArgumentError, "File path #{file_path} not found" unless File.exist? file_path
        raise ArgumentError, "Folder path #{dst_folder} not found" unless Dir.exist? dst_folder

        extracted_files = []
        if gzip?(file_path)
          Zlib::GzipReader.open(file_path) do |gz|
            File.open([dst_folder, gz.orig_name].join('/'), "w") { |file| file.puts(gz.read) }
            extracted_files << gz
          end
        elsif zip?(file_path)
          Zip::File.open(file_path) do |zipfile|
            zipfile.each do |file|
              if file.name.split('/').length > 1
                sub_folder = File.join(dst_folder, file.name.split('/')[0..-2].join('/'))
                FileUtils.mkdir_p sub_folder unless Dir.exist?(sub_folder)
              end
              extracted_files << file.extract(File.join(dst_folder, file.name))
            end
          end
        else
          raise StandardError, "Unsupported file format: #{File.extname(file_path)}"
        end
        extracted_files
      end

      def self.zip_file(file_path)
        return file_path if self.zip?(file_path)

        zip_file_path = "#{file_path}.zip"
        Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
          # Add the file to the zip
          begin
            zipfile.add(File.basename(file_path), file_path)
          rescue Zip::EntryExistsError
          end

        end
        zip_file_path
      end

      def self.automaster?(path, format)
        self.automaster(path, format) != nil
      end

      def self.automaster(path, format)
        files = self.files_from_zip(path)
        basename = File.basename(path, '.zip')
        basename = File.basename(basename, format)
        files.select {|f| File.basename(f, format).downcase.eql?(basename.downcase)}.first
      end

      def self.repeated_names_in_file_list(file_list)
        return file_list.group_by {|x| x.split('/')[-1]}.select { |k,v| v.length > 1}
      end

      def self.exists_and_file(path)
        path = path.to_s
        return (File.exist?(path) and (not File.directory?(path)))
      end

      def self.download_file(uri, limit = 10)
        raise ArgumentError, 'HTTP redirect too deep' if limit == 0

        uri = URI(uri) unless uri.kind_of?(URI)

        if uri.kind_of?(URI::FTP)
          file, filename = download_file_ftp(uri)
        else
          file = Tempfile.new('ont-rest-file')
          file_size = 0
          filename = nil
          http_session = Net::HTTP.new(uri.host, uri.port)
          http_session.verify_mode = OpenSSL::SSL::VERIFY_NONE
          http_session.use_ssl = (uri.scheme == 'https')
          http_session.start do |http|
            http.read_timeout = 1800
            http.request_get(uri.request_uri, {'Accept-Encoding' => 'gzip'}) do |res|
              if res.kind_of?(Net::HTTPRedirection)
                new_loc = res['location']
                if new_loc.match(/^(http:\/\/|https:\/\/)/)
                  uri = new_loc
                else
                  uri.path = new_loc
                end
                return download_file(uri, limit - 1)
              end

              raise Net::HTTPBadResponse.new("#{uri.request_uri}: #{res.code}") if res.code.to_i >= 400

              file_size = res.read_header['content-length'].to_i
              begin
                content_disposition = res.read_header['content-disposition']
                filenames = content_disposition.match(/filename=\"(.*)\"/) || content_disposition.match(/filename=(.*)/)
                filename = filenames[1] if filename.nil?
              rescue
                filename = LinkedData::Utils::Triples.last_iri_fragment(uri.request_uri) if filename.nil?
              end

              file.write(res.body)

              if res.header['Content-Encoding'].eql?('gzip')
                uncompressed_file = Tempfile.new('uncompressed-ont-rest-file')
                file.rewind
                sio = StringIO.new(file.read)
                gz = Zlib::GzipReader.new(sio)
                uncompressed_file.write(gz.read())
                file.close
                file = uncompressed_file
                gz.close()
              end
            end
          end
          file.close
        end

        return file, filename
      end

      def self.download_file_ftp(url)
        url = URI.parse(url) unless url.kind_of?(URI)
        ftp = Net::FTP.new(url.host, url.user, url.password)
        ftp.passive = true
        ftp.login
        filename = LinkedData::Utils::Triples.last_iri_fragment(url.path)
        temp_dir = Dir.tmpdir
        temp_file_path = File.join(temp_dir, filename)
        ftp.getbinaryfile(url.path, temp_file_path)
        file = File.new(temp_file_path)
        return file, filename
      end

    end
  end
end
