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
      uploaded_archive_file = params.dig(:archive_file, :tempfile)&.path
      uploaded_image_files = (params[:image_files] || {}).map { |_name, uploaded_image_file| uploaded_image_file[:tempfile]&.path }.compact
      options = (params[:options] || {}).slice(:columns, :class, :prefix)

      raise UnprocessableEntityError.new('No file(s) selected.') unless uploaded_archive_file.present? || uploaded_image_files.present?

      tmp_directory = Dir.mktmpdir

      begin
        image_files = if uploaded_archive_file
                        ArchiveExtractor.new(uploaded_archive_file).extract_to(File.join(tmp_directory, 'sprites'))
                      else
                        uploaded_image_files
                      end.select { |image_file| Spritesheet::SUPPORTED_IMAGE_FORMATS.include?(File.extname(image_file).delete('.')) }

        spritesheet = Spritesheet.new(image_files, options)
        spritesheet_image_file = spritesheet.save_image(File.join(tmp_directory, 'sprites.png'))
        spritesheet_css_file = spritesheet.save_css(File.join(tmp_directory, 'sprites.css'))

        # TODO: Use param to determine extension.
        archive_file_basename = 'spritesheet.zip'
        archive_file = File.join(tmp_directory, archive_file_basename)

        ArchiveCreator.new(spritesheet_image_file, spritesheet_css_file).save(archive_file)

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
