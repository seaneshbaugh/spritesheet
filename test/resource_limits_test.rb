# frozen_string_literal: true

require 'test_helper'

class ResourceLimitsTest < Minitest::Test
  def archive(entries)
    path = File.join(@directory, 'input.zip')

    Zip::OutputStream.open(path) do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)

        zip.write(content)
      end
    end

    path
  end

  def extract(entries, **limits)
    ArchiveExtractor.new(archive(entries), limits: ProcessingLimits.new(**limits))
                    .extract_to(File.join(@directory, 'extracted'))
  end

  def test_direct_image_byte_boundary_without_large_fixtures
    image = create_image('image.png', 'red')
    tempfile = File.open(image)
    params = { image_files: [{ filename: 'image.png', tempfile: tempfile }] }
    bytes = File.size(image)

    assert UploadRequest.new(params, limits: ProcessingLimits.new(image_bytes: bytes))

    assert_raises(ValidationError) do
      UploadRequest.new(params, limits: ProcessingLimits.new(image_bytes: bytes - 1))
    end
  ensure
    tempfile&.close
  end

  def test_default_32_mib_boundary_uses_sparse_files
    image = File.join(@directory, 'image.png')

    File.open(image, 'wb') { |file| file.truncate(32 * 1024 * 1024) }

    File.open(image) do |file|
      params = { image_files: [{ filename: 'image.png', tempfile: file }] }

      assert UploadRequest.new(params)

      File.truncate(image, (32 * 1024 * 1024) + 1)

      assert_raises(ValidationError) { UploadRequest.new(params) }
    end
  end

  def test_archive_actual_image_bytes_at_and_over_limit
    entries = { 'one.png' => 'a' * 32, 'two.gif' => 'b' * 32 }

    assert_equal 2, extract(entries, image_bytes: 64).length

    FileUtils.rm_rf(File.join(@directory, 'extracted'))

    assert_raises(ValidationError) { extract(entries, image_bytes: 63) }
  end

  def test_irrelevant_files_and_metadata_count_toward_expansion
    assert_raises(ValidationError) { extract({ '__MACOSX/file' => 'a' * 65 }, extraction_bytes: 64) }

    FileUtils.rm_rf(File.join(@directory, 'extracted'))

    assert_raises(ValidationError) { extract({ 'notes.txt' => 'a' * 65 }, extraction_bytes: 64) }
  end

  def test_forged_uncompressed_size_does_not_bypass_expansion_limit
    path = archive({ 'image.png' => 'x' * 4096 })
    bytes = File.binread(path)

    # Lie about expanded size in local and central headers; actual decompressed
    # bytes, or rubyzip's own integrity check, must still reject this archive.
    [bytes.index("PK\x03\x04") + 22, bytes.index("PK\x01\x02") + 24].each do |offset|
      bytes[offset, 4] = [1].pack('V')
    end

    File.binwrite(path, bytes)

    extractor = ArchiveExtractor.new(path, limits: ProcessingLimits.new(extraction_bytes: 64))

    assert_raises(ValidationError) { extractor.extract_to(File.join(@directory, 'extracted')) }
  end

  def test_entry_count_includes_directories
    assert_raises(ValidationError) { extract({ 'one/' => '', 'two/' => '' }, archive_entries: 1) }
  end

  def test_traversal_absolute_backslash_and_duplicate_paths
    ['../outside.png', '/outside.png', 'C:/outside.png', 'a/../outside.png', '..\\outside.png'].each do |name|
      placeholder = 'x' * name.bytesize
      path = archive({ placeholder => 'bad' })

      File.binwrite(path, File.binread(path).gsub(placeholder, name))

      assert_raises(ValidationError, name) do
        ArchiveExtractor.new(path).extract_to(File.join(@directory, 'extracted'))
      end

      FileUtils.rm_rf(File.join(@directory, 'extracted'))
    end

    assert_raises(ValidationError) { extract({ 'a' => 'file', 'a/b.png' => 'bad' }) }
  end

  def test_duplicate_entries_and_symlinks_are_rejected
    path = File.join(@directory, 'duplicate.zip')

    Zip::OutputStream.open(path) do |zip|
      %w[same.png temp.png].each { |name| zip.put_next_entry(name); zip.write('bad') }
    end

    File.binwrite(path, File.binread(path).gsub('temp.png', 'same.png'))

    assert_raises(ValidationError) { ArchiveExtractor.new(path).extract_to(File.join(@directory, 'duplicates')) }

    link = File.join(@directory, 'link.png')

    File.symlink('/etc/passwd', link)

    path = File.join(@directory, 'symlink.zip')

    Zip::File.open(path, create: true) { |zip| zip.add('link.png', link) }

    assert_raises(ValidationError) { ArchiveExtractor.new(path).extract_to(File.join(@directory, 'links')) }
  end

  def test_preexisting_extraction_symlink_is_not_followed
    destination = File.join(@directory, 'extracted')

    Dir.mkdir(destination)

    File.symlink(@directory, File.join(destination, 'escape'))

    assert_raises(ValidationError) { extract({ 'escape/out.png' => 'bad' }) }
    refute File.exist?(File.join(@directory, 'out.png'))
  end

  def test_container_policy_rejects_unsupported_coders_even_with_png_filename
    path = File.join(@directory, 'disguised.png')

    File.write(path, '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><rect width="1" height="1"/></svg>')

    assert_raises(MiniMagick::Error) do
      ImageTools.run(:identify, directory: @directory) { |command| command << path }
    end
  end

  def test_image_and_canvas_pixel_bounds_precede_montage
    image = create_image('image.png', 'red')

    assert Spritesheet.new([image], limits: ProcessingLimits.new(image_pixels: 12, canvas_pixels: 12))
    assert_raises(ValidationError) { Spritesheet.new([image], limits: ProcessingLimits.new(image_pixels: 11)) }
    assert_raises(ValidationError) { Spritesheet.new([image, image], limits: ProcessingLimits.new(canvas_pixels: 23)) }
    assert_raises(ValidationError) { Spritesheet.new([image], limits: ProcessingLimits.new(dimension: 3)) }
  end
end
