# frozen_string_literal: true

require 'test_helper'

class ArchiveTest < Minitest::Test
  def test_creates_and_extracts_zip_with_original_binary_content
    image = create_image('red.png', 'red')
    css = File.join(@directory, 'sprites.css')

    File.write(css, '.sprite { display: inline-block; }')

    archive = File.join(@directory, 'spritesheet.zip')

    ArchiveCreator.new(image, css).save(archive)

    Zip::File.open(archive) do |zip|
      assert_equal %w[red.png sprites.css], zip.entries.map(&:name)
      assert_equal File.binread(image), zip.read('red.png')
      assert_equal File.read(css), zip.read('sprites.css')
    end

    extracted = ArchiveExtractor.new(archive).extract_to(File.join(@directory, 'extracted'))

    assert_equal %w[red.png sprites.css], extracted.map { |file| File.basename(file) }
    assert_equal File.binread(image), File.binread(extracted.first)
  end
end
