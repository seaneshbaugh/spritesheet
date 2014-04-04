module Application
  class Main < Sinatra::Base
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

        Zip::ZipFile.open(tmp_file_name) do |zip_file|
          zip_file.each do |f|
            path = File.join(tmp_directory, 'sprites', f.name)

            FileUtils.mkdir_p(File.dirname(path))

            zip_file.extract(f, path)
          end
        end

        files = Dir.glob(File.join(tmp_directory, 'sprites', '**/*.png'))

        spritesheet_file_name = File.join(tmp_directory, 'spritesheet.png')

        system("montage #{files.join(' ')} -background none -mode Concatenate -tile 5x #{spritesheet_file_name} > /dev/null 2>&1")

        @sprites = {}

        n = 1

        y = 0

        files.each_slice(5) do |row|
          x = 0

          largest_height = 0

          row.each do |file|
            image = Magick::Image.read(file)

            @sprites["sprite-#{n}"] = { :x1 => x, :y1 => y, :x2 => x + image[0].columns, :y2 => y + image[0].rows }

            x += image[0].columns

            if image[0].rows > largest_height
              largest_height = image[0].rows
            end

            n += 1
          end

          y += largest_height
        end

        template_file_name = File.join(settings.views, 'sprites.css.erb')

        css_file_name = File.join(tmp_directory, 'sprites.css')

        css_file = File.new(css_file_name, 'w')

        css_file.puts ERB.new(File.read(template_file_name), 0, '>').result(binding)

        css_file.close

        zip_file_name = File.join(tmp_directory, 'spritesheet.zip')

        Zip::ZipOutputStream.open(zip_file_name) do |zip_file|
          zip_file.put_next_entry('spritesheet.png')

          zip_file.print IO.read(spritesheet_file_name)

          zip_file.put_next_entry('sprites.css')

          zip_file.print IO.read(css_file_name)
        end

        response.headers['content_type'] = 'application/octet-stream'

        attachment('spritesheet.zip')

        response.write(File.read(zip_file_name))
      ensure
        FileUtils.remove_entry_secure tmp_directory
      end
    end
  end
end
