# frozen_string_literal: true

require 'test_helper'

class InputValidationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    @error_app || Application::Main
  end

  def uploaded(path)
    Rack::Test::UploadedFile.new(path, 'application/octet-stream')
  end

  def assert_invalid(params, message)
    post '/', params

    assert_equal 422, last_response.status, last_response.body
    assert_includes last_response.body, message
    refute_includes last_response.body, '/tmp/'
  end

  def zip_with(entries)
    path = File.join(@directory, 'images.zip')

    Zip::OutputStream.open(path) do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end
    path
  end

  def test_missing_and_malformed_inputs
    assert_invalid({}, 'No file(s) selected.')
    assert_invalid({ archive_file: 'not a file' }, 'Invalid file upload.')
    assert_invalid({ image_files: 'not a collection' }, 'collection of uploads')
    assert_invalid({ image_files: { first: 'not a file' } }, 'Invalid file upload.')
    assert_invalid({ archive_file: { filename: 'images.zip' } }, 'Invalid file upload.')
  end

  def test_conflicting_uploads
    image = create_image('red.png', 'red')
    archive = zip_with('red.png' => File.binread(image))

    assert_invalid({ archive_file: uploaded(archive), image_files: { first: uploaded(image) } }, 'not both')
  end

  def test_invalid_options
    image = create_image('red.png', 'red')

    assert_invalid({ image_files: { first: uploaded(image) }, options: 'wrong' }, 'Options')

    [{ columns: ['2'] }, { unexpected: 'value' }].each do |options|
      assert_invalid({ image_files: { first: uploaded(image) }, options: options }, 'Invalid spritesheet options.')
    end
  end

  def test_unsupported_and_corrupt_images
    corrupt = File.join(@directory, 'bad.png')

    File.write(corrupt, 'not an image')

    assert_invalid({ image_files: { first: uploaded(corrupt) } }, 'Invalid image data')

    other = File.join(@directory, 'image.jpg')

    FileUtils.cp(create_image('red.png', 'red'), other)

    assert_invalid({ image_files: { first: uploaded(other) } }, 'Only PNG and static GIF')

    disguised = File.join(@directory, 'disguised.png')

    FileUtils.cp(create_image('red.gif', 'red'), disguised)

    assert_invalid({ image_files: { first: uploaded(disguised) } }, 'must match')
  end

  def test_empty_invalid_and_unsupported_archives
    assert_invalid({ archive_file: uploaded(zip_with({})) }, 'No supported images')
    assert_invalid({ archive_file: uploaded(zip_with('README.txt' => 'hello')) }, 'No supported images')
    assert_invalid({ archive_file: uploaded(zip_with('bad.png' => 'broken')) }, 'Invalid image data')

    corrupt = File.join(@directory, 'corrupt.zip')

    File.write(corrupt, 'broken zip')

    assert_invalid({ archive_file: uploaded(corrupt) }, 'ZIP archive is invalid')

    wrong = File.join(@directory, 'images.tar')

    File.write(wrong, 'not a zip')

    assert_invalid({ archive_file: uploaded(wrong) }, 'Select a ZIP archive.')
  end

  def test_encrypted_archive_is_rejected_before_extraction
    image = create_image('red.png', 'red')

    archive = zip_with('red.png' => File.binread(image))

    bytes = File.binread(archive)

    # Set the encryption flag in both ZIP headers without requiring a password tool.
    [bytes.index("PK\x03\x04") + 6, bytes.index("PK\x01\x02") + 8].each do |offset|
      flags = bytes.byteslice(offset, 2).unpack1('v')
      bytes[offset, 2] = [flags | 1].pack('v')
    end

    File.binwrite(archive, bytes)

    assert_invalid({ archive_file: uploaded(archive) }, 'Encrypted ZIP archives')
  end

  def test_invalid_columns_and_css_names_return_422
    image = create_image('red.png', 'red')

    assert_invalid({ image_files: { first: uploaded(image) }, options: { columns: '-1' } }, 'positive whole number')
    assert_invalid({ image_files: { first: uploaded(image) }, options: { class: '<script>' } }, 'valid CSS identifier')
  end

  def test_blank_options_use_defaults_and_prefix_follows_class
    image = create_image('red.png', 'red')

    post '/', image_files: { first: uploaded(image) }, options: { columns: ' ', class: ' icon ', prefix: '' }

    assert_equal 200, last_response.status

    Zip::File.open_buffer(last_response.body) do |zip|
      assert_includes zip.read('sprites.css'), '.icon.icon-1'
    end
  end

  def test_archive_filters_metadata_and_nonimages_and_preserves_order
    red = create_image('red.png', 'red')
    blue = create_image('blue.png', 'blue')
    archive = zip_with('nested/' => '', 'nested/z.PNG' => File.binread(blue),
                       'README.txt' => 'hello', '__MACOSX/bad.png' => 'broken',
                       'a.png' => File.binread(red))

    post '/', archive_file: uploaded(archive), options: { columns: '2', class: 'icon', prefix: 'tile' }

    assert_equal 200, last_response.status, last_response.body
    assert_equal 'application/zip', last_response.media_type

    Zip::File.open_buffer(last_response.body) do |zip|
      css = zip.read('sprites.css')

      assert_includes css, 'url(sprites.png)'
      assert_includes css, '.icon.tile-2'

      path = File.join(@directory, 'result.png')

      File.binwrite(path, zip.read('sprites.png'))

      assert_equal [8, 3], MiniMagick::Image.new(path).dimensions
      assert_equal 'srgb(0,0,255)', MiniMagick::Image.new(path)['%[pixel:p{0,0}]']
      assert_equal 'srgb(255,0,0)', MiniMagick::Image.new(path)['%[pixel:p{4,0}]']
    end
  end

  def test_unsupported_archive_error_is_escaped_in_erb
    # Exercise the error handler with a user-controlled extension; extraction
    # errors may also be raised independently of the HTTP request parser.
    @error_app = Class.new(Application::Main) do
      get '/test-archive-error' do
        raise ArchiveExtractor::UnsupportedArchiveFormatError, '<script>alert(1)</script>'
      end
    end

    get '/test-archive-error'

    assert_equal 422, last_response.status
    assert_includes last_response.body, '&lt;script&gt;'
    refute_includes last_response.body, '<script>alert(1)</script>'
  end
end
