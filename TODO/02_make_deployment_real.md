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
  A real staging enqueue/restart/perform rehearsal remains outstanding.

### DR-04 — Implement private R2 media storage and delivery

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Follow ADR 0011 with a deliberately small beta scope: private bucket,
  authorization, strict byte/type/dimension checks, verified decoding, safe image
  re-encoding, EXIF removal, moderation state, approved variants only, and durable
  deletion. Do not build a general-purpose media platform.
- Evidence: Production does not use app-local disk; tests cover spoofed/corrupt/
  oversized/EXIF-bearing uploads, cross-brand access, pending/rejected visibility,
  signed delivery, and purge retries.

### DR-05 — Establish backups and prove one restore

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Enable PostgreSQL backups and R2 lifecycle/deletion controls, then document
  the recovery owner and procedure.
- Evidence: A dated staging restore drill successfully recovers the database and
  verifies representative records. Record recovery time and gaps honestly.

### DR-06 — Add minimum production observability

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Configure error tracking, uptime checks, structured-enough application
  logs, and a small metric set: request failures/latency, database saturation,
  queue depth/failures, and media/provider failures. Exclude secrets, tokens,
  precise location, message bodies, and unnecessary PII.
- Evidence: Staging smoke errors and failed jobs produce actionable alerts; health
  checks distinguish web availability from dependency readiness where useful.

### DR-07 — Rehearse a rolling deploy and rollback

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Exercise deploy, migration, worker restart, rollback, and secret rotation
  procedures in staging.
- Evidence: Dated runbook output records what worked, what failed, and the exact
  rollback boundary for schema changes.
