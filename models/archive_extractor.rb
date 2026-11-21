# frozen_string_literal: true

require_relative 'validation_error'
require_relative '../config/processing_limits'

class ArchiveExtractor
  SUPPORTED_FORMATS = %w[zip].freeze

  class UnsupportedArchiveFormatError < StandardError
    def initialize(archive_format)
      super()

      @archive_format = archive_format
    end

    def http_status
      422
    end

    def message
      "Uploaded archive file format (#{@archive_format}) is not supported. Supported formats include #{SUPPORTED_FORMATS.join(', ')}."
    end
  end

  def initialize(archive_file_path, limits: ProcessingLimits.current)
    @limits = limits
    @archive_file_path = archive_file_path

    raise UnsupportedArchiveFormatError.new(archive_format) unless respond_to?(extract_method, true)
  end

  def extract_to(extract_directory)
    FileUtils.mkdir_p(extract_directory)

    unless File.realpath(extract_directory) == File.expand_path(extract_directory) && Dir.empty?(extract_directory)
      raise ValidationError, 'Extraction requires an empty, private directory.'
    end

    send(extract_method, extract_directory)
  rescue Zip::Error, Zlib::Error, EOFError, Errno::EEXIST, Errno::ENOTDIR, Errno::EISDIR
    raise ValidationError, 'The ZIP archive is invalid or could not be read.'
  end

  def archive_format
    @archive_format ||= File.extname(@archive_file_path).delete('.').downcase
  end

  private

  def extract_method
    @extract_method ||= :"extract_#{archive_format}"
  end

  def extract_zip(extract_directory)
    count = Zip::File.count_entries(@archive_file_path)

    raise ValidationError, 'The ZIP archive has too many entries.' if count > @limits.archive_entries

    Zip::File.open(@archive_file_path) do |zip_file|
      entries = zip_file.entries

      raise ValidationError, 'The ZIP archive contains duplicate or inconsistent entries.' unless entries.length == count

      paths = {}

      entries.each do |entry|
        raise ValidationError, 'The ZIP archive contains an invalid filename.' unless entry.name.valid_encoding?

        name = entry.name.delete_suffix('/')
        parts = name.split('/', -1)

        if entry.encrypted?
          raise ValidationError, 'Encrypted ZIP archives are not supported.'
        end

        if (!entry.file? && !entry.directory?) || name.bytesize > 1024 || parts.length > 16 ||
           name.start_with?('/') || name.include?("\\") || name.include?("\0") || name.include?(':') ||
           parts.any? { |part| part.empty? || %w[. ..].include?(part) } || paths.key?(name)
          raise ValidationError, 'The ZIP archive contains an unsafe or duplicate entry.'
        end

        paths[name] = entry
      end

      paths.each_key do |name|
        parts = name.split('/')

        (1...parts.length).each do |length|
          parent = paths[parts.first(length).join('/')]

          raise ValidationError, 'The ZIP archive contains conflicting paths.' if parent && !parent.directory?
        end
      end

      image_count = entries.count do |entry|
        entry.file? && !entry.name.start_with?('__MACOSX/') &&
          %w[png gif].include?(File.extname(entry.name).delete_prefix('.').downcase)
      end

      raise ValidationError, 'The ZIP archive contains too many images.' if image_count > @limits.image_count

      total = 0
      images = 0

      entries.filter_map do |entry|
        next if entry.directory?

        path = File.join(extract_directory, entry.name)
        metadata = entry.name.start_with?('__MACOSX/')
        image = !metadata && %w[png gif].include?(File.extname(entry.name).delete_prefix('.').downcase)
        output = nil

        begin
          unless metadata
            FileUtils.mkdir_p(File.dirname(path))

            output = File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600)
          end

          entry.get_input_stream do |stream|
            while (chunk = stream.read(64 * 1024)) && !chunk.empty?
              total += chunk.bytesize
              images += chunk.bytesize if image

              if total > @limits.extraction_bytes || images > @limits.image_bytes
                raise ValidationError, 'ZIP contents exceed the extraction limit or 32 MiB image allowance.'
              end

              output&.write(chunk)
            end
          end
        ensure
          output&.close
        end

        path unless metadata
      end
    end
  end
end
