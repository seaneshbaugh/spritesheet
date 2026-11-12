# frozen_string_literal: true

require 'test_helper'

class ApplicationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Application::Main
  end

  def test_home_page
    get '/'

    assert last_response.ok?
    assert_includes last_response.body, 'Sprite Sheet'
    assert_includes last_response.body, 'js/app.js'
  end

  def test_upload_returns_zip_with_generated_image_and_css
    image = create_image('red.png', 'red')

    post '/', image_files: { 'first' => Rack::Test::UploadedFile.new(image, 'image/png') }

    assert last_response.ok?, last_response.body
    assert_includes last_response.headers['content-disposition'], 'spritesheet.zip'

    Zip::File.open_buffer(last_response.body) do |zip|
      assert_equal %w[sprites.png sprites.css], zip.entries.map(&:name)
      assert_includes zip.read('sprites.css'), '.sprite.sprite-1'

      png = File.join(@directory, 'result.png')

      File.binwrite(png, zip.read('sprites.png'))

      assert_equal [4, 3], MiniMagick::Image.open(png).dimensions
    end
  end

  def test_archive_upload_returns_generated_zip
    image = create_image('red.png', 'red')

    archive = File.join(@directory, 'images.zip')

    ArchiveCreator.new(image).save(archive)

    post '/', archive_file: Rack::Test::UploadedFile.new(archive, 'application/zip')

    assert last_response.ok?, last_response.body

    Zip::File.open_buffer(last_response.body) do |zip|
      assert_equal %w[sprites.png sprites.css], zip.entries.map(&:name)
      assert_includes zip.read('sprites.css'), '.sprite.sprite-1'
    end
  end
end
