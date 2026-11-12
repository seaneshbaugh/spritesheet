# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require_relative '../config/boot'
require 'minitest/autorun'
require 'rack/test'

class Minitest::Test
  def setup
    super

    @directory = Dir.mktmpdir('spritesheet-test-')
  end

  def teardown
    FileUtils.remove_entry(@directory)

    super
  end

  def create_image(name, color)
    path = File.join(@directory, name)

    MiniMagick.convert do |command|
      command.size '4x3'
      command << "xc:#{color}"
      command << path
    end

    path
  end

  def rgb_pixel(image, x, y)
    format = %w[r g b].map { |channel| "%[fx:255*p{#{x},#{y}}.#{channel}]" }.join(',')

    image[format].split(',').map { |value| value.to_f.round }
  end
end
