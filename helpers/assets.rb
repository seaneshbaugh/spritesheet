# frozen_string_literal: true

require 'sinatra/base'

module Helpers
  module Assets
    def asset_pack_path(path)
      if ENV['RACK_ENV'] == 'development'
        "#{settings.webpack_dev_server_url}#{path}"
      else
        path
      end
    end
  end

  Sinatra.helpers Assets
end
