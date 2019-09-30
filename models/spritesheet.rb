# frozen_string_literal: true

class Spritesheet
  DEFAULT_COLUMN_COUNT = 5
  DEFAULT_CLASS_NAME = 'sprite'

  attr_reader :files

  def initialize(files, options = {})
    options[:tmp_directory] ||= Dir.mktmpdir
    options[:columns] ||= DEFAULT_COLUMN_COUNT
    options[:class] ||= DEFAULT_CLASS_NAME
    options[:prefix] ||= options[:class]

    options[:columns] = options[:columns].to_i.clamp(1, files.length)
    options[:class] = options[:class].strip.gsub(/[^a-zA-Z\d-]/, '').gsub(/^(-|_)+|(-|_)+$/, '')
    options[:prefix] = options[:prefix].strip.gsub(/[^a-zA-Z\d-]/, '').gsub(/^(-|_)+|(-|_)+$/, '')

    @files = files
    @options = options
  end

  def columns
    @options[:columns]
  end

  def generate!
    spritesheet_file_name = File.join(@options[:tmp_directory], 'spritesheet.png')

    system("montage #{files.join(' ')} -background none -mode Concatenate -tile #{columns}x #{spritesheet_file_name} > /dev/null 2>&1")

    @sprites = {}

    n = 1

    y = 0

    files.each_slice(columns) do |row|
      x = 0

      largest_height = 0

      row.each do |file|
        image = MiniMagick::Image.open(file)

        @sprites["#{prefix}-#{n}"] = { x1: x, y1: y, x2: x + image.width, y2: y + image.height }

        x += image.width

        if image.height > largest_height
          largest_height = image.height
        end

        n += 1
      end

      y += largest_height
    end

    # TODO: Figure out how to get to Sinatra settings object from here to get to settings.views.
    template_file_name = File.expand_path(File.join('..', 'views', 'sprites.css.erb'), __dir__)

    css_file_name = File.join(@options[:tmp_directory], 'sprites.css')

    css_file = File.new(css_file_name, 'w')

    css_file.puts ERB.new(File.read(template_file_name), 0, '>').result(binding)

    css_file.close

    zip_file_name = File.join(@options[:tmp_directory], 'spritesheet.zip')

    Zip::OutputStream.open(zip_file_name) do |zip_file|
      zip_file.put_next_entry('spritesheet.png')

      zip_file.print(IO.read(spritesheet_file_name))

      zip_file.put_next_entry('sprites.css')

      zip_file.print(IO.read(css_file_name))
    end

    # TODO: Figure a better return value here. Perhaps the file itself.
    zip_file_name
  end

  def prefix
    @options[:prefix]
  end
end
