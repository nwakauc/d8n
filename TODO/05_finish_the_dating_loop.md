# Milestone 5 — Finish the Dating Loop

Outcome: a controlled HookUs user can complete the real product journey from
registration through a safe text conversation.

> **Reconciliation (2026-08-17):** DL-01/DL-02 are *proof/QA* tasks, not build
> tasks — profile, publication, safe photos, discovery (For You + New Here +
> filters), likes, passes, and canonical matching are all implemented and
> unit/concurrency-tested; what remains is the staging end-to-end proof. **DL-03
> (persisted text messaging) is the one genuine unbuilt product gap** — no
> `Message` model or endpoint exists; conversations are metadata-only. DL-03 is the
> highest-priority NOW item in `docs/FOUNDER-HQ/D8N_NOW_NEXT_LATER.md`.

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
- Owner: Claude
- Status: In progress (IMPLEMENTED + TESTED; not yet STAGING-PROVEN)
- Work: Follow ADR 0010 Slice 2: bounded text only, opaque public IDs,
  persistence-before-delivery, idempotent client sends, stable cursor pagination,
  sender/participant authorization, and polling first. Do not add attachments,
  reactions, typing indicators, presence, search, or WebSockets.
- Evidence: Request and concurrency tests prove authorization, ordering,
  idempotency, pagination, match lifecycle behavior, block/suspension enforcement,
  report evidence access, and absence of message bodies from logs/analytics/errors.
- Evidence recorded (2026-08-17): `messages` table (tenant-safe composite FKs to
  conversations + profiles, partial cursor index), `Message` model (plain text,
  `MAX_BODY_LENGTH` 2000, soft-delete column for future erasure). Endpoints
  `GET/POST /api/v1/conversations/:conversation_id/messages`. Authorization reuses
  `Messaging::MatchAccess` via new `Messaging::ConversationAccess` (participant +
  active match + availability + both block directions), so outsiders/cross-brand/
  blocked/suspended all get neutral 404 `conversation_unavailable`. Newest-first,
  signed brand+viewer+conversation-bound `MessageCursor`; body NFC-normalized,
  blank/oversized rejected, Unicode preserved; content added to
  `filter_parameters`. Conversation list now carries a last-message preview via one
  batched `DISTINCT ON` query. 18 request tests incl. the full like→match→converse
  loop; OpenAPI updated (`listMessages`/`sendMessage` + schemas). All gates green.
- **Deferred beyond this beta subset (report, do not silently skip):** ADR 0010
  Slice 2 also listed **per-participant read state**, **send throttling/abuse
  limits**, **message-reporting evidence handoff**, and **retention/export/
  soft-deletion/legal-erasure** as ship-together items. Per the founder DL-03
  ticket these are intentionally out of this slice: read receipts are explicitly
  excluded; message-reporting is TS-02 remainder; erasure ties to TS-06; message
  rate-limiting is an early-beta safety follow-up (no reusable app-wide limiter
  exists yet). Reading an ended-but-unblocked match returns unavailable rather than
  read-only history, because the only current path to `ended` is a block (which
  must hide history). These need founder acknowledgement or an ADR 0010 update.
- Remaining before Done: staging two-user proof (folded into DL-04).

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
