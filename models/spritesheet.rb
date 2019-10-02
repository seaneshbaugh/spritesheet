# frozen_string_literal: true

class Spritesheet
  DEFAULT_COLUMNS = 5
  DEFAULT_CSS_CLASS = 'sprite'
  SUPPORTED_IMAGE_FORMATS = %w[gif png]

  attr_reader :files

  def initialize(files, options = {})
    options[:columns] ||= DEFAULT_COLUMNS
    options[:class] ||= DEFAULT_CSS_CLASS
    options[:prefix] ||= options[:class]

    # TODO: `clamp` will raise an error if no files are passed. Raise a custom error instead so it can be handled.
    @columns = options[:columns].to_i.clamp(1, files.length)
    @css_class = options[:class].strip.gsub(/[^a-zA-Z\d-]/, '').gsub(/^(-|_)+|(-|_)+$/, '')
    @prefix = options[:prefix].strip.gsub(/[^a-zA-Z\d-]/, '').gsub(/^(-|_)+|(-|_)+$/, '')
    @files = files
  end

  def save_image(image_file_path)
    MiniMagick::Tool::Montage.new do |montage|
      @files.each do |file|
        montage << file
      end

      montage.background 'none'
      montage.mode 'Concatenate'
      montage.tile "#{@columns}x"

      montage << image_file_path
    end

    image_file_path
  end

  def save_css(css_file_path)
    @sprites = {}

    n = 1
    y = 0

    files.each_slice(@columns) do |row|
      x = 0
      largest_height = 0

      row.each do |file|
        image = MiniMagick::Image.open(file)
        @sprites["#{@prefix}-#{n}"] = { x1: x, y1: y, x2: x + image.width, y2: y + image.height }
        x += image.width

        if image.height > largest_height
          largest_height = image.height
        end

        n += 1
      end

      y += largest_height
    end

    # TODO: Make it so the view file can be passed in as an option.
    template_file_name = File.expand_path(File.join('..', 'views', 'sprites.css.erb'), __dir__)

    css_file = File.new(css_file_path, 'w')

    css_file.puts ERB.new(File.read(template_file_name), 0, '>').result(binding)

    css_file.close

    css_file_path
  end
end
