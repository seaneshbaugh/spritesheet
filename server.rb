# frozen_string_literal: true

require_relative 'helpers/assets'
require_relative 'models/archive_creator'
require_relative 'models/archive_extractor'
require_relative 'models/spritesheet'
require_relative 'models/upload_request'

module Application
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

      file = File.new("#{settings.root}/log/#{settings.environment}.log", 'a+')

      file.sync = true

      use Rack::CommonLogger, file
    end

    register Sinatra::ConfigFile

    config_file 'config/settings.yml'

    get '/' do
      erb :index
    end

    post '/' do
      upload = UploadRequest.new(params)

      tmp_directory = Dir.mktmpdir

      begin
        image_files = if upload.archive
                        ArchiveExtractor.new(upload.archive[:path]).extract_to(File.join(tmp_directory, 'sprites'))
                      else
                        upload.images.map { |image| image[:path] }
                      end.select { |image_file| Spritesheet::SUPPORTED_IMAGE_FORMATS.include?(File.extname(image_file).delete_prefix('.').downcase) }

        spritesheet = Spritesheet.new(image_files, upload.options)
        spritesheet_image_file = spritesheet.save_image(File.join(tmp_directory, 'sprites.png'))
        spritesheet_css_file = spritesheet.save_css(File.join(tmp_directory, 'sprites.css'))

        archive_file_basename = 'spritesheet.zip'
        archive_file = File.join(tmp_directory, archive_file_basename)

        ArchiveCreator.new(spritesheet_image_file, spritesheet_css_file).save(archive_file)

        content_type 'application/zip'
        attachment(archive_file_basename)
        response.write(File.binread(archive_file))
      ensure
        FileUtils.remove_entry_secure(tmp_directory)
      end
    end

    error ValidationError, ArchiveExtractor::UnsupportedArchiveFormatError, ArchiveCreator::UnsupportedArchiveFormatError do
      status 422

      @error = env['sinatra.error'].message

      erb :index
    end
  end
end
