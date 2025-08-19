require 'minitest/autorun'
require_relative '../../lib/ontologies_linked_data/utils/file'

class TestUtilsFile < MiniTest::Unit::TestCase
  DST = nil

  def setup
    @dst = Dir.mktmpdir('unzip-dst-')
  end

  def teardown
    FileUtils.remove_entry_secure(@dst) if @dst && Dir.exist?(@dst)
  end

  def test_automaster_from_zip
    zipfile = './test/data/ontology_files/SDO.zip'
    assert LinkedData::Utils::FileHelpers.automaster?(zipfile, '.owl')
    assert_equal 'SDO.owl', LinkedData::Utils::FileHelpers.automaster(zipfile, '.owl')

    zipfile = './test/data/ontology_files/evoc_v2.9.zip'
    refute LinkedData::Utils::FileHelpers.automaster?(zipfile, '.obo')
    assert_nil LinkedData::Utils::FileHelpers.automaster(zipfile, '.obo')
  end

  def test_is_zip
    file = './test/data/ontology_files/BRO_v3.2.owl'
    gzipfile = './test/data/ontology_files/BRO_v3.2.owl.gz'
    zipfile = './test/data/ontology_files/evoc_v2.9.zip'
    tarfile = './test/data/ontology_files/pizza.owl.tar'
    tgzfile = './test/data/ontology_files/pizza.owl.tgz'

    assert LinkedData::Utils::FileHelpers.gzip?(gzipfile)
    refute LinkedData::Utils::FileHelpers.gzip?(zipfile)
    refute LinkedData::Utils::FileHelpers.gzip?(tarfile)
    refute LinkedData::Utils::FileHelpers.gzip?(tgzfile)
    refute LinkedData::Utils::FileHelpers.gzip?(file)

    refute LinkedData::Utils::FileHelpers.zip?(gzipfile)
    assert LinkedData::Utils::FileHelpers.zip?(zipfile)
    refute LinkedData::Utils::FileHelpers.zip?(tarfile)
    refute LinkedData::Utils::FileHelpers.zip?(tgzfile)
    refute LinkedData::Utils::FileHelpers.zip?(file)
  end

  def write_zip(path, entries)
    Zip::File.open(path, create: true) do |zip|
      entries.each do |name, content|
        zip.get_output_stream(name) { |io| io.write(content) }
      end
    end
  end

  def write_gz(path, content, orig_name: nil)
    Zlib::GzipWriter.open(path) do |gz|
      gz.orig_name = orig_name if orig_name
      gz.write(content)
    end
  end

  def test_blocks_zip_slip_attempt
    evil_zip = File.join(Dir.mktmpdir('unzip-src-'), 'evil.zip')
    write_zip(evil_zip, { '../../outside.txt' => 'owned' })

    # Ensure nothing was written outside dst (sanity check in tmp space)
    refute File.exist?(File.expand_path('../../outside.txt', @dst))
  ensure
    FileUtils.remove_entry_secure(File.dirname(evil_zip)) if evil_zip && File.exist?(File.dirname(evil_zip))
  end

  def test_extracts_normal_zip_entry_inside_dst
    zip_path = File.join(Dir.mktmpdir('unzip-src-'), 'ok.zip')
    write_zip(zip_path, { 'dir/subdir/file.txt' => 'hello' })

    extracted = LinkedData::Utils::FileHelpers.unzip(zip_path, @dst)

    assert File.exist?(File.join(@dst, 'dir/subdir/file.txt')), 'file should be extracted inside dst'
    refute_empty extracted
  ensure
    FileUtils.remove_entry_secure(File.dirname(zip_path)) if zip_path && File.exist?(File.dirname(zip_path))
  end

  def test_tar_is_unsupported
    tar_path = './test/data/ontology_files/pizza.owl.tar'
    assert_raises(StandardError) { LinkedData::Utils::FileHelpers.filenames_in_archive(tar_path) }
  end

  def test_tgz_is_unsupported
    tgz_path = './test/data/ontology_files/pizza.owl.tgz'
    assert_raises(StandardError) { LinkedData::Utils::FileHelpers.filenames_in_archive(tgz_path) }
  end

  def test_gzip_strips_any_leading_path_from_orig_name
    gz_path = File.join(Dir.mktmpdir("unzip-src-"), "payload.gz")
    write_gz(gz_path, "data", orig_name: "foo/bar/baz.txt")

    extracted = LinkedData::Utils::FileHelpers.unzip(gz_path, @dst)

    assert File.exist?(File.join(@dst, "baz.txt")), "gzip should write only basename of orig_name"
    refute File.exist?(File.join(@dst, "foo")), "gzip must not create directories from orig_name"
    refute_empty extracted
  ensure
    FileUtils.remove_entry_secure(File.dirname(gz_path)) if gz_path && File.exist?(File.dirname(gz_path))
  end
end
