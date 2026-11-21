# frozen_string_literal: true

require_relative 'helpers/assets'
require_relative 'models/archive_creator'
require_relative 'models/archive_extractor'
require_relative 'models/spritesheet'
require_relative 'models/upload_request'
require_relative 'models/download_body'
require_relative 'middleware/request_workspace'

module Application
  def self.app(main = Main)
    RequestWorkspace.new(main)
  end

  class Main < Sinatra::Base
    include Helpers::Assets

    configure :development do
      register Sinatra::Reloader
      also_reload './helpers/*.rb'
      also_reload './models/*.rb'

      set :show_exceptions, :after_handler
    end

    configure :development, :production do
      enable :logging
    end

    register Sinatra::ConfigFile

    config_file 'config/settings.yml'

    get '/' do
      erb :index
    end

    post '/' do
      upload = UploadRequest.new(params)
      tmp_directory = env.fetch('spritesheet.workspace')
      image_files = if upload.archive
                      ArchiveExtractor.new(upload.archive[:path]).extract_to(File.join(tmp_directory, 'sprites'))
                    else
                      upload.images.map { |image| image[:path] }
                    end.select { |file| Spritesheet::SUPPORTED_IMAGE_FORMATS.include?(File.extname(file).delete_prefix('.').downcase) }
      spritesheet = Spritesheet.new(image_files, upload.options)
      image_file = spritesheet.save_image(File.join(tmp_directory, 'sprites.png'))
      css_file = spritesheet.save_css(File.join(tmp_directory, 'sprites.css'))
      archive_file = File.join(tmp_directory, 'spritesheet.zip')
      ArchiveCreator.new(image_file, css_file).save(archive_file)

      content_type 'application/zip'
      attachment('spritesheet.zip')
      headers 'content-length' => File.size(archive_file).to_s
      body DownloadBody.new(archive_file)
    end

    error ValidationError, ArchiveExtractor::UnsupportedArchiveFormatError, ArchiveCreator::UnsupportedArchiveFormatError do
      status 422

      @error = env['sinatra.error'].message

      erb :index
    end
  end
end
