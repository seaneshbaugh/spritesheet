# frozen_string_literal: true

require 'sinatra/base'

module Helpers
  module Assets
    def asset_pack_path(asset_file_path)
      if ENV['RACK_ENV'] == 'development'
        "http://localhost:8080/#{asset_file_path}"
      else
        asset_file_path
      end
    end
  end

  Sinatra.helpers Assets
end
