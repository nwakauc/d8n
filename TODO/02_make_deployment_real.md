# Milestone 2 — Make Deployment Real

Outcome: one intentionally small European deployment that is durable,
recoverable, observable, and capable of processing private media safely.

## Tasks

### DR-01 — Approve and document the beta topology

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Select the European hosting region/provider and document one Rails web
  process, one separate worker process, PostgreSQL, the chosen durable job
  backend, and private Cloudflare R2 storage. Do not size for speculative 10,000
  concurrent-user traffic.
- Evidence: Approved deployment diagram, service ownership, environment inventory,
  and monthly cost estimate. No credentials belong in the repository.

### DR-02 — Configure PostgreSQL and connection budgets

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Configure managed PostgreSQL, TLS, migrations during deploy, and explicit
  web/worker connection-pool budgets.
- Evidence: Staging deploy and migration rehearsal succeed; aggregate process
  pools remain below the database connection limit with documented headroom.

### DR-03 — Run durable background jobs in a separate worker

- Priority: P1
- Beta blocker: Yes
- Owner: Codex
- Status: In progress
- Work: Choose and fully wire one Rails-compatible durable queue. Remove or defer
  unused competing queue infrastructure instead of maintaining two patterns.
  Define bounded retries and idempotency for verification, notification, media,
  and deletion jobs.
- Evidence: A staging job survives a web restart and is completed by the worker;
  failed/retried jobs are visible; deployment runs web and worker separately.
- Evidence recorded: Solid Queue 1.4.0 is the sole retained Solid component. Its
  official schema/configuration and `bin/jobs` supervisor are installed,
  production Active Job uses the separate `queue` database, Puma does not run the
  supervisor, and the staging Kamal configuration defines a separate `job` role.
  The founder-reported enqueue/restart/perform rehearsal succeeded, and the
  queue database independently records `Infrastructure::SmokeTestJob` job 1 as
  created at 2026-08-14 04:30:20 UTC and finished at 04:30:20 UTC. A deliberate
  failed/retried-job visibility rehearsal remains outstanding before Done.

### DR-04 — Implement private R2 media storage and delivery

- Priority: P1
- Beta blocker: Yes
- Owner: Codex / Founder for provider setup and policy
- Status: In progress
- Work: Follow ADR 0011 with a deliberately small beta scope: private bucket,
  authorization, strict byte/type/dimension checks, verified decoding, safe image
  re-encoding, EXIF removal, moderation state, approved variants only, and durable
  deletion. Do not build a general-purpose media platform.
- Evidence: Production does not use app-local disk; tests cover spoofed/corrupt/
  oversized/EXIF-bearing uploads, cross-brand access, pending/rejected visibility,
  signed delivery, and purge retries.
- Evidence recorded: Rails now has a private, S3-compatible R2 service backed by
  the standard `aws-sdk-s3` adapter. Production selects it only when
  `D8N_R2_ENABLED=true` and refuses to boot if any required R2 setting is blank.
  Regression tests prove the default disabled state, fail-closed environment
  contract, R2 service selection, disabled generic Active Storage routes, and
  disabled unfinished profile-photo API. `docs/operations/private-media-storage.md`
  documents least-privilege setup and the rollback boundary. The staging Kamal
  destination (`d8n-staging-media`, public access disabled, bucket-scoped
  credential) is now deployed with `D8N_R2_ENABLED=true`, and the staging deploy
  carrying it is healthy with the API health check returning 200. A prior deploy
  failure caused by an `env.secret` list overriding `RAILS_MASTER_KEY` and
  `D8N_DATABASE_PASSWORD` was diagnosed and fixed, with regression coverage
  proving staging preserves both the base app secrets and the R2 secrets. Still
  outstanding before Done: the real end-to-end R2 object lifecycle
  (upload -> confirm object -> direct access blocked -> authorized retrieval ->
  purge -> object removed) has not been exercised, and processing, delivery, and
  purge gates remain unimplemented.

### DR-05 — Establish backups and prove one restore

- Priority: P1
- Beta blocker: Yes
- Owner: Codex / Founder for provider and recovery policy
- Status: In progress
- Work: Enable PostgreSQL backups and R2 lifecycle/deletion controls, then document
  the recovery owner and procedure.
- Evidence: A dated staging restore drill successfully recovers the database and
  verifies representative records. Record recovery time and gaps honestly.
- Evidence recorded: `script/operations/postgres_backup` creates owner-only
  custom-format PostgreSQL dumps and checksums without command-line credentials.
  `script/operations/postgres_restore_drill` only creates a new, explicitly
  confirmed `d8n_restore_*` database and never drops or overwrites a database.
  `docs/operations/postgres-backup-restore.md` separates primary, queue, and R2
  recovery and records the operator evidence required. A read-only local proof on
  2026-08-14 produced and checksum-verified a 156,466-byte PostgreSQL 16 custom
  archive with 420 catalogue entries; it also proved that a mismatched PostgreSQL
  14 client correctly fails and led to atomic partial-file cleanup. No off-host
  schedule or successful staging-like restore is claimed yet, so this remains In
  progress.

### DR-06 — Add minimum production observability

- Priority: P1
- Beta blocker: Yes
- Owner: Codex / Founder for provider selection
- Status: In progress
- Work: Configure error tracking, uptime checks, structured-enough application
  logs, and a small metric set: request failures/latency, database saturation,
  queue depth/failures, and media/provider failures. Exclude secrets, tokens,
  precise location, message bodies, and unnecessary PII.
- Evidence: Staging smoke errors and failed jobs produce actionable alerts; health
  checks distinguish web availability from dependency readiness where useful.
- Evidence recorded: `/up` remains a boot/liveness probe, while the documented
  `/api/v1/health` readiness endpoint now independently checks primary and queue
  PostgreSQL and returns bounded `200`/`503` responses without connection details.
  Request tests cover success, unknown brand hosts, and dependency degradation;
  the OpenAPI contract is updated. `docs/operations/observability.md` defines the
  deliberately small beta signal set and privacy boundary. No external tracker,
  uptime check, metrics backend, or alert-delivery exercise is claimed yet.

### DR-07 — Rehearse a rolling deploy and rollback

- Priority: P1
- Beta blocker: Yes
- Owner: Codex / Founder for staging execution
- Status: In progress
- Work: Exercise deploy, migration, worker restart, rollback, and secret rotation
  procedures in staging.
- Evidence: Dated runbook output records what worked, what failed, and the exact
  rollback boundary for schema changes.
- Evidence recorded: `docs/operations/deploy-rollback.md` records the actual Kamal
  web/job topology, verified Kamal 2.12 rollback/role commands, ordered smoke
  checks, worker/storage/database failure handling, and the critical fact that
  current web boot runs `db:prepare`, so image rollback never reverses a migration.
  No rolling deploy, rollback, failed-deploy, or secret-rotation drill was run in
  this pass; DR-07 remains In progress.
