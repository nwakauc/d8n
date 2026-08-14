# Milestone 1 — Make the Build Safe

Outcome: supported dependencies, reproducible Linux builds, and no unintended
production upload surface.

## Tasks

### SB-01 — Upgrade the supported Ruby runtime

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Move from the end-of-life Ruby 3.2.2 runtime to a supported version that
  is compatible with the selected Rails release and all locked native gems.
- Evidence: `.ruby-version`, Docker, CI, and development instructions agree;
  the full test, lint, Zeitwerk, Brakeman, and dependency-audit gates pass.

### SB-02 — Patch Rails/Active Storage and `json`

- Priority: P0
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Upgrade off Active Storage 8.0.5 affected by CVE-2026-66066 and `json`
  2.20.0 affected by CVE-2026-71847, using the smallest compatible dependency
  update.
- Evidence: Updated lockfile; refreshed dependency audit has no applicable known
  vulnerability; full test and media/auth regression suites pass.

### SB-03 — Close unused Rails upload routes

- Priority: P0
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Disable or explicitly protect the default Active Storage direct-upload
  endpoint and keep development-only profile-photo functionality unavailable in
  production until Milestone 2's private-media boundary is complete.
- Evidence: Production-environment request tests prove anonymous callers cannot
  allocate blobs or obtain upload capability, and production refuses unsafe local
  upload behavior.

### SB-04 — Make the lockfile Linux-compatible

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Add the Linux Bundler platform used by CI and production without removing
  developers' supported local platforms.
- Evidence: A clean Linux dependency installation completes from `Gemfile.lock`.

### SB-05 — Prove Docker and CI from a clean checkout

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Build the production image in CI, use a pinned compatible PostgreSQL
  service, run the repository quality gates, and fail on build or scanner errors.
- Evidence: CI links showing image build, migrations, complete tests, RuboCop,
  Zeitwerk, Brakeman, and dependency audit passing from a clean checkout.

### SB-06 — Make the Brakeman gate reproducible

- Priority: P2
- Beta blocker: No
- Owner: Unassigned
- Status: Not started
- Work: Stop the repository wrapper from failing solely because a newer Brakeman
  release exists while still keeping the scanner deliberately updated.
- Evidence: The documented local and CI commands run the lockfile version and
  return a meaningful result for the scanned codebase.

### SB-07 — Add a Rodauth password-burn compatibility regression

- Priority: P2
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Evidence: `domains/identity/password_engine.rb` currently calls the private
  `password_hash_match?` method through `send` in `PasswordEngine.burn`.
- Work: Add a direct regression test covering the dummy password burn used for
  timing-safe failure paths. Do not rewrite authentication.
- Completion evidence: The regression fails if the Rodauth integration disappears
  or changes incompatibly, and the focused plus full authentication tests pass.

### SB-08 — Investigate a supported Rodauth password-check API

- Priority: P2
- Beta blocker: No
- Owner: Unassigned
- Status: Not started
- Evidence: `PasswordEngine.burn` depends on a method Rodauth does not expose as a
  public call at the current boundary.
- Work: Inspect the installed Rodauth version and official API for a supported
  equivalent. Prefer the public API if one exists. Otherwise isolate and document
  the version-coupled call and retain SB-07 as the compatibility alarm. Do not
  rewrite authentication merely to eliminate one private call.
- Completion evidence: The chosen boundary and version assumption are documented;
  the authentication suite passes.
