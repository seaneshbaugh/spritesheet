# frozen_string_literal: true

class ArchiveCreator
  SUPPORTED_FORMATS = %w[zip].freeze

  class UnsupportedArchiveFormatError < StandardError
    def initialize(requested_format)
      @requested_format = requested_format
    end

    def http_status
      422
    end

    def message
      "Requested archive format (#{@requested_format}) is not supported. Supported formats include #{SUPPORTED_FORMATS.join(', ')}."
    end
  end

  def initialize(*files)
    @files = files
  end

  def add_files(*files)
    @files.concat(files)
  end

  def save(archive_file_path)
    archive_format = File.extname(archive_file_path).delete('.').downcase
    save_method = "save_#{archive_format}".to_sym

    raise UnsupportedArchiveFormatError.new(archive_format) unless respond_to?(save_method, true)

    send(save_method, archive_file_path)
  end

  private

  def save_zip(zip_file_path)
    Zip::OutputStream.open(zip_file_path) do |zip_file|
      @files.each do |file|
        zip_file.put_next_entry(File.basename(file))
        zip_file.print(IO.read(file))
      end
    end
  end
end
