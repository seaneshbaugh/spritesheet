# frozen_string_literal: true

# Read in bounded chunks; RequestWorkspace owns cleanup after body closure.
class DownloadBody
  def initialize(path)
    @path = path
  end

  def each
    File.open(@path, 'rb') do |file|
      while (chunk = file.read(64 * 1024))
        yield chunk
      end
    end
  end

  def close; end
end
