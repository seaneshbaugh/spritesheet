# frozen_string_literal: true

require_relative 'helpers/assets'
require_relative 'models/spritesheet'

module Application
  class Main < Sinatra::Base
    include Helpers::Assets

    configure :development do
      register Sinatra::Reloader
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
      unless params[:file] && (file = params[:file][:tempfile]) && (file_name = params[:file][:filename])
        @error = 'No file selected.'

        erb :index
      end

      tmp_directory = Dir.mktmpdir

      begin
        tmp_file_name = File.join(tmp_directory, file_name)

        File.open(tmp_file_name, 'wb') do |f|
          f.write file.read
        end

        Zip::File.open(tmp_file_name) do |zip_file|
          zip_file.each do |f|
            path = File.join(tmp_directory, 'sprites', f.name)

            FileUtils.mkdir_p(File.dirname(path))

            zip_file.extract(f, path)
          end
        end

        files = Dir.glob(File.join(tmp_directory, 'sprites', '**/*.{gif,png}'))

        logger.info files.inspect

        spritesheet = Spritesheet.new(files, tmp_directory: tmp_directory)

        zip_file_name = spritesheet.generate!

        response.headers['content_type'] = 'application/octet-stream'

        attachment('spritesheet.zip')

        response.write(File.read(zip_file_name))
      ensure
        FileUtils.remove_entry_secure(tmp_directory)
      end
    end
  end
end
