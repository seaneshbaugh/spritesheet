# frozen_string_literal: true

require 'bundler/setup'

Bundler.require(:default)

require 'sinatra/config_file'
require 'sinatra/reloader'
require 'sinatra/json'

require_relative 'helpers/assets'
require_relative 'server'

run Application::Main
