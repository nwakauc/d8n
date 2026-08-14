# Milestone 1 — Make the Build Safe

Outcome: supported dependencies, reproducible Linux builds, and no unintended
production upload surface.

## Tasks

### SB-01 — Upgrade the supported Ruby runtime

- Priority: P1
- Beta blocker: Yes
- Owner: Codex
- Status: Done
- Work: Move from the end-of-life Ruby 3.2.2 runtime to a supported version that
  is compatible with the selected Rails release and all locked native gems.
- Evidence: `.ruby-version`, Docker, CI, and development instructions agree;
  the full test, lint, Zeitwerk, Brakeman, and dependency-audit gates pass.
- Evidence recorded: Ruby 3.3.12 is pinned in `.ruby-version` and Docker and
  passed the complete local gates on 2026-08-14. CI consumes `.ruby-version`;
  the clean Linux/Docker proof is tracked separately by SB-04 and SB-05.

### SB-02 — Patch Rails/Active Storage and `json`

- Priority: P0
- Beta blocker: Yes
- Owner: Codex
- Status: Done
- Work: Upgrade off Active Storage 8.0.5 affected by CVE-2026-66066 and `json`
  2.20.0 affected by CVE-2026-71847, using the smallest compatible dependency
  update.
- Evidence: Updated lockfile; refreshed dependency audit has no applicable known
  vulnerability; full test and media/auth regression suites pass.
- Evidence recorded: Rails/Active Storage 8.1.3.1 and `json` 2.21.2 passed 286
  tests and a refreshed `ruby-advisory-db` audit with no vulnerabilities on
  2026-08-14.

### SB-03 — Close unused Rails upload routes

- Priority: P0
- Beta blocker: Yes
- Owner: Codex
- Status: Done
- Work: Disable or explicitly protect the default Active Storage direct-upload
  endpoint and keep development-only profile-photo functionality unavailable in
  production until Milestone 2's private-media boundary is complete.
- Evidence: Production-environment request tests prove anonymous callers cannot
  allocate blobs or obtain upload capability, and production refuses unsafe local
  upload behavior.
- Evidence recorded: Production disables generic Active Storage routes and the
  development profile-photo surface. Focused production/media/API-contract tests
  passed on 2026-08-14.

### SB-04 — Make the lockfile Linux-compatible

- Priority: P1
- Beta blocker: Yes
- Owner: Codex
- Status: In progress
- Work: Add the Linux Bundler platform used by CI and production without removing
  developers' supported local platforms.
- Evidence: A clean Linux dependency installation completes from `Gemfile.lock`.
- Evidence recorded: `x86_64-linux` is locked. A clean Linux install remains
  outstanding because the local Docker daemon was unavailable; CI now contains
  the required image-build gate.

### SB-05 — Prove Docker and CI from a clean checkout

- Priority: P1
- Beta blocker: Yes
- Owner: Codex
- Status: In progress
- Work: Build the production image in CI, use a pinned compatible PostgreSQL
  service, run the repository quality gates, and fail on build or scanner errors.
- Evidence: CI links showing image build, migrations, complete tests, RuboCop,
  Zeitwerk, Brakeman, and dependency audit passing from a clean checkout.
- Evidence recorded: CI now pins PostgreSQL 17, audits dependencies, and builds
  the production image. Local Docker verification was blocked because Docker
  Desktop's daemon was not running; a successful CI run is still required.

### SB-06 — Make the Brakeman gate reproducible

- Priority: P2
- Beta blocker: No
- Owner: Codex
- Status: Done
- Work: Stop the repository wrapper from failing solely because a newer Brakeman
  release exists while still keeping the scanner deliberately updated.
- Evidence: The documented local and CI commands run the lockfile version and
  return a meaningful result for the scanned codebase.
- Evidence recorded: `bin/brakeman --no-pager` now runs the lockfile scanner
  without an unrelated latest-version network gate and completed with zero
  warnings on 2026-08-14.

### SB-07 — Add a Rodauth password-burn compatibility regression

- Priority: P2
- Beta blocker: Yes
- Owner: Codex
- Status: Done
- Evidence: `domains/identity/password_engine.rb` currently calls the private
  `password_hash_match?` method through `send` in `PasswordEngine.burn`.
- Work: Add a direct regression test covering the dummy password burn used for
  timing-safe failure paths. Do not rewrite authentication.
- Completion evidence: The regression fails if the Rodauth integration disappears
  or changes incompatibly, and the focused plus full authentication tests pass.
- Evidence recorded: A direct `PasswordEngine.burn` compatibility regression and
  the full suite passed against Rodauth 2.45.0 on 2026-08-14.

### SB-08 — Investigate a supported Rodauth password-check API

- Priority: P2
- Beta blocker: No
- Owner: Codex
- Status: Done
- Evidence: `PasswordEngine.burn` depends on a method Rodauth does not expose as a
  public call at the current boundary.
- Work: Inspect the installed Rodauth version and official API for a supported
  equivalent. Prefer the public API if one exists. Otherwise isolate and document
  the version-coupled call and retain SB-07 as the compatibility alarm. Do not
  rewrite authentication merely to eliminate one private call.
- Completion evidence: The chosen boundary and version assumption are documented;
  the authentication suite passes.
- Evidence recorded: Rodauth 2.45.0 has public account-aware password validation
  but no public arbitrary-hash check suitable for the dummy burn. The private call
  remains isolated, documented, and protected by SB-07; no auth rewrite was made.
