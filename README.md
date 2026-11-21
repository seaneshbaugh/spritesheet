# Sprite Sheet Generator

Generates a spritesheet and corresponding CSS for a collection of images.

## Development

Docker and Docker Compose are the only host prerequisites.

```sh
docker compose build sinatra
docker compose up sinatra webpack
```

Open http://localhost:3000. The React/Webpack frontend is temporarily retained
while the Ruby runtime is modernized; its replacement is planned in TODO.md.
The application container uses Ruby 4.0.9 and ImageMagick 7.

## Tests

The Minitest suite runs entirely in the application container, including real
ImageMagick generation and ZIP round trips. It does not need the Webpack service.

```sh
docker compose run --rm --no-deps sinatra bundle exec rake test
```

The default Rake task also runs the suite. Dependencies are installed into a
named Docker volume. After changing Gemfile or Gemfile.lock, rebuild the image
and refresh an existing dependency volume:

```sh
docker compose build sinatra
docker compose run --rm --no-deps sinatra bundle install
```

Production and deployment modernization are planned separately; this Dockerfile
is for development and tests.

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
