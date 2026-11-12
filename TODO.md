# Spritesheet modernization plan

Planning baseline: November 11, 2026. This document proposes implementation
commits for review. Commits 1 and 2 have been implemented locally; no deployment changes
have been made. Checkboxes track completed work and remaining verification.

## Agreed direction

- Keep Sinatra, with ERB rendering and Stimulus for form interactions. Do not add Turbo.
- Replace Materialize and Sass with Tailwind CSS. Remove React, Webpack, Babel,
  Node Sass, and dependencies needed only by that stack.
- Retain PNG and static GIF inputs and a ZIP download containing PNG and CSS.
  Animated GIF support and mixed-dimension image layouts are future features.
- Allow at most 32 MiB (33,554,432 bytes) of image data per job. This interprets
  “32 MB” as MiB; show that unit consistently in documentation and UI.
- Prioritize reliable cleanup now. Defer a production cleanup cron job.
- Use Docker for development and all tests; no host Ruby, Node, ImageMagick, or
  browser installation should be required.
- Follow wishlist's development/production split and conventions where useful,
  without bringing over Rails, database, worker, or persistent-storage machinery.
- Plan deployment integration separately in dynamic_sites. Actual deployment is
  a later operational step, after review and successful verification.

## Findings and technical approach

The current app has GET / and POST /, three processing classes, and a small React
form. It uses Ruby 2.6.5, Sinatra 2.0.7, MiniMagick 4.9.5, rubyzip 2.0.0, Puma
4.2.0, ActiveSupport 6.0.0, Webpack 4, React 16, and Node 12. No test suite exists.

Current published targets checked during planning are Ruby 4.0.9, Sinatra 4.2.1,
MiniMagick 5.4.0, and rubyzip 3.7.0. Recheck all direct and transitive dependencies
when implementing, choose stable releases, resolve them together, and commit the
resulting lockfile. These numbers are a starting point rather than a guarantee of
runtime compatibility. Update Puma, Bundler, RuboCop, and remaining tools too.

Use tailwindcss-ruby's standalone CLI rather than the Rails integration. Invoke
it through small build/watch scripts and compile plain CSS into public assets.
Tailwind generates utilities discovered in source files; keep complete class
names in ERB/JavaScript rather than constructing fragments dynamically.

Serve a pinned, locally vendored Stimulus ES module and application controllers
from public assets using native browser modules. Record the upstream version,
license, checksum, and update procedure. This avoids a JavaScript bundler and
runtime CDN dependency; a small static import map is sufficient if useful.

Existing defects to fix include the CSS reference to spritesheet.png when the
archive contains sprites.png, the obsolete ERB constructor, unsupported/empty
input crashes, malformed image field names, unstable React IDs, broken removal
of the last image, and the missing selected archive filename. The production
Webpack/CSS build path is also inconsistent; replace it rather than repair it.

The deployment checkout is /home/bungo/Projects/dynamic_sites, not
/home/Projects/dynamic_sites. Its spritesheet service and Nginx inclusion are
commented out. The standalone wishlist checkout is the primary configuration
reference; deployment submodules can be stale and must be checked before use.

## Commit 1 — Establish a current Ruby runtime and Docker test foundation

- [x] Update .ruby-version, Gemfile, lockfile, and Docker Ruby version together.
  Resolve current stable Sinatra/sinatra-contrib, Puma, MiniMagick, rubyzip,
  Bundler, and development dependencies. Add explicit standard-library gems
  where required by current Ruby rather than relying on incidental loading.
- [x] Replace Dockerfile.sinatra with a development Dockerfile based on a
  supported Ruby slim image, following wishlist. Install ImageMagick and only
  the native build/runtime packages this application needs. Verify ImageMagick
  version and MiniMagick command compatibility inside the container.
- [x] Initially retain the old frontend service if needed to keep this commit
  reviewable; its removal belongs to commit 5. Do not spend effort upgrading it.
- [x] Add a named bundle cache, explicit working directory, port/bind settings,
  and init handling. Create writable temporary directories at startup as needed.
- [x] Add .dockerignore excluding credentials, tooling directories, Git metadata,
  logs, temporary files, node_modules, and generated artifacts.
- [x] Replace the positional ERB.new arguments and migrate MiniMagick calls to
  its current API. Audit rubyzip major-version changes and current Rack behavior.
- [x] Make boot dependencies explicit and reusable by tests. Load the development
  reloader only in development; avoid requiring production-only boot through tests.
- [x] Remove unused sinatra/json and replace ActiveSupport convenience methods
  with ordinary Ruby where practical, allowing removal of active_support/all.
  Retain sinatra-contrib only for features still used.
- [x] Add Minitest, Rack::Test, Rake tasks, test helper, and small generated or
  checked-in image fixtures. Keep test dependencies out of production.
- [x] Add initial passing tests for GET /, basic image/CSS generation, and ZIP
  creation using real ImageMagick. Characterize working behavior without
  encoding known defects as desired behavior.
- [x] Verify a clean Docker build, application boot, and containerized test task.
  Record the exact resolved versions and any compatibility decisions.

### Commit 1 verification

Implemented and verified locally; no deployment was performed. Resolved Ruby 4.0.9, Bundler
4.0.20, Sinatra/sinatra-contrib 4.2.1, Puma 8.0.2, MiniMagick 5.4.0, rubyzip
3.7.0, Rack 3.2.8, RuboCop 1.92.2, Minitest 6.1.0, Rack::Test 2.3.0, and
Rake 13.4.2. The development image uses Debian slim and ImageMagick 7; explicitly
install/select DejaVu Sans because montage has no default font in this image.
Rubyzip extraction now uses destination_directory, and the generated response
uses the Rack-compatible content_type helper. ActiveSupport is removed;
sinatra-contrib remains for config loading and development reloading.

Verified:

- `docker compose build sinatra` completed successfully.
- `docker compose run --rm --no-deps sinatra bundle exec rake test` passed.
- The built image also passed the suite without mounts: 5 tests, 32 assertions.
- A real Puma process in the built image returned HTTP 200 for GET / and shut
  down gracefully; no host port or long-lived container was needed.
- Production-mode boot succeeded without loading Sinatra::Reloader.
- `git diff --check` passed.

The tests exercise real image generation, CSS positions, binary ZIP round trips,
direct uploads, and archive uploads. Rake's verbose Ruby warnings expose an
upstream sinatra/config_file delegated-method redefinition warning; normal boot
and all tests pass. The old Webpack frontend was retained and was not built or
browser-tested in this step. Existing output/validation defects remain scheduled
for commit 2; this is not yet the production-ready modernization.

## Commit 2 — Define supported inputs and correct generated output

- [x] Separate request parsing/validation from orchestration sufficiently to test
  it without introducing a large framework or unnecessary abstractions.
- [x] Define unambiguous image-versus-archive input behavior. Reject conflicting
  inputs and malformed parameter shapes with a useful validation response.
- [x] Validate actual decoded image formats as well as filename extensions;
  normalize extension case. Support PNG and single-frame GIF only for this phase.
- [x] Reject animated GIFs and unequal image dimensions with clear messages for
  now. Do not silently discard frames or promise mixed-size layout correctness.
  Document these as provisional baseline restrictions, with future support below.
- [x] Reject empty uploads, empty ZIPs, and archives containing no usable images.
  Define handling of unrelated archive entries: ignore harmless non-image files
  and __MACOSX metadata; report corrupt files claiming to be supported images.
- [x] Preserve direct-upload order and archive entry order for now; document the
  numbering rule rather than adding a new sorting feature.
- [x] Validate columns and CSS class/prefix options, retaining defaults of five
  columns and sprite. Reject malformed values and identifiers that become empty
  or invalid rather than emitting unusable CSS.
- [x] Keep spritesheet.zip as the download name and sprites.png/sprites.css as
  members. Correct the CSS image URL to sprites.png and use application/zip.
- [x] Escape displayed errors and user-controlled strings in ERB explicitly.
  Return deliberate 422 statuses for invalid content and avoid exposing exceptions.
- [x] Add regression tests for output filenames, transparency, dimensions,
  sprite numbering, columns, CSS coordinates, PNG/static GIF, and invalid inputs.
  Assert pixels/geometry where useful rather than merely stubbing ImageMagick.

### Commit 2 verification

Implemented request parsing in UploadRequest and shared 422 validation errors.
ImageMagick identify checks format, dimensions, and frame count without making
MiniMagick temporary copies; processing errors receive readable validation
messages. CSS generation reuses validated dimensions. Nested ZIP directories
are supported and non-image entries are excluded from image processing.
Basic entry-type/path checks accompany nested extraction; comprehensive archive
bounds and extraction safeguards remain in commit 3.

Verified with `docker compose run --rm --no-deps sinatra bundle exec rake test`:
20 tests, 183 assertions, zero failures/errors. Coverage includes actual sprite
pixels/order and CSS coordinates, transparency, PNG/static GIF, uppercase
extensions, malformed/conflicting uploads, invalid options, blank defaults,
invalid/empty/encrypted ZIPs, nested folders and metadata, animation/mixed-size
rejection, correct ZIP/CSS filenames and content type, and escaped 422 errors.
README documents the supported input/output contract and ordering. Dockerized
RuboCop lint passed for all eight changed Ruby files; `git diff --check` passed.

## Commit 3 — Bound upload processing and guarantee temporary-file cleanup

- [ ] Centralize limits with documented defaults. Enforce the 32 MiB total for
  direct images and the actual decompressed image bytes from ZIP input. Browser
  validation is advisory; server checks are authoritative.
- [ ] Use a separate proposed 40 MiB total HTTP-body ceiling to allow multipart
  and archive overhead. Reject oversized bodies early, including requests without
  a trustworthy Content-Length. Do not use Content-Length as the sole check.
- [ ] Bound actual total archive extraction, including irrelevant entries, and
  reject excessive entry counts. Choose and document operational guardrails in
  implementation; they must prevent tiny-file/directory floods without treating
  count as the user's primary product limit.
- [ ] Validate ZIP paths before extraction: reject traversal, absolute paths,
  symlinks, collisions, and entries escaping the request directory. Handle nested
  directories and corrupt/encrypted archives deliberately. Count actual bytes
  while extracting rather than trusting archive size metadata.
- [ ] Set ImageMagick memory, map, disk, thread, and time bounds and a command
  timeout. Compressed byte size alone does not bound decoded image memory. Set
  generous pixel/canvas guardrails and validate combined output dimensions before
  montage; document them as operational limits, not new feature requirements.
- [ ] Keep only required PNG/GIF codecs enabled where practical. Remove Ghostscript
  and its fonts unless a demonstrated supported use requires them.
- [ ] Own extraction files, generated output, and ImageMagick scratch files under
  an identifiable per-request temporary directory. Ensure MiniMagick-created
  copies and scratch files are included in cleanup, not just the final outputs.
- [ ] Audit Rack multipart tempfile ownership and lifecycle, including parser
  failures, and ensure uploads are closed/unlinked through the supported cleanup
  mechanism. Verify behavior with a real server, not only mocked requests.
- [ ] Clean up on success, validation failures, invalid images/ZIPs, failed
  ImageMagick commands, timeouts, and interrupted response delivery. If using a
  streaming/file response, tie cleanup to response-body closure so files remain
  available until consumption ends. Avoid an unbounded in-memory ZIP copy.
- [ ] Log to stdout/stderr instead of accumulating application log files. Avoid
  logging upload bodies or unnecessary client filenames.
- [ ] Add bounded tests proving actual byte enforcement, hostile ZIP rejection,
  cleanup after success/failure, and repeated requests without accumulating files.
  Include the exact limit boundary and an over-limit case without enormous fixtures.
- [ ] Document that ensure blocks cannot clean up after SIGKILL or host failure.
  Production ephemeral storage in commit 7 limits persistence; an age-based cron
  remains a deferred additional measure rather than a prerequisite for cleanup.

## Commit 4 — Replace React with server-rendered ERB and Stimulus

- [ ] Render the complete multipart form in ERB so initial rendering and errors
  do not depend on React mounting. Keep the final download a normal form POST.
- [ ] Vendor the pinned Stimulus module with provenance and license; load local
  controllers as native modules with no runtime CDN or Node requirement.
- [ ] Implement image/archive switching with disabled inactive fields, add/remove
  image rows, selected filenames, previews, and advanced-options disclosure.
- [ ] Use valid, stable field names and IDs. Prefer an ordered image_files[]
  parameter array and update server parsing/tests accordingly. Avoid hashing dates.
- [ ] Revoke preview object URLs on replacement/removal/disconnect. Handle removing
  the final image by retaining or recreating an empty usable row.
- [ ] Preserve non-file options after validation errors and explain when files
  must be selected again. Browsers cannot repopulate file inputs.
- [ ] Add labels, keyboard-operable buttons, sensible input types/accept values,
  accessible error announcements, and a basic usable form without JavaScript.
- [ ] Show supported formats, equal-dimension/static-GIF restrictions, and the
  32 MiB aggregate limit. Keep client checks aligned with server messages.
- [ ] Verify rendered multipart names with request tests and manually exercise
  switching, previews, row removal, error recovery, and a downloaded ZIP.

## Commit 5 — Adopt Tailwind and remove the legacy asset toolchain

- [ ] Add current compatible tailwindcss-ruby and plain CSS input. Provide explicit
  build/watch commands suitable for Sinatra rather than adding tailwindcss-rails.
- [ ] Scan ERB, helpers, and Stimulus source deliberately. Keep complete utility
  names visible to Tailwind and ensure generated sprite CSS is not processed as
  application styling.
- [ ] Recreate a small responsive interface with Tailwind, retaining useful
  identity/background attribution where applicable. No extensive redesign is needed.
- [ ] Link the compiled CSS explicitly in the layout and test production output.
  Define a simple cache-versioning approach for local JS and compiled CSS.
- [ ] Add bin/dev and Procfile.dev with Puma and a Tailwind watcher. Ensure the
  watcher survives noninteractive Docker use and both processes stop cleanly.
- [ ] Reduce development Compose to one web service plus named dependency cache.
  Standardize the application port setting and document watcher/reload behavior.
- [ ] Remove assets/package.json, yarn.lock, Webpack configuration, JSX, Sass,
  Dockerfile.webpack, webpack helper/settings, React-related dependencies, and
  obsolete public Bootstrap/jQuery assets after checking references.
- [ ] Verify clean checkout startup, CSS rebuilds after template edits, local
  module loading, and a minified production CSS build without Node/Yarn/Sass.

## Commit 6 — Add containerized browser checks and CI

- [ ] Add a small Capybara/Selenium browser suite using Minitest. Use a Compose
  system-test profile, following wishlist, so browsers are not installed on the host.
- [ ] Configure the test app's reachable bind address, remote browser URL, and
  allowed test hosts. Keep browser fixtures and temporary downloads isolated.
- [ ] Cover image/archive switching, filename/preview changes, adding/removing
  the final row, advanced options, and validation recovery. Confirm the successful
  ZIP response through request tests and a real-browser download check if reliable.
- [ ] Keep model/request tests fast and independent of Selenium; provide separate
  commands for the default suite and system suite, plus a command for both.
- [ ] Proposed default: add GitHub Actions to build the Docker image and run the
  same containerized test commands. This was not explicitly selected in the reply;
  omit CI if repository review determines it is unwanted, without blocking local tests.
- [ ] Add current RuboCop configuration scoped to this small Sinatra app and run
  lint plus a dependency vulnerability audit inside Docker. Resolve material findings.
- [ ] Verify CI/container networking, cleanup, failure exit codes, and browser
  artifacts. Avoid tests that only reproduce implementation details.

## Commit 7 — Package a minimal production container

- [ ] Add Dockerfile.production using wishlist's multi-stage approach. Build gems
  and Tailwind CSS in build stages; copy only runtime dependencies/assets into the
  final image. Use a supported OS/Ruby combination verified for the target CPU.
- [ ] Exclude development/test gems and compilers from runtime. Run as an
  unprivileged user and start Puma directly rather than Foreman or a CSS watcher.
- [ ] Add GET /up as a lightweight readiness route and configure production host
  authorization for spritesheet.seaneshbaugh.com and health probes. Retain appropriate
  Rack protection; remove obsolete blanket exceptions only after request checks.
- [ ] Serve compiled assets through Sinatra/Puma to keep this stateless service
  self-contained; no Nginx public-directory copy or shared asset volume is necessary.
- [ ] Configure writable temporary storage explicitly. Propose a size-bounded
  tmpfs for uploads and scratch files, with memory/concurrency settings sized to
  the droplet alongside the Rails apps. Verify that the chosen size accommodates
  a valid 32 MiB job, expanded pixels, output ZIP, and concurrent requests.
- [ ] Limit processing concurrency conservatively; reconcile Puma thread counts,
  ImageMagick limits, and container memory so multiple uploads cannot exhaust the
  host. Measure a representative large job before finalizing numeric defaults.
- [ ] Verify non-root startup, readiness, static assets, real generation/download,
  stdout logs, graceful shutdown, temp cleanup, and restart with no retained uploads.
  Confirm runtime works without development bind mounts or dependency caches.

## Commit 8 — Integrate deployment in dynamic_sites (separate repository)

These are proposed changes outside this repository, not instructions to deploy
now. Reading access has been granted; implementation scope can be reviewed with
the plan before editing the deployment repository.

- [ ] Update the spritesheet submodule revision to the reviewed implementation.
- [ ] Replace the old config/spritesheet/Dockerfile build path with the application's
  Dockerfile.production using sites/spritesheet as its build context.
- [ ] Enable a single spritesheet service on the internal Docker network. Add
  restart/init behavior, healthcheck, graceful shutdown, bounded Docker logs,
  temporary storage and resource settings consistent with current wishlist services.
  Do not add a database, worker, host upload volume, or public Puma port.
- [ ] Restore the spritesheet Nginx virtual host in the active user_conf.d layout.
  Remove stale filesystem root/log assumptions, proxy assets and app traffic,
  preserve HTTPS/proxy headers, and configure request size/timeouts consistently
  with the 40 MiB proposed body ceiling and application processing timeout.
- [ ] Check current certificate/domain coverage and proxy startup behavior. Avoid
  breaking wishlist/portfolio when the spritesheet upstream is unavailable.
- [ ] Validate Compose configuration and Nginx configuration without printing
  expanded secret values. Build the image and exercise proxy/upload limits in an
  isolated configuration before any production restart.
- [ ] Document a targeted build/recreate procedure, readiness and ZIP smoke checks,
  previous-image/submodule rollback steps, and what changes require rebuilding Nginx.
  Actual droplet deployment remains a separately initiated step.

## Commit 9 — Document the final workflow and operational boundaries

- [ ] Update README with prerequisites (Docker/Compose), first build/start, default
  tests, system tests, lint/audit, production image build, and dependency updates.
- [ ] Document input formats, equal dimensions/static GIF scope, ordering, option
  defaults, output filenames, and byte/request/processing limits with their units.
- [ ] Document temporary-file ownership, stdout/Docker log rotation, bounded scratch
  storage, shutdown behavior, and remaining crash-cleanup limitations.
- [ ] Explain how to update the vendored Stimulus module and rebuild Tailwind;
  host Ruby/Node installs and runtime CDN connections are unnecessary.
- [ ] Run the documented commands from a clean Docker environment. Record final
  verification results and known limitations; update this checklist accurately.

## Deferred follow-ups

- Animated GIF handling with an explicit frame/animation/output contract.
- Mixed image dimensions with tested packing and matching CSS coordinates.
- An age-based production cleanup job for abandoned request directories. Design it
  around a dedicated prefix/root and active-job protection; never broadly sweep /tmp.
- Additional formats, richer previews, drag-and-drop, sorting/reordering, and any
  background processing only when an actual usage need justifies them.

## Sources checked during planning

- [Ruby downloads](https://www.ruby-lang.org/en/downloads/)
- [Sinatra versions/dependencies](https://rubygems.org/gems/sinatra)
- [Sinatra documentation](https://sinatrarb.com/intro.html)
- [MiniMagick releases](https://rubygems.org/gems/mini_magick) and
  [API documentation](https://github.com/minimagick/minimagick)
- [rubyzip releases](https://rubygems.org/gems/rubyzip)
- [Tailwind source detection](https://tailwindcss.com/docs/detecting-classes-in-source-files)
- [Standalone Tailwind Ruby wrapper](https://github.com/flavorjones/tailwindcss-ruby)
- [Stimulus installation](https://stimulus.hotwired.dev/handbook/installing)
