# frozen_string_literal: true

require 'test_helper'

class ApplicationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Application.app
  end

  def test_home_page
    get '/'

    assert last_response.ok?
    assert_includes last_response.body, 'Sprite Sheet'
    assert_includes last_response.body, 'js/app.js'
    assert_equal 1, last_response.body.scan('name="image_files[]"').length
    assert_includes last_response.body, 'Clear image selection'
    refute_includes last_response.body, 'Add image row'
    refute_includes last_response.body, 'Remove image row'
    assert_includes last_response.body, 'enctype="multipart/form-data"'
    assert_includes last_response.body, 'data-controller="upload"'
    assert_includes last_response.body, 'css/app.css'
    refute_includes last_response.body, 'localhost:8080'
    refute_includes last_response.body, 'id="root"'
  end

  def test_upload_returns_zip_with_generated_image_and_css
    image = create_image('red.png', 'red')

    post '/', image_files: [Rack::Test::UploadedFile.new(image, 'image/png')]

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

  def test_ordered_array_upload_returns_a_zip
    red = create_image('red.png', 'red')
    blue = create_image('blue.png', 'blue')

    post '/', image_files: [Rack::Test::UploadedFile.new(red, 'image/png'), Rack::Test::UploadedFile.new(blue, 'image/png')]

    assert last_response.ok?, last_response.body

    Zip::File.open_buffer(last_response.body) do |zip|
      assert_includes zip.read('sprites.css'), '.sprite.sprite-2'
    end
  end

  def test_errors_preserve_escaped_options_and_archive_mode
    post '/', input_mode: 'archive', options: { columns: '2', class: 'icon', prefix: '\" onfocus=\"alert(1)' }
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'value="2"'
    assert_includes last_response.body, 'value="icon"'
    assert_includes last_response.body, '&quot;'
    assert_includes last_response.body, 'value="archive" checked'
    assert_includes last_response.body, 'Please select your files again.'
    refute_includes last_response.body, 'onfocus="alert'
  end

  def test_versioned_assets_are_served_locally
    get '/'

    html = last_response.body
    paths = html.scan(%r{(?:src|href)="(/(?:js|css)/[^" ]+)"}).flatten

    assert_equal 2, paths.length

    paths.each do |path|
      assert_match(/\?v=[0-9a-f]{12}\z/, path)

      get path

      assert last_response.ok?, path
    end

    get '/js/controllers/upload_controller.js'

    assert last_response.ok?

    get '/js/vendor/stimulus-3.2.2.js'

    assert last_response.ok?
  end
end
