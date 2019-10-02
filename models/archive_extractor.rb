# frozen_string_literal: true

class ArchiveExtractor
  SUPPORTED_FORMATS = %w[zip].freeze

  class UnsupportedArchiveFormatError < StandardError
    def initialize(archive_format)
      @archive_format = archive_format
    end

    def http_status
      422
    end

    def message
      "Uploaded archive file format (#{@archive_format}) is not supported. Supported formats include #{SUPPORTED_FORMATS.join(', ')}."
    end
  end

  def initialize(archive_file_path)
    @archive_file_path = archive_file_path

    raise UnsupportedArchiveFormatError.new(archive_format) unless respond_to?(extract_method, true)
  end

  def extract_to(extract_directory)
    FileUtils.mkdir_p(extract_directory)

    send(extract_method, extract_directory)
  end

  def archive_format
    @archive_format ||= File.extname(@archive_file_path).delete('.').downcase
  end

  private

  def extract_method
    @extract_method ||= "extract_#{archive_format}".to_sym
  end

  def extract_zip(extract_directory)
    Zip::File.open(@archive_file_path) do |zip_file|
      zip_file.reject { |file| file.name.start_with?('__MACOSX/') }.map do |file|
        path = File.join(extract_directory, file.name)

        zip_file.extract(file, path)

        path
      end
    end
  end
end
