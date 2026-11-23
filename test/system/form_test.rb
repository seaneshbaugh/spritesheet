# frozen_string_literal: true

require 'test_helper'
require 'selenium-webdriver'
require 'socket'
require 'net/http'
require 'timeout'
require 'rbconfig'

class FormTest < Minitest::Test
  def setup
    super

    listener = TCPServer.new('0.0.0.0', 0)
    port = listener.addr[1]

    listener.close

    @pid = Process.spawn({ 'APP_PORT' => port.to_s, 'RACK_ENV' => 'test',
                           'SPRITESHEET_TMP_ROOT' => File.join(@directory, 'spritesheet-browser') },
                         RbConfig.ruby, 'bin/server', out: File.join(@directory, 'server.log'), err: [:child, :out])

    Timeout.timeout(10) do
      loop do
        begin
          break if Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/")).code == '200'
        rescue Errno::ECONNREFUSED
          # Wait for Puma to bind.
        end

        sleep 0.05
      end
    end

    address = Socket.ip_address_list.find(&:ipv4_private?).ip_address
    @url = "http://#{address}:#{port}/"
    @wait = Selenium::WebDriver::Wait.new(timeout: 10)
    @image = create_image('red.png', 'red')
  end

  def browser(javascript: true)
    options = Selenium::WebDriver::Firefox::Options.new

    options.add_argument('-headless')
    options.add_option('se:downloadsEnabled', true)
    options.add_preference('javascript.enabled', javascript)
    options.add_preference('browser.helperApps.neverAsk.saveToDisk', 'application/zip')

    @driver = Selenium::WebDriver.for(:remote, url: ENV.fetch('SELENIUM_URL', 'http://selenium:4444/wd/hub'), options: options)
    @driver.file_detector = ->(args) { args.first if File.file?(args.first.to_s) }
    @driver.navigate.to(@url)

    @wait.until { element('form').attribute('data-ready') == 'true' } if javascript

    @driver
  end

  def element(selector)
    @driver.find_element(css: selector)
  end

  def selected_names
    @driver.execute_script('return Array.from(document.querySelector("[data-upload-target=imageInput]").files, file => file.name)')
  end

  def drop_files(*paths, on_panel: false)
    fixture = @driver.execute_script(<<~JS)
      const input = document.createElement("input");
      input.type = "file";
      input.multiple = true;
      input.hidden = true;
      document.body.append(input);
      return input;
    JS

    fixture.send_keys(paths.join("\n"))

    target = on_panel ? element('[data-action*="drop->upload#appendDroppedFiles"]') : element('[data-upload-target="imageInput"]')

    @driver.execute_script(<<~JS, target, fixture)
      const transfer = new DataTransfer();
      Array.from(arguments[1].files).forEach(file => transfer.items.add(file));
      arguments[0].dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: transfer }));
      arguments[0].dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: transfer }));
    JS

    selected_names
  ensure
    @driver.execute_script('arguments[0].remove()', fixture) if fixture
  end

  def teardown
    @driver&.quit

    if @pid
      Process.kill('TERM', @pid)
      Timeout.timeout(5) { Process.wait(@pid) }
    end

    super
  end

  def test_switching_previews_and_clearing_the_selection
    browser

    @driver.manage.window.resize_to(390, 844)

    FileUtils.mkdir_p('tmp/screenshots')

    @driver.save_screenshot('tmp/screenshots/form-mobile.png')

    assert_operator @driver.execute_script('return document.styleSheets[0].cssRules.length'), :>, 0
    assert @driver.execute_script('return document.documentElement.scrollWidth <= window.innerWidth')
    refute element('[data-upload-target="archive"]').displayed?

    @driver.execute_script('window.revoked = []; const revoke = URL.revokeObjectURL.bind(URL); URL.revokeObjectURL = url => { window.revoked.push(url); revoke(url); };')

    element('[data-upload-target="imageInput"]').send_keys(@image)

    @wait.until { @driver.find_elements(css: '[data-upload-target="previews"] img').length == 1 }

    assert_includes element('[data-upload-target="previews"]').text, 'red.png'
    assert element('[data-upload-target="clearButton"]').enabled?

    element('[data-upload-target="clearButton"]').click

    assert_equal 1, @driver.find_elements(css: '[data-upload-target="imageInput"]').length
    assert_equal '', element('[data-upload-target="imageInput"]').attribute('value')
    assert_empty @driver.find_elements(css: '[data-upload-target="previews"] img')
    refute element('[data-upload-target="clearButton"]').enabled?
    assert_equal 1, @driver.execute_script('return window.revoked.length')

    element('[data-upload-target="imageInput"]').send_keys(@image)
    element('[value="archive"]').click

    refute element('[data-upload-target="images"]').displayed?
    refute element('[data-upload-target="imageInput"]').enabled?

    archive = File.join(@directory, 'images.zip')

    ArchiveCreator.new(@image).save(archive)

    element('#archive-file').send_keys(archive)

    assert_includes element('[data-upload-target="archiveName"]').text, 'images.zip'

    keys = @driver.execute_script('return Array.from(new FormData(document.querySelector("form")).keys())')

    refute_includes keys, 'image_files[]'

    element('[type="submit"]').click

    @wait.until { @driver.downloadable_files.include?('spritesheet.zip') }

    @driver.download_file('spritesheet.zip', @directory)

    Zip::File.open(File.join(@directory, 'spritesheet.zip')) { |zip| assert_equal %w[sprites.png sprites.css], zip.entries.map(&:name) }
  end

  def test_dropped_files_append_in_order_and_are_included_in_the_download
    browser

    element('[data-upload-target="imageInput"]').send_keys(@image)

    blue = create_image('blue.png', 'blue')
    green = create_image('green.png', 'green')
    yellow = create_image('yellow.png', 'yellow')

    assert_equal %w[red.png blue.png green.png], drop_files(blue, green)
    assert_equal %w[red.png blue.png green.png yellow.png], drop_files(yellow, on_panel: true)
    assert_equal 4, @driver.find_elements(css: '[data-upload-target="previews"] img').length

    element('[type="submit"]').click

    @wait.until { @driver.downloadable_files.include?('spritesheet.zip') }

    @driver.download_file('spritesheet.zip', @directory)

    Zip::File.open(File.join(@directory, 'spritesheet.zip')) do |zip|
      image_path = File.join(@directory, 'result.png')

      File.binwrite(image_path, zip.read('sprites.png'))

      image = MiniMagick::Image.new(image_path)

      assert_equal [16, 3], image.dimensions
      assert_equal [255, 0, 0], rgb_pixel(image, 0, 0)
      assert_equal [0, 0, 255], rgb_pixel(image, 4, 0)
      assert_equal [0, 128, 0], rgb_pixel(image, 8, 0)
      assert_equal [255, 255, 0], rgb_pixel(image, 12, 0)
    end
  end

  def test_removing_one_image_preserves_remaining_order_in_the_download
    browser

    element('[data-upload-target="imageInput"]').send_keys(@image)

    drop_files(create_image('blue.png', 'blue'), create_image('green.png', 'green'))

    element('[aria-label="Remove blue.png"]').click

    assert_equal %w[red.png green.png], selected_names
    assert_equal 2, @driver.find_elements(css: '[data-upload-target="previews"] img').length
    assert_equal 'Remove green.png', @driver.switch_to.active_element.attribute('aria-label')
    assert element('[data-upload-target="clearButton"]').enabled?

    element('[type="submit"]').click

    @wait.until { @driver.downloadable_files.include?('spritesheet.zip') }

    @driver.download_file('spritesheet.zip', @directory)

    Zip::File.open(File.join(@directory, 'spritesheet.zip')) do |zip|
      path = File.join(@directory, 'remaining.png')

      File.binwrite(path, zip.read('sprites.png'))

      image = MiniMagick::Image.new(path)

      assert_equal [8, 3], image.dimensions
      assert_equal [255, 0, 0], rgb_pixel(image, 0, 0)
      assert_equal [0, 128, 0], rgb_pixel(image, 4, 0)
    end
  end

  def test_removing_duplicate_and_final_image_clears_selection_and_releases_previews
    browser

    element('[data-upload-target="imageInput"]').send_keys(@image)

    drop_files(@image)

    @driver.execute_script('window.revoked = []; const revoke = URL.revokeObjectURL.bind(URL); URL.revokeObjectURL = url => { window.revoked.push(url); revoke(url); };')

    @driver.find_elements(css: '[data-action="upload#removeImage"]').first.click

    assert_equal ['red.png'], selected_names
    assert_equal 1, @driver.find_elements(css: '[data-action="upload#removeImage"]').length

    element('[data-action="upload#removeImage"]').click

    assert_empty selected_names
    assert_empty @driver.find_elements(css: '[data-upload-target="previews"] img')
    refute element('[data-upload-target="clearButton"]').enabled?
    assert_equal 'image-files', @driver.switch_to.active_element.attribute('id')
    assert_equal 3, @driver.execute_script('return window.revoked.length')
  end

  def test_browse_replaces_dropped_selection_and_clear_resets_errors
    browser

    input = element('[data-upload-target="imageInput"]')

    input.send_keys(@image)

    assert_equal %w[red.png blue.png], drop_files(create_image('blue.png', 'blue'))

    # WebDriver appends to multiple inputs by default; clearing before send_keys
    # emulates the replacement FileList supplied by a native Browse dialog.
    input.clear
    input.send_keys(create_image('green.png', 'green'))

    assert_equal ['green.png'], selected_names
    assert_equal 1, @driver.find_elements(css: '[data-upload-target="previews"] img').length
    refute_includes element('[data-upload-target="previews"]').text, 'red.png'

    bad = File.join(@directory, 'notes.txt')

    File.write(bad, 'not an image')

    drop_files(bad)

    element('[type="submit"]').click

    assert_includes element('[data-upload-target="error"]').text, 'Only PNG and static GIF'

    element('[data-upload-target="clearButton"]').click

    assert_empty selected_names
    assert_empty @driver.find_elements(css: '[data-upload-target="previews"] img')
    refute element('[data-upload-target="error"]').displayed?
  end

  def test_server_errors_preserve_options_and_mode_and_clear_file_inputs
    browser

    element('[value="archive"]').click

    bad = File.join(@directory, 'bad.zip')

    File.write(bad, 'broken')

    element('#archive-file').send_keys(bad)
    element('summary').click
    element('#columns').send_keys('2')
    element('#css-class').send_keys('icon')
    element('#css-prefix').send_keys('tile')
    element('[type="submit"]').click

    @wait.until { @driver.find_elements(css: '#server-error').any? }

    @wait.until { element('form').attribute('data-ready') == 'true' }

    assert_includes element('#server-error').text, 'Please select your files again.'
    assert_equal 'icon', element('#css-class').attribute('value')
    assert_equal 'tile', element('#css-prefix').attribute('value')
    assert_equal '2', element('#columns').attribute('value')
    assert element('[value="archive"]').selected?
    assert_equal '', element('#archive-file').attribute('value')
    assert_equal 'server-error', @driver.switch_to.active_element.attribute('id')
  end

  def test_client_validation_and_local_modules
    browser

    element('[type="submit"]').click

    assert_includes element('[data-upload-target="error"]').text, 'No file(s) selected.'
    assert_equal @url, @driver.current_url

    resources = @driver.execute_script('return performance.getEntriesByType("resource").map(resource => resource.name)')

    assert(resources.any? { |url| url.include?('stimulus-3.2.2.js?v=') })
    assert(resources.any? { |url| url.include?('upload_controller.js?v=') })
    assert(resources.all? { |url| url.start_with?(@url) })

    @driver.manage.window.resize_to(1280, 1000)

    @driver.execute_script('window.scrollTo(0, 0)')

    FileUtils.mkdir_p('tmp/screenshots')

    @driver.save_screenshot('tmp/screenshots/form.png')
  end

  def test_previews_release_object_urls_on_replacement_and_disconnect
    browser

    @driver.execute_script('window.revoked = []; const revoke = URL.revokeObjectURL.bind(URL); URL.revokeObjectURL = url => { window.revoked.push(url); revoke(url); };')

    input = element('[data-upload-target="imageInput"]')

    input.send_keys(@image)

    @wait.until { @driver.find_elements(css: '[data-upload-target="previews"] img').length == 1 }

    input.clear
    input.send_keys(create_image('blue.png', 'blue'))

    @wait.until { element('[data-upload-target="previews"]').text.include?('blue.png') }

    assert_equal 1, @driver.execute_script('return window.revoked.length')

    @driver.execute_script('document.querySelector("form").removeAttribute("data-controller")')

    @wait.until { @driver.execute_script('return window.revoked.length') == 2 }

    assert_equal 2, @driver.execute_script('return window.revoked.length')
  end

  def test_form_download_works_without_javascript
    browser(javascript: false)

    assert element('#archive-file').displayed?
    assert element('[data-upload-target="imageInput"]').displayed?

    element('[data-upload-target="imageInput"]').send_keys(@image)
    element('[type="submit"]').click

    @wait.until { @driver.downloadable_files.include?('spritesheet.zip') }

    @driver.download_file('spritesheet.zip', @directory)

    Zip::File.open(File.join(@directory, 'spritesheet.zip')) { |zip| assert_includes zip.read('sprites.css'), '.sprite.sprite-1' }
  end
end
