# frozen_string_literal: true

require_relative 'temporary_storage'

TemporaryStorage.prepare!

require 'bundler/setup'

Bundler.require(:default)

require 'erb'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'sinatra/config_file'
require_relative 'processing_limits'

# Keep Rack's parser guardrails consistent with the application's image limit.
Rack::Utils.multipart_file_limit = ProcessingLimits.current.image_count + 2
Rack::Utils.multipart_total_part_limit = ProcessingLimits.current.image_count + 16

require 'sinatra/reloader' if ENV.fetch('RACK_ENV', 'development') == 'development'

MiniMagick.configure do |config|
  config.timeout = ProcessingLimits.current.command_seconds
  config.tmpdir = TemporaryStorage.root
  config.warnings = false
end

require_relative '../server'
