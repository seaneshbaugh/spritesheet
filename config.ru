if ENV['RACK_ENV'] == 'production'
  require 'rubygems'

  ENV['GEM_PATH'] = '/home/seaneshb/spritesheet/production/shared/bundle/ruby/1.8:/usr/lib/ruby/gems/1.8'
  ENV['GEM_HOME'] = '/home/seaneshb/spritesheet/production/shared/bundle/ruby/1.8'

  Gem.clear_paths
end

require 'bundler/setup'

Bundler.require(:default)

require 'sinatra/config_file'
require 'sinatra/reloader'
require 'sinatra/json'
require 'zip/zipfilesystem'

require File.join(File.dirname(__FILE__), 'server')

run Application::Main
