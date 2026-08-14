# Kamal Deploy, Failure, And Rollback Runbook

## Current deployment boundary

Staging uses Kamal with separate `web` and `job` roles. The image entrypoint runs
`bin/rails db:prepare` before a web server starts. Therefore a successful image
rollback does **not** roll back schema changes: a new migration may already have
committed before the new container became healthy.

Until this is rehearsed, deploy only additive, backward-compatible migrations.
Use expand/contract changes across releases; do not combine destructive column or
table removal with the release that stops using it.

## Pre-deploy record

For every staging or future production deploy, record:

- operator, UTC time, destination, Git/image version, and previous live version;
- clean quality-gate result and migration list;
- backup timestamp/checksum when the release changes schema;
- whether old and new code are mutually compatible with the resulting schema;
- stop condition and expected smoke checks.

`kamal config` may reveal combined secrets and must not be pasted into tickets,
logs, or chat.

## Smoke sequence

After a deploy, verify in order:

1. `bundle exec kamal app version -d staging` reports the intended version.
2. `GET /up` returns success.
3. `GET /api/v1/health` returns `200` with both database checks `ok`.
4. The `web` and `job` roles are present in `kamal details -d staging`.
5. A bounded authenticated smoke flow works.
6. A smoke job is processed by the worker, and failed-job count did not grow
   unexpectedly.

Do not use a high-concurrency load test as a deploy smoke check.

## Application rollback

If the schema remains backward-compatible, identify an existing image from the
audit/images output and run:

```sh
bundle exec kamal audit -d staging
bundle exec kamal app images -d staging
bundle exec kamal rollback PREVIOUS_VERSION -d staging
```

Repeat the smoke sequence. Record the exact version and outcome. Never guess a
version or use an unreviewed image tag.

If old code is incompatible with the migrated schema, do not run a blind image
rollback. Put the application in maintenance mode if necessary, stop the worker
role to prevent more side effects, and choose between a forward fix and the
separately rehearsed database recovery procedure. Do not improvise a migration
`down` against production during an incident.

## Worker and external failure

- For a poison/retrying job, stop only the `job` role with
  `bundle exec kamal app stop -r job -d staging`; keep web available where safe.
- Do not delete failed queue rows until the job's side effect and idempotency state
  are understood.
- For R2 failure, disable new media operations, retain database authorization
  state, and reconcile jobs after storage recovers. Never fall back to local disk.
- For primary PostgreSQL failure, stop writes and follow the backup/restore
  runbook. For queue-only failure, web may remain available for flows that do not
  promise asynchronous delivery, but readiness should remain degraded.

## Rehearsal still required

This document does not prove rollback. DR-07 remains open until a dated staging
exercise records a normal rolling deploy, web/worker replacement, a rollback to a
known compatible image, a failed deploy, and the schema boundary observed in each
case. Production deployment remains founder-approved work.

