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
limits, including the planned 32 MiB image allowance, belong to the next TODO
section and are not enforced by this step yet.
