# frozen_string_literal: true

require 'test_helper'
require 'socket'
require 'timeout'
require 'rbconfig'

# Real Puma exercises buffering, multipart parsing, body closure and exec locks.
class RuntimeServerTest < Minitest::Test
  def start_server
    @root = File.join(@directory, 'spritesheet-runtime')
    @socket_path = File.join(@directory, 'puma.sock')
    @log_path = File.join(@directory, 'server.log')

    FileUtils.rm_f(@socket_path)

    @pid = Process.spawn({ 'SPRITESHEET_TMP_ROOT' => @root, 'APP_PORT' => '0', 'RACK_ENV' => 'production' },
                         RbConfig.ruby, 'bin/server', '-b', "unix://#{@socket_path}", out: @log_path, err: @log_path)

    Timeout.timeout(10) do
      loop do
        break if File.socket?(@socket_path)

        if Process.waitpid(@pid, Process::WNOHANG)
          @pid = nil

          flunk File.read(@log_path)
        end

        sleep 0.02
      end
    end
  end

  def stop_server(signal = 'TERM')
    return unless @pid

    Process.kill(signal, @pid)

    Timeout.timeout(5) { Process.wait(@pid) }

    @pid = nil
  end

  def exchange(headers, body = '')
    socket = UNIXSocket.new(@socket_path)

    socket.write("POST / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n#{headers}\r\n#{body}")

    Timeout.timeout(5) { socket.read }
  ensure
    socket&.close
  end

  def multipart(content)
    "--sample\r\nContent-Disposition: form-data; name=\"image_files[first]\"; filename=\"one.png\"\r\nContent-Type: image/png\r\n\r\n".b +
      content + "\r\n--sample--\r\n"
  end

  def assert_idle_storage
    stable_since = nil

    Timeout.timeout(5) do
      loop do
        entries = Dir.children(@root) - %w[.lock puma.pid]
        files = Dir.glob("/proc/#{@pid}/fd/*").filter_map do |fd|
          File.readlink(fd) rescue nil
        end
        clear = entries.empty? && files.none? { |path| path.start_with?(@root) && path.include?('(deleted)') }
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stable_since = clear ? (stable_since || now) : nil

        break if stable_since && now - stable_since >= 0.15

        sleep 0.02
      end
    end

    assert_empty Dir.children(@root) - %w[.lock puma.pid]
  end

  def test_real_uploads_rejection_abort_and_kill_restart_cleanup
    start_server

    image = create_image('image.png', 'red')
    body = multipart(File.binread(image))
    headers = "Content-Type: multipart/form-data; boundary=sample\r\nContent-Length: #{body.bytesize}\r\n"
    response = exchange(headers, body)

    assert_includes response, '200 OK'
    assert_includes response.downcase, 'content-type: application/zip'
    assert_idle_storage

    response = exchange("Content-Type: multipart/form-data; boundary=sample\r\nContent-Length: 8\r\n", 'broken!!')

    assert_match(/HTTP\/1.1 (400|422)/, response)
    assert_idle_storage

    # Force the parser to create a tempfile before encountering an incomplete part.
    malformed = body.sub(/--sample--\r\n\z/, '--sample' + "\r\nBroken")
    response = exchange("Content-Type: multipart/form-data; boundary=sample\r\nContent-Length: #{malformed.bytesize}\r\n", malformed)

    assert_match(/HTTP\/1.1 (400|422)/, response)
    assert_idle_storage

    limit = ProcessingLimits.current.request_bytes

    # Must reject from headers, without waiting for the declared body.
    assert_includes exchange("Content-Length: #{limit + 1}\r\n"), '413'
    assert_idle_storage

    # Chunked decoding must stop as soon as actual bytes exceed the limit.
    socket = UNIXSocket.new(@socket_path)

    socket.write("POST / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n")

    chunk = 'x' * (1024 * 1024)

    begin
      41.times { socket.write("#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n") }

      socket.write("0\r\n\r\n")
    rescue Errno::EPIPE, Errno::ECONNRESET
      # Puma may close the connection immediately after its 413 response.
    end

    response = +''

    Timeout.timeout(5) do
      begin
        loop { response << socket.readpartial(4096) }
      rescue EOFError, Errno::ECONNRESET
        # Preserve the 413 bytes read before the server resets unread input.
      end
    end

    assert_includes response, '413'

    socket.close

    socket = nil

    assert_idle_storage

    socket = UNIXSocket.new(@socket_path)

    socket.write("POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1000000\r\n\r\n" + ('x' * 200_000))

    socket.close

    socket = nil

    assert_idle_storage

    # Kill during an incomplete buffered upload; seed job artifacts to check
    # named-file recovery as well as Puma's unlinked upload-buffer lifecycle.
    socket = UNIXSocket.new(@socket_path)

    socket.write("POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1000000\r\n\r\npartial")

    Dir.mkdir(File.join(@root, 'request-abandoned'))

    File.write(File.join(@root, 'request-abandoned', 'magick-orphan'), 'scratch')

    outside = File.join(@directory, 'unrelated')

    File.write(outside, 'keep')

    stop_server('KILL')

    socket.close

    socket = nil

    assert File.exist?(File.join(@root, 'request-abandoned'))

    start_server

    assert_idle_storage

    assert_equal 'keep', File.read(outside)

    # A second launch sharing the root must fail before deleting a live job.
    File.write(File.join(@root, 'live-job'), 'active')

    output = File.join(@directory, 'second.log')
    second = Process.spawn({ 'SPRITESHEET_TMP_ROOT' => @root }, RbConfig.ruby, 'bin/server', out: output, err: output)
    _, status = Process.wait2(second)

    refute status.success?
    assert_includes File.read(output), 'in use'
    assert File.exist?(File.join(@root, 'live-job'))
  ensure
    socket&.close

    stop_server
  end

  def test_cleanup_permission_failure_prevents_puma_startup
    skip 'Requires root to create a directory owned by a different user' unless Process.uid.zero?

    parent = Dir.mktmpdir('spritesheet-permission-test-', '/tmp')

    File.chmod(0o755, parent)

    root = File.join(parent, 'spritesheet-runtime')

    Dir.mkdir(root, 0o700)

    File.chown(65_534, 65_534, root)

    protected = File.join(root, 'abandoned')

    Dir.mkdir(protected, 0o700)

    File.write(File.join(protected, 'scratch'), 'cannot remove as runtime user')

    log = File.join(@directory, 'permission-failure.log')
    pid = Process.spawn({ 'SPRITESHEET_TMP_ROOT' => root }, RbConfig.ruby, 'bin/server',
                        uid: 65_534, gid: 65_534, out: log, err: log)
    _, status = Process.wait2(pid)

    refute status.success?
    assert_includes File.read(log), 'Spritesheet startup failed'
    refute_includes File.read(log), 'Puma starting'
    assert File.exist?(File.join(protected, 'scratch'))
  ensure
    FileUtils.remove_entry_secure(parent) if parent
  end

  def test_unsafe_boot_storage_fails_before_starting_puma
    root = File.join(@directory, 'spritesheet-runtime')

    Dir.mkdir(root)

    File.symlink(File.join(@directory, 'outside'), File.join(root, '.lock'))

    log = File.join(@directory, 'failure.log')
    pid = Process.spawn({ 'SPRITESHEET_TMP_ROOT' => root }, RbConfig.ruby, 'bin/server', out: log, err: log)
    _, status = Process.wait2(pid)

    refute status.success?
    assert_includes File.read(log), 'Spritesheet startup failed'
    refute_includes File.read(log), 'Puma starting'
  end
end
