# frozen_string_literal: true

require 'digest'

module Helpers
  module Assets
    def asset_path(path)
      "/#{path}?v=#{asset_version}"
    end

    def asset_version
      @asset_version ||= begin
        digest = Digest::SHA256.new

        Dir.glob(File.join(settings.public_folder, '{css,js}', '**', '*')).each do |file|
          digest << File.binread(file) if File.file?(file)
        end

        digest.hexdigest[0, 12]
      end
    end

    def h(value)
      Rack::Utils.escape_html(value.to_s)
    end

    def form_option(name)
      values = params[:options]
      value = values[name] if values.is_a?(Hash)

      value.is_a?(String) ? value : ''
    end

    def archive_mode?
      params[:input_mode] == 'archive'
    end
  end
end
