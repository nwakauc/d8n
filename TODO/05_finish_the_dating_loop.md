# Milestone 5 — Finish the Dating Loop

Outcome: a controlled HookUs user can complete the real product journey from
registration through a safe text conversation.

## Tasks

### DL-01 — Prove profile and discovery readiness with safe photos

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Integrate Milestone 2 media states into profile completion/publication so
  only processed and approved photos count or appear. Preserve the existing
  tenant-safe discovery and matching boundaries.
- Evidence: End-to-end tests cover incomplete, pending, rejected, approved,
  suspended, blocked, and deleted profiles without exposing private location or
  media internals.

### DL-02 — Rehearse like-to-match correctness

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Validate existing like/pass/match behavior under concurrent requests and
  through the public API without redesigning matching.
- Evidence: Concurrency, idempotency, canonical-match, block, suspension, cursor,
  tenant-isolation, and query-bound tests pass in the release environment.

### DL-03 — Implement persisted text messaging

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Follow ADR 0010 Slice 2: bounded text only, opaque public IDs,
  persistence-before-delivery, idempotent client sends, stable cursor pagination,
  sender/participant authorization, and polling first. Do not add attachments,
  reactions, typing indicators, presence, search, or WebSockets.
- Evidence: Request and concurrency tests prove authorization, ordering,
  idempotency, pagination, match lifecycle behavior, block/suspension enforcement,
  report evidence access, and absence of message bodies from logs/analytics/errors.

### DL-04 — Run the complete two-user beta journey

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Exercise two users through register, verify/recover, create profile, upload
  safe photo, publish, discover, like, match, converse, block/report, admin review,
  enforcement, and account closure on staging.
- Evidence: A dated release checklist records the client/API version, test users,
  outcomes, discovered defects, and confirmation that no cross-brand or private
  data was exposed.

### DL-05 — Load and failure test the beta shape

- Priority: P1
- Beta blocker: Yes
- Owner: Codex
- Status: In progress
- Work: Test the expected controlled-beta workload plus reasonable headroom. Cover
  login/registration, discovery, likes/matches, polling messages, uploads, worker
  backlog, provider timeouts, web restart, and database pressure. Do not claim a
  guaranteed concurrency capacity from one synthetic run.
- Evidence: Document workload assumptions, p50/p95/p99 latency, error rate,
  database connections/slow queries, queue depth/retries, resource saturation,
  and the bottlenecks actually observed. Resolve safety/correctness failures and
  agree explicit beta limits for capacity issues.
- Evidence recorded: The 2026-08-14 staging baseline and query-plan investigation
  are recorded in `docs/performance/staging-capacity-2026-08-14.md`. The current
  two-core shared host saturates between 25 and 50 VUs; a candidate Hetzner run,
  messaging/media workload, failure tests, queue metrics, and explicit beta
  limits remain outstanding.

### DL-06 — Conduct the private-beta go/no-go review

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Review every beta blocker in this folder, operational runbooks, unresolved
  human decisions, and load-test evidence. Set invite count, geography, support
  coverage, moderation coverage, and rollback/stop conditions.
- Evidence: Founder/CTO records `Go` or `No go`, date, accepted residual risks,
  owners, and review date. An undocumented verbal acceptance is not completion.
