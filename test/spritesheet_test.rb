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

class SpritesheetValidationTest < Minitest::Test
  def test_rejects_empty_image_list
    assert_raises(ValidationError) { Spritesheet.new([]) }
  end

  def test_validates_columns_and_identifiers_without_silent_sanitization
    image = create_image('red.png', 'red')

    %w[0 -1 1.5 abc 2oops].each do |columns|
      assert_raises(ValidationError) { Spritesheet.new([image], columns: columns) }
    end

    ['123', '!', 'two words', '<script>', ''].each do |identifier|
      assert_raises(ValidationError) { Spritesheet.new([image], class: identifier) }
      assert_raises(ValidationError) { Spritesheet.new([image], prefix: identifier) }
    end
  end

  def test_rejects_mixed_dimensions_and_animation
    red = create_image('red.png', 'red')
    blue = create_image('blue.png', 'blue')

    MiniMagick::Image.new(blue).resize '8x6!'

    error = assert_raises(ValidationError) { Spritesheet.new([red, blue]) }

    assert_includes error.message, 'same dimensions'

    animation = File.join(@directory, 'animated.gif')

    MiniMagick.convert do |command|
      command << red
      command << blue
      command << animation
    end

    error = assert_raises(ValidationError) { Spritesheet.new([animation]) }

    assert_includes error.message, 'multi-frame'
  end

  def test_static_gif_uppercase_extensions_and_transparency
    gif = create_image('clear.GIF', 'none')
    sheet = Spritesheet.new([gif], columns: 100)
    path = sheet.save_image(File.join(@directory, 'result.png'))
    image = MiniMagick::Image.new(path)

    assert_equal [4, 3], image.dimensions
    assert_equal '0', image['%[fx:p{0,0}.a]']
  end

  def test_direct_order_and_wrapping_css_match_generated_pixels
    files = [create_image('z.png', 'blue'), create_image('a.png', 'red'), create_image('b.png', 'green')]
    sheet = Spritesheet.new(files, columns: 2, class: 'icon', prefix: 'part')
    path = sheet.save_image(File.join(@directory, 'result.png'))
    css = File.read(sheet.save_css(File.join(@directory, 'result.css')))
    image = MiniMagick::Image.new(path)

    assert_equal [8, 6], image.dimensions
    assert_equal [0, 0, 255], rgb_pixel(image, 0, 0)
    assert_equal [255, 0, 0], rgb_pixel(image, 4, 0)
    assert_equal [0, 128, 0], rgb_pixel(image, 0, 3)
    assert_includes css, '.icon.part-3'
    assert_includes css, 'background-position: 0 -3px;'
    assert_includes css, 'url(sprites.png)'
  end
end
