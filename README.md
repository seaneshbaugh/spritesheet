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
