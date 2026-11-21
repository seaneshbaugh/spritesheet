# frozen_string_literal: true

require 'test_helper'

class TemporaryStorageTest < Minitest::Test
  def with_root(path)
    keys = %w[SPRITESHEET_TMP_ROOT TMPDIR MAGICK_TEMPORARY_PATH]
    previous = ENV.to_h.slice(*keys)
    ENV['SPRITESHEET_TMP_ROOT'] = path

    yield
  ensure
    keys.each { |key| previous.key?(key) ? ENV[key] = previous[key] : ENV.delete(key) }
  end

  def test_boot_sweep_removes_only_owned_contents_and_holds_lock
    root = File.join(@directory, 'spritesheet-runtime')
    outside = File.join(@directory, 'unrelated')

    File.write(outside, 'keep')

    with_root(root) do
      TemporaryStorage.prepare!

      Dir.mkdir(File.join(root, 'abandoned'))

      File.write(File.join(root, 'abandoned', 'upload'), 'partial')

      File.symlink(outside, File.join(root, 'scratch-link'))

      lock = TemporaryStorage.clean_on_boot!

      assert_equal ['.lock'], Dir.children(root)
      assert_equal 'keep', File.read(outside)
      assert_raises(RuntimeError) { TemporaryStorage.clean_on_boot! }

      # App loading/reloading must not perform another sweep.
      File.write(File.join(root, 'live-job'), 'active')

      TemporaryStorage.prepare!

      assert File.exist?(File.join(root, 'live-job'))
    ensure
      lock&.close
    end
  end

  def test_root_and_lock_symlinks_are_rejected
    root = File.join(@directory, 'spritesheet-runtime')

    File.symlink(@directory, root)

    with_root(root) { assert_raises(RuntimeError) { TemporaryStorage.clean_on_boot! } }

    File.unlink(root)

    Dir.mkdir(root)

    File.symlink(File.join(@directory, 'outside'), File.join(root, '.lock'))

    with_root(root) { assert_raises(Errno::ELOOP) { TemporaryStorage.clean_on_boot! } }

    refute File.exist?(File.join(@directory, 'outside'))
  end
end
