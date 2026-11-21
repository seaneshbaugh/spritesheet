# frozen_string_literal: true

require 'tempfile'
require 'rack/body_proxy'
require_relative '../config/temporary_storage'

class RequestWorkspace
  def initialize(app, root: nil)
    @app = app
    @root = root
  end

  def call(env)
    # Only the generation endpoint needs uploads, scratch files, and output.
    return @app.call(env) unless env['REQUEST_METHOD'] == 'POST' && env['PATH_INFO'] == '/'

    directory = Dir.mktmpdir('request-', @root || TemporaryStorage.root)
    uploads = []
    cleaned = false
    handed_off = false
    cleanup = lambda do
      next if cleaned

      cleaned = true

      begin
        (uploads + Array(env['rack.tempfiles'])).uniq.each(&:close!)
      ensure
        FileUtils.remove_entry_secure(directory)
      end
    end

    begin
      env['spritesheet.workspace'] = directory
      env['rack.multipart.tempfile_factory'] = lambda do |filename, _content_type|
        extension = File.extname(filename.delete("\0"))[0, 129]

        Tempfile.new(['upload-', extension], directory).tap { |file| uploads << file }
      end

      status, headers, body = @app.call(env)
      response = [status, headers, Rack::BodyProxy.new(body, &cleanup)]
      handed_off = true

      response
    ensure
      cleanup.call unless handed_off
    end
  end
end
