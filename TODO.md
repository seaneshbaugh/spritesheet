# Spritesheet modernization plan

Planning baseline: November 11, 2026. This document proposes implementation
commits for review. Sections 1–5 have been implemented locally; no deployment changes
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

- [x] Centralize limits with documented defaults. Enforce the 32 MiB total for
  direct images and the actual decompressed image bytes from ZIP input. Browser
  validation is advisory; server checks are authoritative.
- [x] Enforce a 40 MiB total HTTP-body ceiling in Puma to allow multipart and
  archive overhead. Reject oversized declared-size and chunked requests before
  Rack parsing. Puma is the required server; do not duplicate body buffering in
  application middleware.
- [x] Bound actual total archive extraction, including irrelevant entries, and
  reject excessive entry counts. Choose and document operational guardrails in
  implementation; they must prevent tiny-file/directory floods without treating
  count as the user's primary product limit.
- [x] Validate ZIP paths before extraction: reject traversal, absolute paths,
  symlinks, collisions, and entries escaping the request directory. Handle nested
  directories and corrupt/encrypted archives deliberately. Count actual bytes
  while extracting rather than trusting archive size metadata.
- [x] Set ImageMagick memory, map, disk, thread, and time bounds and a command
  timeout. Compressed byte size alone does not bound decoded image memory. Set
  generous pixel/canvas guardrails and validate combined output dimensions before
  montage; document them as operational limits, not new feature requirements.
- [x] Keep only required PNG/GIF codecs enabled where practical. Remove Ghostscript
  and its fonts unless a demonstrated supported use requires them.
- [x] Own extraction files, generated output, and ImageMagick scratch files under
  an identifiable per-request temporary directory. Ensure MiniMagick-created
  copies and scratch files are included in cleanup, not just the final outputs.
- [x] Audit Rack multipart tempfile ownership and lifecycle, including parser
  failures, and ensure uploads are closed/unlinked through the supported cleanup
  mechanism. Verify behavior with a real server, not only mocked requests.
- [x] Clean up on success, validation failures, invalid images/ZIPs, failed
  ImageMagick commands, timeouts, and interrupted response delivery. If using a
  streaming/file response, tie cleanup to response-body closure so files remain
  available until consumption ends. Avoid an unbounded in-memory ZIP copy.
- [x] Log to stdout/stderr instead of accumulating application log files. Avoid
  logging upload bodies or unnecessary client filenames.
- [x] Add bounded tests proving actual byte enforcement, hostile ZIP rejection,
  cleanup after success/failure, and repeated requests without accumulating files.
  Include the exact limit boundary and an over-limit case without enormous fixtures.
- [x] Add boot-time cleanup of all contents of the service's dedicated temporary
  root, covering multipart uploads, request directories, and ImageMagick scratch
  files left after SIGKILL or host failure. Run once before Puma starts accepting
  requests, not on application reloads or individual worker starts. Use private
  per-instance storage so another running instance's files cannot be removed;
  never sweep shared /tmp or follow symlinks outside the owned root. Fail startup
  clearly if cleanup cannot complete.
- [x] Test startup with seeded abandoned files and verify the temporary root is
  empty before serving requests, unrelated files remain untouched, and cleanup
  failures prevent startup. Include a kill/restart recovery check.
- [x] Document that ensure blocks handle ordinary request cleanup, while startup
  cleanup handles crash leftovers on restart. Production ephemeral storage in
  commit 7 further limits persistence; an age-based cron remains deferred.

### Commit 3 verification (November 12, 2026)

Implemented a private request-workspace middleware for POST / with an immediately
registered Rack multipart tempfile factory. Other methods/routes bypass it; the
original request-body stream is passed through without copying or reading it.
ZIP output creation uses IO.copy_stream; HTTP delivery uses 64 KiB chunks. Response
closure owns workspace cleanup. Puma buffers use the private TMPDIR and enforce
40 MiB for both declared-size and chunked uploads before Rack receives them.
Application logs use container stdout/stderr.

Limits are centralized in config/processing_limits.rb: 32 MiB of image bytes,
40 MiB of total HTTP input and expanded archive content, 1,024 images, 2,048 ZIP
entries, 16 million pixels per image/output canvas, and 16,384 pixels per side.
ZIP names/types/collisions are checked before extraction; actual bytes are counted
while streaming, including ignored metadata. ImageMagick has an installed codec
and resource policy, per-command timeouts, and request-scoped scratch paths.

bin/server now locks and sweeps the dedicated runtime root before execing Puma.
The lifetime lock prevents another launcher from clearing an active server's
files. Cleanup never follows a symlink outside the owned root. Reloading the
application does not sweep; unsafe storage or cleanup errors prevent startup.
The lock and Puma PID are control files rather than abandoned upload data.

Verification:

- Docker image builds successfully with the ImageMagick policy installed.
- Dockerized Minitest after the November 16 simplification: 43 tests, 326
  assertions, no failures/errors/skips.
- The original section-three image also passed its full suite without source
  bind mounts.
- Real Puma tests verify successful downloads, malformed multipart cleanup,
  interrupted uploads, declared/chunked 413 responses, SIGKILL/restart recovery,
  preserved unrelated files, exclusive startup locking, and failed startup when
  cleanup cannot proceed. Tests also cover response-close cleanup on interrupted
  downloads, real ImageMagick errors/timeouts, sparse 32 MiB boundary checks,
  actual/forged ZIP expansion sizes, hostile paths/collisions/symlinks, pixel
  bounds, and the installed native codec restrictions.
- Ruby lint passes for 23 files; git diff --check passes. The previously noted
  upstream sinatra/config_file verbose warning remains unchanged.

November 16 refinement: restrict workspace creation to POST / and rely exclusively
on Puma for the HTTP-body ceiling. Removed application-level body spooling and
its duplicate limit checks. Middleware tests now verify bypassed requests create
no directories and upload streams/lengths pass through unchanged. Real Puma
declared-size and chunked overflow tests continue to pass.

README documents the operational limits and temporary-file ownership. Per-command
resource caps are not a combined per-container budget or a total request deadline;
production concurrency, tmpfs sizing, non-root image packaging, and Docker log
rotation remain in section 7 and deployment integration. No cron job or deployment
was added, and no Git commit was created for this section.

## Commit 4 — Replace React with server-rendered ERB and Stimulus

- [x] Render the complete multipart form in ERB so initial rendering and errors
  do not depend on React mounting. Keep the final download a normal form POST.
- [x] Vendor the pinned Stimulus module with provenance and license; load local
  controllers as native modules with no runtime CDN or Node requirement.
- [x] Implement image/archive switching with disabled inactive fields, a single
  multiple-file input, clear selection, append-on-drop, selected filenames,
  previews, and advanced-options disclosure.
- [x] Use valid, stable field names and IDs. Prefer an ordered image_files[]
  parameter array and update server parsing/tests accordingly. Avoid hashing dates.
- [x] Revoke preview object URLs on replacement/removal/disconnect. Handle removing
  the final image by retaining or recreating an empty usable row.
- [x] Preserve non-file options after validation errors and explain when files
  must be selected again. Browsers cannot repopulate file inputs.
- [x] Add labels, keyboard-operable buttons, sensible input types/accept values,
  accessible error announcements, and a basic usable form without JavaScript.
- [x] Show supported formats, equal-dimension/static-GIF restrictions, and the
  32 MiB aggregate limit. Keep client checks aligned with server messages.
- [x] Verify rendered multipart names with request tests and manually exercise
  switching, previews, clearing/replacing/appending files, error recovery, and a downloaded ZIP.

## Commit 5 — Adopt Tailwind and remove the legacy asset toolchain

- [x] Add current compatible tailwindcss-ruby and plain CSS input. Provide explicit
  build/watch commands suitable for Sinatra rather than adding tailwindcss-rails.
- [x] Scan ERB, helpers, and Stimulus source deliberately. Keep complete utility
  names visible to Tailwind and ensure generated sprite CSS is not processed as
  application styling.
- [x] Recreate a small responsive interface with Tailwind, retaining useful
  identity/background attribution where applicable. No extensive redesign is needed.
- [x] Link the compiled CSS explicitly in the layout and test production output.
  Define a simple cache-versioning approach for local JS and compiled CSS.
- [x] Add bin/dev and Procfile.dev with Puma and a Tailwind watcher. Ensure the
  watcher survives noninteractive Docker use and both processes stop cleanly.
- [x] Reduce development Compose to one web service plus named dependency cache.
  Standardize the application port setting and document watcher/reload behavior.
- [x] Remove assets/package.json, yarn.lock, Webpack configuration, JSX, Sass,
  Dockerfile.webpack, webpack helper/settings, React-related dependencies, and
  obsolete public Bootstrap/jQuery assets after checking references.
- [x] Verify clean checkout startup, CSS rebuilds after template edits, local
  module loading, and a minified production CSS build without Node/Yarn/Sass.

### Sections 4 and 5 verification (November 21, 2026)

Implemented together because the existing Webpack container could not start and
both sections replace the same frontend/build boundary. The form is now ERB with
ordered image_files[] uploads and a local Stimulus controller. It supports mode
switching, disabled inactive fields, a multiple-file input, clear selection, filenames,
previews, object-URL release, native advanced-options disclosure, advisory byte
checks, and normal browser ZIP downloads. Server errors preserve escaped non-file
options and upload mode, explain file reselection, and receive accessible focus.
Without JavaScript both input sections remain usable, with native multiple-image
selection and server validation.

Tailwind 4.3.4 runs through tailwindcss-ruby; source is plain CSS with explicit
ERB/helper/controller scanning. The old React, Webpack/Babel, Materialize, Sass,
Node/Yarn lockfiles/configuration, Bootstrap/jQuery, and unused font files are
removed. Stimulus 3.2.2 is vendored with its MIT license, source provenance, package
integrity verification, SHA-256 checksums, and upgrade instructions. A shared
content digest versions local stylesheet/JavaScript/import-map URLs. No runtime
CDN or host Node/Ruby installation is needed. The original background and license
attribution are retained with a modest responsive form refresh.

Normal development now uses the single web service. bin/dev builds CSS before
Foreman starts Puma and the noninteractive Tailwind watcher from Procfile.dev.
Docker images also build minified CSS. Browser checks use an optional Selenium
profile and test-only Ruby client; they do not run in the default fast suite.
That small portion of section 6 was brought forward to verify the frontend change.

Verified:

- Docker build and clean image dependency installation, including the standalone
  Tailwind CLI, succeed. An existing bundle volume can be refreshed with the
  documented Docker command.
- The request/processing suite passes: 46 tests, 363 assertions.
- Firefox passes: 5 tests, 39 assertions, including actual ZIP downloads with
  and without JavaScript, mode switching, image previews, selection cleanup,
  labels/IDs, option recovery, local versioned modules, mobile
  layout, and object-URL release on replacement/removal/disconnect.
- The running CSS watcher rebuilds after a source edit without a TTY.
- The running web service serves the form successfully. Foreman shuts down both
  Puma and the watcher gracefully; the container exits with status 0 and restarts.
- Ruby lint and git diff --check pass. README documents migration, build/watch,
  cache refresh, and ordinary/browser test commands. Screenshots are available
  under ignored tmp/screenshots/.

The old project Sinatra/Webpack development containers were replaced with web;
old images and volumes were not deleted. No production deployment or Git commit
was performed. CI, broader lint configuration/dependency audits, and production
packaging remain in later sections.

### Image selection refinement (November 22, 2026)

Removed the redundant image-row controls and template/partial. The form now has
one native multiple-file input and a Clear image selection button. Browse uses
the browser's replacement selection; file drops on the input or surrounding panel
append to the actual FileList, preserving existing order followed by dropped
order. Clearing resets the file input, previews, and client error and revokes
preview URLs. Native multipart submission and the no-JavaScript fallback remain.

Verified through test:all in Docker: 46 regular tests / 368 assertions and 7
Firefox tests / 60 assertions, all passing. Browser coverage checks input and
panel drops, multiple/repeated drops, Browse replacement, clearing, object-URL
cleanup, and actual generated sprite pixels in appended order. Ruby lint and
git diff --check pass.

Per-image removal follow-up: each preview now has a compact light-red Remove
button beneath its filename. It removes by selection index (including duplicate
names), preserves remaining order, revokes replaced preview URLs, and moves focus
to the next Remove button or the file input. Removing the final file also disables
the clear-all button. Firefox suite: 9 tests / 76 assertions pass, including actual
ZIP pixels after middle-image removal and duplicate/final-image cleanup. Ruby lint
and git diff --check pass.

## Commit 6 — Add containerized browser checks and CI

- [x] Add a small Selenium browser suite using Minitest. Use a Compose
  system-test profile, following wishlist, so browsers are not installed on the host.
- [x] Configure the test app's reachable bind address, remote browser URL, and
  allowed test hosts. Keep browser fixtures and temporary downloads isolated.
- [x] Cover image/archive switching, filename/preview changes, adding/removing
  the final row, advanced options, and validation recovery. Confirm the successful
  ZIP response through request tests and a real-browser download check if reliable.
- [x] Keep model/request tests fast and independent of Selenium; provide separate
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
- [ ] Wire the boot cleanup from commit 3 into the production entrypoint before
  starting Puma. Ensure uploads and ImageMagick scratch files use the same private
  temporary root, and verify crash/restart cleanup under the unprivileged runtime
  user, including when the container writable filesystem survives a restart.
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
- Additional formats, richer previews, sorting/reordering, and any
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
