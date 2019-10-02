# frozen_string_literal: true

require_relative 'helpers/assets'
require_relative 'models/archive_creator'
require_relative 'models/archive_extractor'
require_relative 'models/spritesheet'

module Application
  class Main < Sinatra::Base
    include Helpers::Assets

    class UnprocessableEntityError < StandardError
      def http_status
        422
      end
    end

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
      uploaded_file = params.dig(:file, :tempfile)
      uploaded_file_name = params.dig(:file, :filename)

      raise UnprocessableEntityError.new('No file selected.') unless uploaded_file && uploaded_file_name

      tmp_directory = Dir.mktmpdir

      begin
        archive_extractor = ArchiveExtractor.new(uploaded_file.path)
        files = archive_extractor.extract_to(File.join(tmp_directory, 'sprites'))
        image_files = files.select { |file| Spritesheet::SUPPORTED_IMAGE_FORMATS.include?(File.extname(file).delete('.')) }

        spritesheet = Spritesheet.new(image_files)
        spritesheet_image_file = spritesheet.save_image(File.join(tmp_directory, 'sprites.png'))
        spritesheet_css_file = spritesheet.save_css(File.join(tmp_directory, 'sprites.css'))

        # TODO: Use param to determine extension.
        archive_file_basename = 'spritesheet.zip'
        archive_file = File.join(tmp_directory, archive_file_basename)

        archive_creator = ArchiveCreator.new(spritesheet_image_file, spritesheet_css_file)
        archive_creator.save(archive_file)

        response.headers['content_type'] = 'application/octet-stream'
        attachment(archive_file_basename)
        response.write(File.read(archive_file))
      ensure
        FileUtils.remove_entry_secure(tmp_directory)
      end
    end

    error UnprocessableEntityError, ArchiveExtractor::UnsupportedArchiveFormatError, ArchiveCreator::UnsupportedArchiveFormatError do
      @error = env['sinatra.error'].message

      erb :index
    end
  end
end
