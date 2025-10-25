require 'net/http'
require 'uri'
require 'zip'
require 'zlib'
require 'tmpdir'
require 'fileutils'
require 'down/net_http'

module LinkedData
  module Utils
    module FileHelpers
      # --- Magic-byte detection helpers (avoid shelling out to `file`) ---
      MAGIC_ZIP  = "\x50\x4B\x03\x04".b # PK header. we do not support empty/spanned/SFX zip files
      MAGIC_GZIP = "\x1F\x8B".b

      def self.zip?(file_path)
        File.open(file_path, 'rb') { |f| f.read(4) } == MAGIC_ZIP
      rescue Errno::ENOENT, Errno::EISDIR
        false
      end

      def self.gzip?(file_path)
        base_name = File.basename(file_path).downcase
        # Exclude .tar.gz and .tgz files by filename extension (we don’t support tarballs yet).
        # Note: this is a filename-based check only — a misnamed tarball without these suffixes
        # will still pass the GZIP magic check and be treated as a single .gz payload.
        return false if base_name.end_with?('.tar.gz', '.tgz')

        File.open(file_path, 'rb') { |f| f.read(2) } == MAGIC_GZIP
      rescue Errno::ENOENT, Errno::EISDIR
        false
      end

      def self.filenames_in_archive(file_path)
        file_path = file_path.to_s
        raise ArgumentError, "File path #{file_path} not found" unless File.exist?(file_path)

        filenames = []
        if gzip?(file_path)
          Zlib::GzipReader.open(file_path) do |gzip_reader|
            filenames << resolve_gzip_name(file_path, gzip_reader)
          end
        elsif zip?(file_path)
          Zip::File.open(file_path) do |zip_file|
            zip_file.each do |entry|
              next if entry.directory?
              next if entry.symlink?
              next if macos_metadata?(entry.name)
              next if entry.name.split('/').last.start_with?('.')

              filenames << entry.name
            end
          end
        else
          raise StandardError, "Unsupported file format: #{File.extname(file_path)}"
        end
        filenames
      end

      def self.unzip(file_path, dst_directory)
        file_path = file_path.to_s
        dst_directory = dst_directory.to_s
        raise ArgumentError, "File path #{file_path} not found" unless File.exist?(file_path)
        raise ArgumentError, "Folder path #{dst_directory} not found" unless Dir.exist?(dst_directory)

        extracted_files = []

        if gzip?(file_path)
          Zlib::GzipReader.open(file_path) do |gzip_reader|
            name = resolve_gzip_name(file_path, gzip_reader)
            dest = safe_join(dst_directory, name)
            FileUtils.mkdir_p(File.dirname(dest))

            begin
              File.open(dest, 'wb') { |f| IO.copy_stream(gzip_reader, f) }
            rescue StandardError
              FileUtils.rm_f(dest) # remove partial file on any failure
              raise
            end

            extracted_files << dest
          end

        elsif zip?(file_path)
          Zip::File.open(file_path) do |zip_file|
            zip_file.each do |entry|
              next if entry.directory?
              next if entry.symlink?
              next if macos_metadata?(entry.name)
              next if entry.name.split('/').last.start_with?('.')

              dest = safe_join(dst_directory, entry.name)
              FileUtils.mkdir_p(File.dirname(dest))

              begin
                entry.get_input_stream do |input|
                  File.open(dest, 'wb') { |f| IO.copy_stream(input, f) }
                end
              rescue StandardError
                FileUtils.rm_f(dest) # clean up partial file on any error
                raise
              end

              extracted_files << dest
            end
          end

        else
          raise StandardError, "Unsupported file format: #{File.extname(file_path)}"
        end

        extracted_files
      end

      def self.zip_file(file_path)
        file_path = file_path.to_s
        return file_path if zip?(file_path)

        zip_file_path = "#{file_path}.zip"
        Zip::File.open(zip_file_path, create: true) do |zip_file|
          base = File.basename(file_path)
          zip_file.add(base, file_path) unless zip_file.find_entry(base)
        end
        zip_file_path
      end

      def self.automaster?(path, format)
        automaster(path, format) != nil
      end

      def self.automaster(path, format)
        filenames = filenames_in_archive(path)
        basename = File.basename(path, '.zip')
        basename = File.basename(basename, format)
        filenames.find { |f| File.basename(f, format).casecmp?(basename) }
      end

      def self.repeated_names_in_file_list(file_list)
        file_list.group_by { |x| x.split('/').last }.select { |_k, v| v.length > 1 }
      end

      def self.exists_and_file(path)
        path = path.to_s
        File.exist?(path) && !File.directory?(path)
      end

      def self.download_file(uri, limit: 10, open_timeout: 15, read_timeout: 1800, headers: {}, max_size: 512 * 1024 * 1024)
        uri = URI(uri) unless uri.is_a?(URI)
        unless %w[http https].include?(uri.scheme)
          raise ArgumentError, "Unsupported URI scheme #{uri.scheme.inspect} (only http/https are supported)"
        end

        tmpfile = Down::NetHttp.download(
          uri.to_s,
          max_redirects: limit,
          open_timeout: open_timeout,
          read_timeout: read_timeout,
          max_size: max_size,
          headers: { "User-Agent" => "OntoPortal" }.merge(headers)
        )

        filename = tmpfile.original_filename ||
                   File.basename(uri.path.to_s) ||
                   LinkedData::Utils::Triples.last_iri_fragment(uri.request_uri)
        filename = sanitize_filename(filename)
        tmpfile.rewind

        [tmpfile, filename]
      end

      # --- Utility guards / filters ---
      def self.safe_join(base, *paths)
        target = File.expand_path(File.join(base, *paths))
        base_expanded = File.expand_path(base)
        prefix = (base_expanded == File::SEPARATOR) ? File::SEPARATOR : (base_expanded + File::SEPARATOR)
        raise SecurityError, "Path traversal: #{target}" unless target == base_expanded || target.start_with?(prefix)

        target
      end

      def self.macos_metadata?(entry_name)
        base = entry_name.split('/').last
        entry_name.start_with?('__MACOSX/') || base == '.DS_Store' || base.start_with?('._')
      end

      def self.sanitize_filename(name)
        base = File.basename(name.to_s)
        base = base.gsub(/[\x00-\x1F\/\\:\*\?\"<>\|]/, "")  # control + unsafe chars
        base = base.sub(/\A\.+/, "")                        # no leading dots
        base = base.strip.gsub(/\s+/, " ")                  # trim + collapse spaces
        base = base[0, 255]
        base.empty? ? "unnamed" : base
      end

      # Resolve the output filename for a .gz:
      # - Prefer header's orig_name when present
      # - Otherwise use the source filename without its .gz
      # - Always collapse to a basename (strip any embedded path)
      # - Sanitize odd header bytes and control chars
      def self.resolve_gzip_name(file_path, gzip_reader)
        name = gzip_reader.orig_name
        name = File.basename(file_path, File.extname(file_path)) if name.nil? || name.empty?
        name = File.basename(name.to_s)
        sanitize_filename(name)
      end

    end
  end
end
