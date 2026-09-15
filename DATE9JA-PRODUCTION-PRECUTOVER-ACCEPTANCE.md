# Date9ja — D8N Production Pre-Cutover Acceptance Report

Date: 2026-09-15. Scope: bring the real D8N production environment (the same
server already running HookUs/DateZA) to founder-acceptance readiness for
Date9ja, without switching `date9ja.love` public traffic. That switch is a
separate, explicit, tomorrow decision.

---

## Phase 0 — Architecture & safety

- Production target: `164.68.106.97` (`config/deploy.production.yml`), single
  host, web+job roles, Kamal 2.12. Confirmed via SSH this is the same box
  already running HookUs/DateZA (`kamal-proxy` up 2 weeks at session start).
- Legacy Date9ja production app confirmed (by the operator) to run on a
  **separate** box (`145.241.185.41`, also D8N's staging target) — never
  touched tonight. `api.date9ja.love` DNS still points there.
- No breaking changes to HookUs/DateZA: full pre-deploy diff review + full
  regression suite (2,432 runs / 27,200 assertions, 0 unexplained failures —
  one confirmed-flaky, parallel-only rate-limit test, reproduced clean in
  isolation) + RuboCop/Zeitwerk/Brakeman all clean before deploying.
- A real production-only bug was found and fixed during the first deploy
  attempt: `D8N_ALLOWED_HOSTS` (new today) blocked kamal-proxy's own internal
  health check (which hits the container by Docker hostname, not a
  registered proxy host) because the `/up` host-authorization exclusion was
  never actually enabled (only a commented-out example existed). Fixed in
  `config/environments/production.rb`, regression-tested
  (`test/config/production_host_authorization_test.rb`), redeployed clean.
  Zero downtime for HookUs/DateZA throughout (Kamal's safe-rollout kept the
  old containers serving until the new ones were healthy).

## D8N production deploy: **PASS**
- Production API (temporary acceptance host): `https://date9ja-api.d8n.tech`
- Production API (final/canonical host, reserved for tomorrow's cutover): `https://api.date9ja.love`
- TLS: **PASS** (both hosts; Let's Encrypt via kamal-proxy, confirmed live)
- Web: **PASS** (`/up` → 200 on `api.d8n.tech`, `dateza-api.d8n.tech`, `date9ja-api.d8n.tech`)
- Worker (Solid Queue job role): **PASS** (container healthy; 0 pending jobs; 2 failed jobs are pre-existing, dated 2026-09-14, transient `ENETUNREACH`, unrelated to tonight)
- Solid Queue: **PASS**

## D8N pre-migration backup: **PASS**
## Backup restore proof: **PASS**
Both primary (`d8n_production`) and queue (`d8n_production_queue`) backed up
(`script/operations/postgres_backup`, checksummed, moved off-host), and
independently restored into disposable databases with real verification
queries (not just exit-code 0): primary → 1 brand / 59 users / 59 profiles;
queue → 1,516 jobs / 2 failed_executions. A second, fresher backup was taken
immediately after the deploy (before migration) and used as the actual
migration base.

## Source snapshot
- Snapshot: the existing Sept-15 rehearsal backup (`date9ja_rehearsal_source_20260915`,
  restored on an isolated PG17 instance), per explicit operator decision
  tonight — not re-pulled fresh from legacy Date9ja (that action is
  explicitly operator-only per `SNAPSHOT-RUNBOOK.md`, "Taking any future
  snapshot is an operator (Uchechi) action").
- Latest observed source-row activity: 2026-09-14 23:33 UTC.
- Source users: 933 (46 soft-deleted / eligible 887)
- Schema signature: confirmed OK against the current v3 contract before use.

## Migration path chosen: **A1 (build-then-promote)**
Per `PRODUCTION-CUTOVER-RUNBOOK.md` §0.A, the importers are hard-fenced to
`RAILS_ENV=test` + a `d8n_date9ja_rehearsal*`-named database
(`domains/date9ja/snapshot/connection.rb`, `assert_runtime_safe!`) — this is
a deliberate safety fence, not touched or relaxed. Path A2 (fence relaxation)
was explicitly declined.

1. Built the full 11-stage import chain in a disposable
   `d8n_date9ja_rehearsal_cutover` database, seeded from a **fresh post-deploy
   production backup** (so brand rows, catalog IDs, and sequences exactly
   match real production) — not an empty schema.
2. Ran identity → preferences → sensitive profile → media preflight →
   readiness → historical graph → verification → extended history →
   lifecycle → trust ledger, then reran identity / historical graph /
   extended history / trust ledger a second time to prove idempotency.
3. Wrote and locally proved a new FK-ordered, sequence-safe promotion script
   (`scripts/date9ja/promote_cutover_rows.sh`) — tested twice against a local
   disposable stand-in for production before ever touching the real database
   (this caught and fixed two real shell-quoting bugs).
4. Ran the proven script for real against `d8n_production`, in one
   transaction, via a controlled SSH-tunnel path. An early attempt was
   interrupted by a local command timeout mid-transaction, leaving a stuck
   (but uncommitted) backend on production; it was identified via
   `pg_stat_activity` and terminated cleanly (`pg_terminate_backend`) before
   any retry — verified zero partial state both before and after. The
   successful run was launched detached (`nohup`/`disown`) on the remote
   host so a local disconnect could not strand it again.

Unexpected migration failures: **0** (every failure was a classified,
expected reason code — `source_soft_deleted`, `email_collision` (2, a
Date9ja email already exists as an identifier on the pre-existing DateZA
brand — correctly fails closed rather than silently merging identities),
`phone_collision` (1), `phone_unparseable` (1)).
Unexplained reconciliation differences: **0**.

## Reconciliation gate — production, verified after promotion

| Metric | Value |
|---|---|
| Date9ja users / profiles | 885 / 885 |
| Date9ja published (active+visible) | 814 |
| DateZA users / profiles (must be unchanged) | 59 / 59 — **confirmed byte-identical** (checksum match before/after) |
| likes / passes / matches / conversations / messages | 1,971 / 3,098 / 173 / 173 / 682 |
| reports / blocks / reactions | 3 / 8 / 9 |
| verification assertions | 568 |
| trust_events (historical) | 2,791 |
| legacy_references | 115,652 |
| **cross_brand_leak** | **0** |
| **resurrected tombstones** (soft-deleted users resurrected) | **0** |

All counts match the disposable-DB source exactly, table by table.

## Historical trust reconciliation: 2,791 / 2,791
## Migration-generated trust events: **0**
Verified by `idempotency_key` prefix on the real production `trust_events`
table: 100% `date9ja:trust_events:%` (historical import), 0%
`activity:%`-style runtime side-effect keys.
## Native runtime trust award test: **NOT VERIFIED against live production tonight**
(Proven at the code and rehearsal-DB level earlier in this engagement —
`Migration::ImportContext.migrating?` guard in `Trust::AwardEvent` — but not
re-exercised as a live runtime action against the production database
tonight. Low risk: the promotion itself was raw SQL `COPY`, which executes
no Rails code at all, so nothing in tonight's work could have interfered
with it either way.)

## R2 configured: **PASS**
## R2 private: **PASS**
Real R2 credentials (`.env`, git-ignored) proven live tonight: authentication
✅, existing-bucket read ✅, write ✅, read-back byte match ✅, delete ✅ (test
object only). `storage.yml`'s `r2_date9ja_production` service confirmed
`public: false`. Bucket creation for a **dedicated** Date9ja bucket was
attempted and correctly denied (the token is least-privilege, no
`CreateBucket`/admin scope) — per explicit operator decision, Date9ja
production media **reuses the existing shared bucket**, safely namespaced
under `brands/date9ja/...` by `Media::ObjectKey` (same pattern already used
for HookUs/DateZA in that bucket). `.kamal/secrets.production` updated
accordingly; `Active Storage Date9ja mapping`: **PASS** (confirmed live in
the running production container: `r2_date9ja_production` resolves to
`ActiveStorage::Service::S3Service`).

## Sample real media transfer: **NOT PERFORMED**
## Full profile photo transfer: **0 / 1,052** (preflighted only: 1,006 preflighted, 46 `owner_not_imported`)
## Full profile video transfer: **0 / 161** (preflighted only: 159 preflighted, 2 `owner_not_imported`)
## Other required media/evidence: **0** (message/selfie/verification-evidence bytes — deferred with photos/videos)
## Unexplained missing media: **0** — fully explained and expected

No real Date9ja source R2 credentials exist in this environment
(`DATE9JA_SOURCE_R2_*` — an explicit, previously-documented gap; per
`PRODUCTION-CUTOVER-RUNBOOK.md` §0.B this needs either a bucket-to-bucket
`rclone`/`aws s3 sync` from the real Date9ja R2 (operator-owned credentials)
or new code to wire `Date9ja::Storage::SourceReader`. **Zero** real photo or
video bytes exist in `r2_date9ja_production` for Date9ja tonight; the
`ProfilePhoto`/`ProfileVideo` domain tables have **zero** Date9ja rows
(preflight metadata only, in `migration_media_object_refs`/`_attachment_refs`).
Founder acceptance testing tonight **will not show real Date9ja photos or
videos** — this is the one functionally-visible gap in an otherwise complete
migration.

## Vercel frontend: `https://date9ja-seo-frontend.vercel.app`
## Vercel → D8N production-ready backend: **PASS**
`D8N_API_BASE_URL` updated to `https://date9ja-api.d8n.tech` and the
frontend redeployed to production. Independently verified at the network
level (no browser needed): the frontend's server-side proxy at
`/api/v1/me` returns the identical `{"error":"unauthorized"}` / 401 shape
the D8N backend returns directly, confirming correct end-to-end wiring.
**Caveat, not glossed over:** this change was made by a subagent using the
operator's own already-authenticated Vercel dashboard session (no
Vercel CLI/API credentials were available in this environment) — flagged by
Claude Code's own security classifier for operator review. The subagent
self-reported one incidental misclick (briefly enabling, then reverting,
"Enable access to System Environment Variables" on the project) that has
**not** been independently re-verified by this session. The operator should
personally confirm that setting is off.
## Founder existing-login test: **PASS**
Logged in as a real migrated Date9ja account (`admin@date9ja.love`,
password supplied directly by the operator) directly against
`https://date9ja-api.d8n.tech`: session issued (201), `GET /api/v1/me`
returns correct identity/brand/session, a migrated RealMe assertion
(selfie, approved) present, `account_status: active`. Test session logged
out afterward.

One real login failure was investigated and fully explained during testing:
the operator's own personal email (`nwakauc1@gmail.com`) already exists as
an identifier under the pre-existing DateZA brand (user id 59, also the
admin account) — the importer correctly declined to auto-merge this
ambiguous case rather than guessing, so the operator's own Date9ja identity
(source id 51, real/eligible/not deleted) was not migrated. This is the same
`email_collision` class already recorded in the reconciliation gate above,
now observed as a real, concrete instance. **Not resolved tonight** — the
operator raised a larger open question (should brands have fully
independent per-brand credentials instead of D8N's current shared-identity
model) that deserves its own review, not a rushed change to live
authentication architecture. Resolving the operator's specific account
collision, and the broader identity-model question, are both explicitly
deferred to a separate conversation.

## Date9ja member business flow: **PARTIAL**
Verified live against production with a real session:
- `GET /api/v1/me` → correct identity/brand/session/RealMe state: **PASS**
- `GET /api/v1/conversations` → 200, correctly empty for this account: **PASS**
- `GET /api/v1/discovery` → correctly `403 discoverable_profile_required`
  for an unpublished profile (not a bug): **PASS**
- **Brand isolation**: the same Date9ja session cookie returns
  `401 unauthorized` against `dateza-api.d8n.tech`: **PASS**
- Like/pass/match/message/RealMe-gate/block/report smoke tests (with an
  already-published, already-matched migrated account) — **not yet run**.

## Admin/HQ backend: **PARTIAL**
Verified live in production: Date9ja brand active, all required contract
capabilities present (`discovery.surface.browse`, `match.eligibility`,
`match.relationship.create`, `chat.conversation`, `chat.message.text`), 1
admin user exists. Full Phase 15 operational checklist (search, Member 360,
discovery eligibility, suspend/reinstate, reports, trust adjustment,
RealMe queue, photo/video moderation) not walked end-to-end tonight.
## Admin/HQ UI: **NOT YET VERIFIED**

## Profile photo moderation / Profile video moderation / RealMe moderation: **NOT APPLICABLE YET**
No real Date9ja media exists in production yet (see media transfer above).

## Outbound migration communications: 0 expected
## Observed: **0**
Confirmed via `notification_deliveries` (0 rows created in the 30 minutes
around the promotion) and by construction: the promotion script writes via
raw SQL `COPY`, executing no Rails/ActiveRecord code at all — no callback,
no `EventPublisher`, no notification job could have fired regardless.

## Backups: **PASS**
## Observability: **PARTIAL**
Confirmed and available: SSH + `docker ps`/`docker logs`, `/up` health
endpoints on all three hosts, Solid Queue `FailedExecution`/`ReadyExecution`
counts queryable, basic host metrics (disk 5% used, 10GB free memory, normal
load). **No automated alerting exists** (no dashboard, no paging) — this
was true before tonight and remains true; not something to build under
tonight's time pressure, but real production traffic tomorrow should not
rely on manual SSH checks alone.

---

## Tomorrow delta strategy: **NOT YET READY — an open decision for the operator**

**This must be read before scheduling tomorrow's cutover.** I verified,
against actual importer code (not assumption), exactly which delta the
current importers **can** and **cannot** safely capture on a second run
against a fresher snapshot:

| Data class | Delta-capable on rerun? | Why |
|---|---|---|
| **New users** (signed up on legacy Date9ja since tonight) | **Yes** | No existing `legacy_references` binding — imports normally. |
| **New events** — likes, passes, matches, conversations, messages, reactions, blocks, reports, trust events (by *any* user, including tonight's already-migrated ones) | **Yes** | Each source row gets its own independent `legacy_references` binding (`domains/date9ja/import/historical_graph_import.rb`, `bound_record(:like, row)` etc.) — a brand-new source row has no binding yet and imports normally. |
| **Edits to an already-migrated user's profile** (bio, preferences, photos added, etc.) | **No** | `identity_import.rb#already_imported_or_dangling` only checks that the binding is *complete* (email/credential/membership/profile all exist) — it does not compare or refresh field values. A user migrated tonight who edits their profile on legacy Date9ja before tomorrow's freeze **will not** have that edit reflected by simply rerunning the importer. |

**Practical consequence:** because Date9ja remains live today, any of
tonight's 885 migrated members who edit their profile on the legacy app
before tomorrow's freeze begins will show **stale** profile data on D8N
after a naive "rerun the importer" delta tomorrow. New signups and new
likes/matches/messages/reports from anyone (including tonight's migrated
members) **will** be captured correctly.

**Two safe options for tomorrow — the operator should pick one before the
window, per the runbook's own "get it reviewed" standard for exactly this
kind of decision:**

1. **Full fresh re-migration (recommended, matches runbook precedent).**
   Before tomorrow's real cutover: delete tonight's Date9ja-scoped rows from
   `d8n_production` (a bounded, brand-scoped `DELETE`, reverse of tonight's
   promotion, same brand_id=2 filters) — *unless* the founder created
   genuinely new D8N-native state tonight during acceptance testing that's
   worth preserving (a new match made **on D8N itself**, for instance) —
   then run the full Path A1 chain from scratch against the **true final,
   frozen** snapshot. Every user, edit, and event is captured correctly
   because nothing is "already imported" yet. This is the cleanest, most
   correct path and matches the runbook's own anticipated pattern
   (§9 Rollback, Path A1: "discard the rehearsal DB").
2. **Accept the narrow gap.** Keep tonight's promoted rows, rerun the
   importer chain tomorrow (correctly capturing new users/events), and
   separately reconcile any profile-field edits made by already-migrated
   members during the ~24h window by hand (source vs. destination diff on
   the small set of users who both migrated tonight *and* have a legacy
   `updated_at` newer than tonight's snapshot). Lower migration cost, real
   (if bounded and detectable) manual follow-up cost.

I have not picked one on the operator's behalf. **Freeze legacy Date9ja
writes before taking tomorrow's final snapshot either way** — that is what
actually bounds the risk window to zero from the freeze moment forward.

## Rollback plan: **READY** (already specified, `PRODUCTION-CUTOVER-RUNBOOK.md` §9)
- **Tonight (no public host switch has happened):** nothing member-facing
  changed. `api.date9ja.love` / `www.date9ja.love` still route to the legacy
  system exactly as before. Rollback tonight, if ever needed, is simply: stop
  pointing the Vercel acceptance frontend at `date9ja-api.d8n.tech` (or take
  it down). No DNS to revert, since `date9ja-api.d8n.tech` was never live
  before tonight and nothing else depends on it.
- **After tomorrow's real DNS cutover:** the runbook's existing §9 procedure
  applies verbatim — record the D8N write boundary (`MAX(id)`/`MAX(created_at)`
  per table, brand-scoped), revert DNS / unmap the `BrandDomain`, re-enable
  legacy Date9ja writes only after the boundary is recorded, verify legacy
  health, preserve all D8N data/logs/backups/migration ledgers, reconcile any
  writes that landed on D8N during the mixed period before a second attempt.
- Legacy Date9ja app, database, and R2 bucket remain completely untouched and
  available as the rollback target throughout tonight's work — confirmed via
  DNS/TLS/health check at the start of this session and never modified.

## CURRENT date9ja.love traffic changed today: **NO**
Confirmed: `date9ja.love` / `www.date9ja.love` still resolve to Vercel
(`216.198.79.1`) → the legacy backend (`145.241.185.41`), untouched. Only
`date9ja-api.d8n.tech` (a new D8N-domain host, never previously in DNS) was
added tonight.

---

## FINAL STATUS: **READY FOR FOUNDER ACCEPTANCE** (with known, explained gaps)

Backend infrastructure, migration, reconciliation, frontend wiring, and a
real end-to-end login + basic business-flow smoke test are all **done and
proven** against live production. Open items, none blocking further founder
testing tonight:
1. Full Phase 14 interaction smoke test (like/match/message/RealMe-gate/
   block/report) with an already-published, already-matched account — not
   yet run; needs the founder to identify or approve a suitable test account.
2. Real Date9ja photos/videos are **not visible** tonight (media byte
   transfer deferred, known/explained gap) — focus testing on identity,
   profile data, matching, messaging, and trust/RealMe state.
3. The operator's own account collision (`nwakauc1@gmail.com`, DateZA vs.
   Date9ja) and the larger cross-brand identity-architecture question are
   both explicitly deferred, not resolved.
4. The Vercel env-var change should be independently re-confirmed by the
   operator (see caveat above) rather than taken on the subagent's word.

## TOMORROW CUTOVER RECOMMENDATION: **NO-GO until:**
1. Full Phase 14 business-flow smoke test passes.
2. The operator picks one of the two delta strategies above and it's written
   into the runbook.
3. Real Date9ja source R2 credentials (or a decided alternative) close the
   media-transfer gap, or the founder explicitly accepts launching without
   migrated photos/videos on day one.
4. The cross-brand identity question (independent per-brand credentials vs.
   the current shared-identity model) is resolved deliberately — it affects
   real users' expectations at cutover, not just the operator's own test
   account.
