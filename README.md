# Sprite Sheet Generator

Generates a spritesheet and corresponding CSS for a collection of images.

## Development

Docker and Docker Compose are the only host prerequisites. Build the image,
refresh the named gem cache, and start the development service:

```sh
docker compose build web
docker compose run --rm --no-deps web bundle install
docker compose up -d --remove-orphans web
```

Open http://localhost:3000. `--remove-orphans` removes the old Sinatra/Webpack
containers when migrating from the previous setup; their images/volumes are not
deleted. Only the `web` service is needed for normal development.

`bin/dev` builds CSS before starting Puma and the Tailwind watcher through
`Procfile.dev`/Foreman. The watcher stays alive without a TTY. ERB templates and
Ruby helpers/models reload in development; Tailwind recompiles after source edits.
Refresh the browser to see changes, including versioned JavaScript modules.

After Gemfile or Gemfile.lock changes, repeat the build and `bundle install`
commands above, then recreate the web service. The container uses Ruby 4.0.9 and
ImageMagick 7. No host Ruby, Node, Yarn, Sass, or browser install is needed.

## Assets and form

The form is rendered by ERB. Stimulus adds mode switching, filenames,
previews, a clear-selection button, and advisory client validation. The single
image input accepts multiple files: Browse replaces the selection, while dropping
files onto the input or its surrounding panel appends them in drop order after
the existing files. Each preview has a Remove button for that individual file;
Clear image selection removes all files. Advanced options use native `details`.
Submission remains a normal multipart POST returning a ZIP. Without JavaScript,
both upload sections remain available: select files in only one section; the
native image chooser supports multiple files. Validation errors preserve options
and upload mode, but require selecting files again.

JavaScript uses native ES modules and an import map. Stimulus 3.2.2 is vendored
locally; source, license, checksums, and upgrade steps are recorded in
`public/js/vendor/README.txt`. There are no runtime CDN requests. A content digest
versions the stylesheet, entrypoint, and import-map module URLs together.

Tailwind's standalone CLI is supplied by `tailwindcss-ruby`, with plain CSS input
at `assets/stylesheets/app.css`. It scans the specified ERB templates, helpers,
and Stimulus controllers; keep utility class names as complete literals. Generated
sprite CSS is separate and is not included in Tailwind's scan. The application
CSS output is ignored by Git and compiled into Docker images or before dev/tests.

```sh
docker compose run --rm --no-deps web bin/css build  # minified build
```

This replaces React, Materialize, Webpack/Babel, Sass, and the Node/Yarn toolchain.
Production image packaging remains a later TODO section; start Puma directly with
`bin/server` after building assets when checking server-only operation.

## Tests

The default Minitest suite runs inside the application container, including real
ImageMagick generation, ZIP round trips, request tests, and Puma lifecycle checks.
It builds CSS automatically and does not start a browser.

```sh
docker compose run --rm --no-deps web bundle exec rake test
```

For real Firefox tests, start the optional Selenium profile, then run the separate
system suite. It starts an isolated Puma process inside the test container and
checks interactions, error recovery, downloads, mobile layout, object-URL cleanup,
and the no-JavaScript fallback. No host port is needed for the test app.

```sh
docker compose --profile system-test up -d --wait selenium
docker compose --profile system-test run --rm --no-deps web bundle exec rake test:system
# Or run both suites:
docker compose --profile system-test run --rm --no-deps web bundle exec rake test:all
docker compose stop selenium
```

Screenshots are saved under ignored `tmp/screenshots/`. If tests fail while
Selenium is unavailable, start it with the profile command above. Ordinary
application logs are available through `docker compose logs -f web`.

## Supported inputs and generated output

Upload PNG or single-frame GIF files, or a ZIP containing them. All images in a
job must have equal dimensions. Animated GIFs and mixed image sizes are deferred.
Filename extensions are case-insensitive and must match the actual image format.
Direct uploads with unsupported extensions are rejected. ZIPs may contain nested
folders; non-image files, directory entries, and `__MACOSX` metadata are ignored.
Corrupt files with PNG/GIF extensions cause validation errors, rather than being
silently skipped. Encrypted ZIPs are unsupported.

Choose images or an archive, not both. Sprites are numbered in direct-upload
submission order or ZIP entry order, without sorting filenames.

The download is `spritesheet.zip`, containing `sprites.png` and `sprites.css`.
Keep the two extracted files together so the CSS image URL resolves correctly.

Options default to five columns and CSS class `sprite`; the prefix defaults to
the chosen class. Columns must be a positive integer and are capped at the number
of images. Blank form options use their defaults. CSS names may contain ASCII
letters, digits, underscores, and hyphens, but cannot start with a digit or consist
of a lone hyphen. Names are validated rather than silently sanitized.

Invalid content returns HTTP 422 with a readable message. Upload-size and resource
limits are described below.

## Upload and processing limits

Limits are centralized in `config/processing_limits.rb` and enforced on the server.
MiB means 1,048,576 bytes; multipart overhead is separate from image data.

| Limit | Default |
| --- | --- |
| Total direct image bytes, or decompressed PNG/GIF bytes in a ZIP | 32 MiB |
| Entire HTTP request, including multipart/ZIP overhead | 40 MiB |
| Total decompressed ZIP content, including ignored files/metadata | 40 MiB |
| Images per job | 1,024 |
| ZIP entries, including directories and metadata | 2,048 |
| Pixels in each image and in the entire output canvas | 16 million each |
| Width/height of an image or the output canvas | 16,384 pixels |
| ImageMagick command timeout | 30 seconds per command |

ImageMagick also has policy limits of 128 MiB pixel-cache memory, 256 MiB mapped
cache, 256 MiB disk cache, and one processing thread per command. These are
per-command guardrails, not a combined container memory/storage budget or a total
request deadline. They can reject an expensive job below the 32 MiB upload limit.
Production concurrency, container memory, and bounded tmpfs sizing remain in
section 7. Compressed image bytes alone cannot predict decoded memory use.

The Docker image installs `config/imagemagick-policy.xml`. Only PNG/GIF image
codecs and the internal XC/INFO fixture/diagnostic coders are enabled; delegates
and filters are disabled. Ghostscript is not installed. Rebuild the image after
changing the policy. Changes to numeric limits must be reconciled with that
policy and the production reverse proxy when it is configured.

Puma rejects declared or chunked HTTP bodies over 40 MiB before Rack parses them.
Puma is the required HTTP server in development and production; the application
does not spool or recount the HTTP body. A replacement server would need equivalent
request-size enforcement. HTTP request overflow returns 413; image/extraction
and processing validation errors return 422. ZIP extraction counts actual bytes
as they are read instead of trusting the declared uncompressed sizes. Unsafe
paths, symlinks, duplicate/conflicting destinations, paths longer than 1,024
bytes, and nesting deeper than 16 components are rejected.

## Temporary storage and crash recovery

Always start the server through `bin/server` (the image's default command). It
creates a private, owned directory at `/tmp/spritesheet-runtime`, takes an
exclusive lifetime lock, and removes abandoned contents **before** starting Puma.
`SPRITESHEET_TMP_ROOT` may select another private `spritesheet-*` directory with
an existing real parent directory. Do not share it between instances or mount it
as shared storage. A second server using the same root fails before cleanup.
Unsafe storage or cleanup failures prevent startup rather than starting with
uncertain disk state. Application reloads and worker starts do not run the sweep.

Only `POST /` creates a request workspace containing multipart uploads, extracted
files, generated output, and ImageMagick scratch files. GETs, static assets, and
other routes bypass workspace handling. Rack's
multipart factory registers files immediately, so parser failures cannot leave
untracked handles. Workspaces are removed on errors or when the response body is
closed, including aborted downloads. ZIP creation and downloads use bounded
chunks instead of reading the entire generated files into Ruby memory.

Puma's pre-Rack upload buffers also use the private root via TMPDIR. On Linux it
unlinks those files immediately and closes them when the request finishes or the
client disconnects. Disk space is released when those handles close, including
when the process dies. A subsequent boot removes named leftovers from a killed
job. The `.lock` and running `puma.pid` files are control files, not abandoned
uploads; they may remain while the server is idle. There is no broad `/tmp` sweep.
A periodic cleanup job remains deferred.

Puma's upload buffers, multipart copies, expanded content, ImageMagick caches, output
PNG, and output ZIP can coexist. The 32 MiB input limit is **not** a 32 MiB limit
on total temporary storage; the production tmpfs budget must include those copies
and concurrent jobs. Logs now go to container stdout/stderr rather than growing
application log files. Docker log rotation will be configured with deployment.

The default test command includes real Puma tests using private Unix sockets
inside the test container. It checks upload/parse failures, client disconnects,
declared/chunked oversize rejection, startup locking, and kill/restart recovery.
It does not bind host ports or require host dependencies.
