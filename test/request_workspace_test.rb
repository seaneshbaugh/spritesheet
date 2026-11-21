# frozen_string_literal: true

require 'test_helper'
require 'rack/mock'

class RequestWorkspaceTest < Minitest::Test
  def env(body = '')
    Rack::MockRequest.env_for('/', method: 'POST', input: body)
  end

  def middleware(app)
    RequestWorkspace.new(app, root: @directory)
  end

  def consume(response)
    response[2].each { |chunk| assert_kind_of String, chunk }
  ensure
    response[2].close if response[2].respond_to?(:close)
  end

  def test_other_requests_bypass_workspace_handling
    [%w[GET /], %w[HEAD /], %w[GET /js/app.js], %w[POST /missing], %w[PUT /]].each do |method, path|
      request = Rack::MockRequest.env_for(path, method: method, input: 'untouched')
      original_input = request['rack.input']
      original_factory = ->(*) { flunk 'Unused multipart factory' }
      request['rack.multipart.tempfile_factory'] = original_factory
      response = [204, {}, []]
      app = lambda do |received|
        assert_same request, received
        assert_same original_input, received['rack.input']
        assert_same original_factory, received['rack.multipart.tempfile_factory']
        refute received.key?('spritesheet.workspace')

        assert_empty Dir.children(@directory)

        response
      end

      assert_same response, middleware(app).call(request)
    end
  end

  def test_upload_body_is_passed_through_without_reading_or_replacing_it
    request = env('original body')
    input = request['rack.input']
    length = request['CONTENT_LENGTH']
    app = lambda do |received|
      assert_same input, received['rack.input']
      assert_equal 0, input.pos
      assert_equal length, received['CONTENT_LENGTH']
      assert_empty Dir.children(received.fetch('spritesheet.workspace'))
      assert_equal 'original body', input.read

      [200, {}, []]
    end

    consume(middleware(app).call(request))

    refute input.closed?
    assert_empty Dir.children(@directory)
  end

  def test_workspace_remains_until_body_is_closed_even_after_aborted_download
    app = lambda do |request|
      file = File.join(request.fetch('spritesheet.workspace'), 'download.zip')

      File.binwrite(file, 'x' * 130_000)

      [200, {}, DownloadBody.new(file)]
    end
    response = middleware(app).call(env)

    refute_empty Dir.children(@directory)

    chunks = 0

    assert_raises(IOError) do
      response[2].each do |_chunk|
        chunks += 1

        raise IOError, 'client disconnected' if chunks == 2
      end
    end

    response[2].close

    assert_empty Dir.children(@directory)
  end

  def test_multipart_parser_failures_close_and_unlink_partially_created_uploads
    upload = nil
    app = lambda do |request|
      upload = request['rack.multipart.tempfile_factory'].call('image.png', 'image/png')

      upload.write('partial')

      raise Rack::Multipart::EmptyContentError
    end

    assert_raises(Rack::Multipart::EmptyContentError) { middleware(app).call(env) }
    assert upload.closed?
    assert_nil upload.path
    assert_empty Dir.children(@directory)
  end

  def test_full_app_repeated_success_and_failure_leave_no_workspaces
    image = create_image('red.png', 'red')
    app = RequestWorkspace.new(Application::Main, root: @directory)
    session = Rack::Test::Session.new(Rack::MockSession.new(app))

    3.times do
      session.post('/', image_files: { first: Rack::Test::UploadedFile.new(image, 'image/png') })
      assert_equal 200, session.last_response.status
      session.post('/')
      assert_equal 422, session.last_response.status
      assert_equal ['red.png'], Dir.children(@directory)
    end
  end

  def test_processing_failure_and_timeout_remove_uploads_and_scratch
    image = create_image('red.png', 'red')

    [0.000001, 30].each do |seconds|
      app = lambda do |request|
        directory = request.fetch('spritesheet.workspace')
        upload = request['rack.multipart.tempfile_factory'].call('image.png', 'image/png')

        FileUtils.cp(image, upload.path)

        File.write(File.join(directory, 'magick-orphan'), 'scratch')

        sheet = Spritesheet.new([upload.path], limits: ProcessingLimits.new(command_seconds: seconds))

        sheet.save_image(File.join(directory, 'missing', 'result.png'))

        flunk 'Expected ImageMagick failure'
      end

      assert_raises(ValidationError) { middleware(app).call(env) }
      assert_equal ['red.png'], Dir.children(@directory)
    end
  end

  def test_real_image_command_timeout
    limits = ProcessingLimits.new(command_seconds: 0.001)

    assert_raises(MiniMagick::TimeoutError) do
      ImageTools.run(:convert, directory: @directory, limits: limits) do |command|
        command.size '1024x1024'
        command << 'xc:red'
        command.blur '0x50'
        command << File.join(@directory, 'timeout.png')
      end
    end
  end
end
