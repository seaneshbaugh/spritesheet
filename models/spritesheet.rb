# frozen_string_literal: true

require_relative 'validation_error'
require_relative 'image_tools'

class Spritesheet
  DEFAULT_COLUMNS = 5
  DEFAULT_CSS_CLASS = 'sprite'
  SUPPORTED_IMAGE_FORMATS = %w[gif png].freeze

  attr_reader :files

  def initialize(files, options = {}, limits: ProcessingLimits.current, **keyword_options)
    options = options.merge(keyword_options)
    @limits = limits

    raise ValidationError, 'No supported images were selected.' if files.empty?

    unless (options.keys - %i[columns class prefix]).empty?
      raise ValidationError, 'Invalid spritesheet options.'
    end

    if files.length > limits.image_count || files.sum { |file| File.size(file) } > limits.image_bytes
      raise ValidationError, 'Images exceed the 32 MiB total or image-count limit.'
    end

    columns = options.fetch(:columns, DEFAULT_COLUMNS).to_s

    unless columns.match?(/\A[0-9]+\z/) && columns.to_i.positive?
      raise ValidationError, 'Columns must be a positive whole number.'
    end

    @columns = [columns.to_i, files.length].min
    @css_class = css_identifier(options.fetch(:class, DEFAULT_CSS_CLASS), 'CSS class')
    @prefix = css_identifier(options.fetch(:prefix, @css_class), 'CSS prefix')
    @files = files
    @dimensions = files.map { |file| validate_image(file) }

    unless @dimensions.uniq.length == 1
      raise ValidationError, 'All images must have the same dimensions for now.'
    end

    width, height = @dimensions.first
    canvas_width = width * @columns
    canvas_height = height * ((files.length + @columns - 1) / @columns)

    if canvas_width > limits.dimension || canvas_height > limits.dimension || canvas_width * canvas_height > limits.canvas_pixels
      raise ValidationError, 'The generated spritesheet exceeds the canvas size limit.'
    end
  end

  def save_image(image_file_path)
    ImageTools.run(:montage, directory: File.dirname(image_file_path), limits: @limits) do |montage|
      # The slim image has no default ImageMagick font configured.
      montage.font 'DejaVu-Sans'

      @files.each do |file|
        montage << file
      end

      montage.background 'none'
      montage.mode 'Concatenate'
      montage.tile "#{@columns}x"

      montage << image_file_path
    end

    image_file_path
  rescue MiniMagick::Error
    raise ValidationError, 'Image data could not be processed. Select valid PNG or static GIF images.'
  end

  def save_css(css_file_path)
    @sprites = {}

    n = 1
    y = 0

    files.each_slice(@columns) do |row|
      x = 0
      largest_height = 0

      row.each do |_file|
        width, height = @dimensions[n - 1]
        @sprites["#{@prefix}-#{n}"] = { x1: x, y1: y, x2: x + width, y2: y + height }
        x += width

        if height > largest_height
          largest_height = height
        end

        n += 1
      end

      y += largest_height
    end

    # TODO: Make it so the view file can be passed in as an option.
    template_file_name = File.expand_path(File.join('..', 'views', 'sprites.css.erb'), __dir__)

    File.write(css_file_path, ERB.new(File.read(template_file_name), trim_mode: '>').result(binding))

    css_file_path
  end

  private

  def css_identifier(value, label)
    unless value.is_a?(String) && value.strip.match?(/\A(?:[a-zA-Z_]|-[a-zA-Z_-])[a-zA-Z0-9_-]*\z/)
      raise ValidationError, "#{label} must be a valid CSS identifier (letters, digits, underscores, and hyphens)."
    end

    value.strip
  end

  def validate_image(file)
    extension = File.extname(file).delete_prefix('.').downcase

    unless SUPPORTED_IMAGE_FORMATS.include?(extension)
      raise ValidationError, 'Only PNG and static GIF images are supported.'
    end

    frames = ImageTools.run(:identify, directory: File.dirname(file), limits: @limits) do |command|
      command.ping
      command.format "%m %w %h\n"
      command << file
    end.lines.map(&:split)

    unless frames.all? { |format, width, height| format.downcase == extension && width.to_i.positive? && height.to_i.positive? } && !frames.empty?
      raise ValidationError, 'Image contents must match their PNG or GIF filename extension.'
    end

    raise ValidationError, 'Animated or multi-frame images are not supported yet.' unless frames.length == 1

    dimensions = frames.first.drop(1).map(&:to_i)

    if dimensions.any? { |value| value > @limits.dimension } || dimensions.inject(:*) > @limits.image_pixels
      raise ValidationError, 'An image exceeds the pixel or dimension limit.'
    end

    dimensions
  rescue MiniMagick::Error
    raise ValidationError, 'Invalid image data. Select valid PNG or static GIF images.'
  end
end
