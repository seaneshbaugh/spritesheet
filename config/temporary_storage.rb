# frozen_string_literal: true

require 'fileutils'

module TemporaryStorage
  def self.root
    File.expand_path(ENV.fetch('SPRITESHEET_TMP_ROOT', '/tmp/spritesheet-runtime'))
  end

  def self.prepare!
    path = root

    unless File.basename(path).start_with?('spritesheet-') && File.realpath(File.dirname(path)) == File.dirname(path)
      raise 'Temporary root must be a dedicated spritesheet-* directory under a real parent directory'
    end

    begin
      Dir.mkdir(path, 0o700)
    rescue Errno::EEXIST
      # Inspect the existing entry without following a symlink.
    end

    stat = File.lstat(path)

    raise 'Temporary root must be an owned directory, not a symlink' unless stat.directory? && stat.uid == Process.uid

    File.chmod(0o700, path)

    ENV['TMPDIR'] = path
    ENV['MAGICK_TEMPORARY_PATH'] = path

    path
  end

  def self.clean_on_boot!
    path = prepare!

    lock = File.open(File.join(path, '.lock'), File::RDWR | File::CREAT | File::NOFOLLOW, 0o600)

    unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      lock.close

      raise 'Temporary storage is in use by another server'
    end

    cleaned = false

    begin
      Dir.children(path).each do |name|
        next if name == '.lock'

        # remove_entry_secure removes symlinks themselves, not their targets.
        FileUtils.remove_entry_secure(File.join(path, name))
      end

      cleaned = true
    ensure
      lock.close unless cleaned
    end

    lock
  end
end
