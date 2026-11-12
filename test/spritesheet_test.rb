# frozen_string_literal: true

require 'test_helper'

class SpritesheetTest < Minitest::Test
  def test_generates_image_and_css_for_two_images
    files = [create_image('red.png', 'red'), create_image('blue.png', 'blue')]
    sheet = Spritesheet.new(files, columns: 2)
    image_path = sheet.save_image(File.join(@directory, 'sprites.png'))
    css_path = sheet.save_css(File.join(@directory, 'sprites.css'))

    assert_equal [8, 3], MiniMagick::Image.open(image_path).dimensions

    css = File.read(css_path)

    assert_includes css, '.sprite.sprite-1'
    assert_includes css, '.sprite.sprite-2'
    assert_includes css, 'background-position: -4px 0;'
    assert_includes css, 'width: 4px;'
    assert_includes css, 'height: 3px;'
  end
end
