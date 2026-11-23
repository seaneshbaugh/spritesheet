# frozen_string_literal: true

source 'https://rubygems.org'
ruby file: '.ruby-version'

gem 'mini_magick', '~> 5.4'
gem 'puma', '~> 8.0'
gem 'rubyzip', '~> 3.7', require: 'zip'
gem 'sinatra', '~> 4.2', require: 'sinatra/base'
gem 'sinatra-contrib', '~> 4.2', require: false
gem 'tailwindcss-ruby', '~> 4.3', require: false

group :development do
  gem 'foreman', '~> 0.90', require: false
  gem 'rubocop', '~> 1.92', require: false
end

group :test do
  gem 'minitest', '~> 6.1', require: false
  gem 'rack-test', '~> 2.2', require: false
  gem 'rake', '~> 13.3', require: false
  gem 'selenium-webdriver', '~> 4.0', require: false
end
