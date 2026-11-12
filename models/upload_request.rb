# frozen_string_literal: true

require_relative 'validation_error'
require_relative 'spritesheet'

class UploadRequest
  attr_reader :archive, :images, :options

  def initialize(params)
    @archive = upload(params[:archive_file])
    collection = params[:image_files] || {}

    raise ValidationError, 'Image files must be a collection of uploads.' unless collection.is_a?(Hash)

    @images = collection.values.filter_map { |value| upload(value) }

    raise ValidationError, 'Choose images or a ZIP archive, not both.' if archive && !images.empty?
    raise ValidationError, 'No file(s) selected.' unless archive || !images.empty?

    if archive
      raise ValidationError, 'Select a ZIP archive.' unless extension(archive) == 'zip'
    elsif images.any? { |image| !Spritesheet::SUPPORTED_IMAGE_FORMATS.include?(extension(image)) }
      raise ValidationError, 'Only PNG and static GIF images are supported.'
    end

    values = params[:options] || {}

    raise ValidationError, 'Options must be a collection of named values.' unless values.is_a?(Hash)

    @options = values.each_with_object({}) do |(key, value), result|
      unless %w[columns class prefix].include?(key.to_s) && value.is_a?(String)
        raise ValidationError, 'Invalid spritesheet options.'
      end

      result[key.to_sym] = value.strip unless value.strip.empty?
    end
  end

  private

  def upload(value)
    return if value.nil?

    raise ValidationError, 'Invalid file upload.' unless value.is_a?(Hash)

    filename = value[:filename] || value['filename']
    tempfile = value[:tempfile] || value['tempfile']

    unless filename.is_a?(String) && tempfile.respond_to?(:path) && File.file?(tempfile.path)
      raise ValidationError, 'Invalid file upload.'
    end

    return if filename.empty?

    { path: tempfile.path, filename: filename }
  end

  def extension(file)
    File.extname(file[:filename]).delete_prefix('.').downcase
  end
end
