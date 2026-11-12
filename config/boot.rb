# frozen_string_literal: true

require 'bundler/setup'

Bundler.require(:default)

require 'erb'
require 'fileutils'
require 'tmpdir'
require 'sinatra/config_file'
require 'sinatra/reloader' if ENV.fetch('RACK_ENV', 'development') == 'development'

require_relative '../server'
