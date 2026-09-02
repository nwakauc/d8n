# D8N HQ — Implementation Roadmap

Status as of 2026-09-01: **ACTIVE DELIVERY / CANONICAL ROADMAP.** Phase 1 and Phase 2
backend work, plus the bounded Member Directory extension, are built, but neither product slice is accepted until its
frontend, security gates, and operational verification are complete.
Sequencing is derived from the dependency chains actually found in
CURRENT-STATE.md and ARCHITECTURE.md, not from the phase numbering in the
original product brief (which the brief itself said not to copy
verbatim).

## Why this order

Three hard dependency chains fell out of the audit:

1. **Nothing cross-brand can ship before the authorization boundary is
   decided** (SECURITY-AND-RBAC.md §2) — even a read-only "All D8N" view is a
   policy decision, not just an engineering task.
2. **Nothing release/deploy-correlated can ship before version stamping
   exists** (ARCHITECTURE.md §9) — nothing to correlate against yet.
3. **Nothing analytics/growth/retention-shaped can ship before the event
   pipeline exists** (ARCHITECTURE.md §3) — the data literally isn't
   captured yet. Trust & Safety, Member 360, and Brand Health, by
   contrast, need **no new instrumentation at all** — CURRENT-STATE.md
   confirms the underlying tables already exist and are already
   populated by the live product.

That third point is why the roadmap does not follow the brief's
suggested FOUNDATION → COMMAND CENTRE → OPERATIONS → OBSERVABILITY →
ANALYTICS → GROWTH → INTELLIGENCE ordering literally: Trust & Safety and
Brand/Member operations are *cheaper to ship correctly* than a real
Command Centre, because Command Centre's headline scores need either the
event pipeline (growth/product) or an observability vendor (system) to
be honest, non-fabricated numbers, while Trust & Safety and Member 360
need neither.

## Phase 0 — Decisions & prerequisites (no product code)

**Reconciled status (2026-09-01): PARTIAL.**

- **Option A authorization boundary: DONE** — ADR 0020 confirms explicit
  per-brand assignments/fan-out only; Founder and Super Admin do not
  bypass tenant isolation.
- **HQ-001 release identity: DONE (code), OPERATIONAL VERIFICATION
  OUTSTANDING** — the image bakes git SHA/build time and
  `GET /api/v1/version` exposes release/environment identity. Staging must
  still prove the deployed 40-character SHA.
- **Admin MFA launch gate: DONE (backend), OPERATIONAL VERIFICATION
  OUTSTANDING** — ADR 0021 implements encrypted TOTP, recovery codes,
  session step-up, throttled/audited failures, and reset. Founder staging/
  production enrollment remains a human gate.
- **Differentiated RBAC foundation: DONE** — ADR 0020 implements the role/
  capability trigger anticipated by ADR 0013 and the original Phase 10
  plan, plus brand-scoped operator management.
- **Observability vendor decision: OUTSTANDING** — still required only
  before Phase 3/HQ-010, which has not started.

**Objective:** resolve the handful of things that block everything else,
before writing HQ application code.

- Founder/security decision: SECURITY-AND-RBAC.md §2 — Option A (fan-out,
  no new cross-brand grant) is now recorded in ADR 0020 for V1.
- Founder decision: observability vendor (ARCHITECTURE.md §4) — needed
  before Phase 3 (Observability), not before Phase 1/2, but the earlier
  it's picked the cheaper it is to instrument new code with it from day
  one rather than retrofitting.
- Engineering: add version/release stamping (ARCHITECTURE.md §9) — built,
  standalone, unblocks Phase 4 (Deployment Intelligence) and every
  release-correlated metric later. Backend ticket: **HQ-001**.
- Engineering: admin MFA — backend built; staging/production enrollment
  and acceptance remain the restated pre-launch gate (SECURITY-AND-RBAC.md),
  not HQ-specific work, but its priority is raised by this plan and it
  should land before Phase 2 ships anything beyond read-only views.

**Acceptance criteria:** Option A is confirmed in ADR 0020; still
outstanding operationally, `/api/v1/version` must return the real deployed
git SHA in staging and the Founder/operator session must complete MFA and
role/isolation acceptance.

**What becomes usable:** nothing user-facing yet. This phase de-risks
everything after it.

## Phase 1 — Member 360 + admin read foundation (recommended first slice — see below)

**Reconciled status (2026-08-29): PARTIAL.**

- **Backend: DONE** — HQ-101 through HQ-107, the discovery diagnostic, and
  the bounded Member Directory extension
  are implemented and documented in `PHASE-1-IMPLEMENTATION.md` and
  `docs/api/openapi.yaml`.
- **Operations directory extension: DONE** — the explicitly requested
  brand-scoped `GET /api/v1/hq/members` directory is now available for the
  interim Operations console; it is a safe listing, not a new cross-brand
  authority model or signup notification stream.
- **Operations analytics extension: DONE** — `GET /api/v1/hq/analytics/overview`
  exposes only server-computed metrics derivable from current memberships,
  profiles, and sessions. This does not pull the Phase 5 AnalyticsEvent
  pipeline forward.
- **Enforcement controls: PARTIAL** — brand-scoped suspension existed; the
  foundation now distinguishes suspension/ban creation from reinstatement,
  records operator notes, and exposes audited security alerts. Frontend
  actions and production acceptance remain outstanding.
- **Frontend: IN PROGRESS** — HQ-F01 through HQ-F04 are being implemented
  from the documented contract.
- **Security gates: BACKEND PASSED / OPERATIONAL ACCEPTANCE OUTSTANDING** —
  capability RBAC and mandatory admin MFA are implemented. Founder upgrade/
  enrollment and staging role/tenant verification remain.
- **Operational verification: OUTSTANDING** — the backend is test-proven,
  but the agreed end-to-end operator acceptance criterion is not complete.

**Objective:** an operator can look up one member, on one brand, and see
their real state — identity, profile, product activity, safety history —
without a Rails console.

**Backend work:**
- `Hq::Identity::Lookup` — resolve a member by email/phone/public_id
  (closes CURRENT-STATE.md #1.2, the single highest-leverage gap found).
- `Hq::Member360::Load` — aggregation service per ARCHITECTURE.md §6,
  reading existing tables only.
- Read API over `SecurityEvent`/`AuthAttempt` for one member (closes
  #3.5/#3.6, scoped to a single member, not a general audit browser yet).
- Read API over `AccountEnforcement` history for one member (closes
  #4.8).
- New `api/v1/hq/` namespace, authorized via existing
  `Admin::AuthorizationContext` with explicit capabilities (no new auth mechanism).
- Every new read logs a `SecurityEvent` per SECURITY-AND-RBAC.md §4 (sensitive-read
  auditing).

**Frontend work:** a single search box → Member 360 page with the six
sections from ARCHITECTURE.md §6 (Identity/Profile/Product/Comms/Safety/
Activity), each section collapsible, "why is Discover empty" as one
expandable card if time allows (can slip to Phase 2 without blocking).

**Data work:** none — this phase deliberately requires zero new tables
per CURRENT-STATE.md's findings.

**Observability work:** none yet (Phase 3).

**Security/RBAC work:** confirms SECURITY-AND-RBAC.md §3 step 1 in practice — ships
under the existing `moderator` role, no new role.

**Tests:** unit tests for `Hq::Identity::Lookup` and `Hq::Member360::Load`
per-section (mirroring this repo's existing `test/domains/` conventions);
an integration test proving a moderator on brand A cannot look up a
member's brand-B-only data (tenant isolation, this repo's existing
mandatory test category).

**Acceptance criteria:** an operator can find any HookUs or DateZA member
by email and see accurate profile/product/safety state, for a brand they
have an active `AdminAssignment` on, and nothing for a brand they don't.

**Dependencies:** Phase 0's Option A decision (confirms this is
single-brand-scoped, no fan-out yet needed for a single-member lookup).

**What becomes usable at completion:** the actual, daily-useful "look up
this user and see what's going on" tool — this alone replaces a large
share of today's Rails-console-driven support/moderation work.

## Phase 2 — Trust & Safety command surface

**Reconciled status (2026-08-29): PARTIAL.**

- **Backend: DONE** — brand-scoped Trust & Safety overview,
  repeat-offender aggregation, and brand-wide enforcement history are
  implemented. The existing admin report queue/detail/transition and
  suspension/reinstatement APIs remain the canonical moderation paths.
  See `PHASE-2-IMPLEMENTATION.md` and `docs/api/openapi.yaml`.
- Enforcement mutations remain capability-separated: Operations/Trust & Safety
  may create; Founder/Super Admin may reinstate or override.
- **Frontend: IN PROGRESS** — the Trust & Safety page described below is
  being implemented; the canonical roadmap did not assign it an HQ-Fxx ID.
- **Security gates: BACKEND PASSED / OPERATIONAL ACCEPTANCE OUTSTANDING** —
  the same capability/MFA foundation now protects this slice. Founder
  enrollment and staging role/tenant verification remain.
- **Operational verification: OUTSTANDING** — backend tests pass, but an
  operator has not yet satisfied the phase acceptance criterion through a
  verified frontend workflow.

**Objective:** the existing reports queue becomes a real command surface:
aging, repeat-offender visibility, enforcement history, all in one place,
brand-scoped.

**Backend work:** repeat-offender aggregation endpoint
(ARCHITECTURE.md §8), brand-wide enforcement history endpoint, "age of
oldest open report" + basic queue stats — all additive reads over
existing tables, no schema change.

**Frontend work:** Trust & Safety page: open/overdue counts, oldest-case
age, reports-by-type/brand breakdown, repeat-offender list, links into
Member 360 (Phase 1) for any member.

**Data/observability work:** none.

**Security/RBAC work:** none beyond Phase 1.

**Tests:** unit + tenant-isolation tests for the two new aggregation
queries.

**Acceptance criteria:** a moderator can answer "what's overdue" and
"who keeps getting reported" without a console query.

**Dependencies:** Phase 1 (links into Member 360).

**What becomes usable:** genuinely better moderation ops for the current
HookUs beta today, not a future capability.

## Phase 3 — System health / observability foundation

**Objective:** adopt an external observability vendor (Phase 0 decision)
and give HQ a first "is D8N healthy" view built on it, not hand-rolled.

**Backend work:** vendor SDK integration (errors + basic APM); extend
`/api/v1/health` into a fuller readiness check if the vendor doesn't
already cover it; wire `brand_id`/`user_id`/`request_id` as tags on every
captured error (ARCHITECTURE.md §4); a thin HQ read adapter over the
vendor's API for the small "top errors / error rate" card.
Backend ticket: **HQ-010**.

**Frontend work:** a System Health card on a not-yet-built Command
Centre stub (or standalone page) showing: deploy health (`/api/v1/health`
already exists), top errors (from vendor), queue depth (direct Solid
Queue table read per `docs/operations/observability.md`'s documented
pattern, wrapped in a real endpoint instead of manual SQL).

**Data work:** none new; this is instrumentation, not a new data model.

**Security/RBAC work:** vendor data-scrubbing configuration
(SECURITY-AND-RBAC.md §5).

**Tests:** smoke test that error capture reaches the vendor in a
non-prod environment; unit test for the queue-depth endpoint.

**Acceptance criteria:** a real error in staging shows up, correlated
with `brand_id`, in the vendor's UI and in a summarized HQ card — no
in-house tracing/log storage was built to get there.

**Dependencies:** Phase 0's vendor decision.

## Phase 4 — Deployment/release intelligence

**Objective:** "did the last deploy hurt the product" becomes answerable.

**Backend work:** propagate the version from Phase 0 (HQ-001) as a
`release` tag on captured errors (vendor, Phase 3) and, once it exists,
on `AnalyticsEvent` (Phase 5); simple before/after comparison endpoint
(error rate, and once available, key product metrics) keyed on release.

**Frontend work:** a Deployments page: list of recent releases (from
Kamal/GitHub, read via their APIs) with error-rate delta per release.

**Dependencies:** Phase 0 (HQ-001) and Phase 3 (vendor adopted).

**What becomes usable:** genuine deploy-risk visibility, still without
Company Intelligence or anomaly detection.

## Phase 5A — Bounded Founder Metrics & Command Centre foundation (implemented)

**Objective:** provide a trustworthy current health snapshot from existing
brand-scoped tables before introducing analytics instrumentation. The backend
layer is `Hq::Metrics::Catalog` + `Hq::Metrics::Compute`, with deterministic
attention signals and authorized multi-brand comparison at the two Command
Centre endpoints documented in `docs/api/openapi.yaml`.

**Current status:** DONE for the bounded backend foundation. Frontend and
staging/production operational acceptance remain outstanding. Time-to-first
interaction medians remain explicitly unavailable until a bounded rollup is
accepted; no scores are calculated.

## Phase 5 — Event pipeline + marketplace health + funnel

**Status (2026-09-01): PARTIAL — Phase 4 foundation delivered.**
`AnalyticsEvent`, the initial allowlisted event taxonomy, authoritative
registration/publication producers, bounded funnel, and daily trend APIs are
implemented. Onboarding completion, retention, full funnel backfill, and
rollups remain future slices.

**Remaining objective:** expand the canonical event system only where an
authoritative product transition cannot be derived from transactional tables,
then add scheduled rollups for mature historical cohorts.

**Backend work:** `AnalyticsEvent` table + `Hq::Analytics::Emit`;
instrument the ~15 highest-value existing call sites (registration,
onboarding steps, publish, discovery, like, match, conversation, message,
report); rollup jobs for DAU/WAU/MAU, marketplace health, funnel
conversion (METRICS.md registry entries, with tests).

**Frontend work:** Marketplace Health page, funnel visualization,
Growth-lite (whatever's derivable without acquisition data — i.e.
everything except cost-per-member/campaign economics, which stay
`NOT AVAILABLE`).

**Data/observability work:** the event pipeline itself; basic data-health
self-check (ARCHITECTURE.md §11) — ingestion lag, dedup rate — ships
alongside it, not bolted on later, since this is the first phase where
there's anything to self-monitor.

**Security/RBAC work:** none beyond existing per-brand scoping.

**Dependencies:** Phase 0 (release tagging is nice-to-have on events, not
blocking); genuinely independent of Phases 1–4 otherwise and could run in
parallel with them if resourcing allows.

**What becomes usable:** the first real Growth/Product score inputs;
still not Revenue (no billing exists) or true acquisition-channel
Growth (no attribution exists) — those stay `NOT CONFIGURED`.

## Phase 6A — Goals & Performance Scoreboard (future design)

**Status (2026-09-01): DOCUMENTATION ONLY / NOT STARTED.** The design is
captured in [GOALS-AND-PERFORMANCE-SCOREBOARD.md](GOALS-AND-PERFORMANCE-SCOREBOARD.md).
No goal model, route, migration, or score evaluation code exists yet.

**Objective:** let Founder HQ compare actual performance with explicitly
configured, direction-aware targets without inventing metrics or business
scores.

**Backend work:** add a small brand-scoped goal model and immutable target
change history; extend the canonical metric registry with direction, supported
period, scope, and target-shape metadata; add MFA-protected goal CRUD and
performance/history reads; evaluate bounded daily/weekly/monthly/yearly
periods using deterministic, versioned status rules.

**Dependencies:** Product Intelligence metric IDs and historical availability;
founder approval of status thresholds and within-range pacing; explicit
company-scope authorization; existing Admin authorization, MFA, and audit
infrastructure.

**Acceptance:** target changes are actor-attributed and auditable; brand
isolation and company-scope denial are proven; higher/lower/range directions,
period boundaries, unavailable data, immature periods, previous comparisons,
and deterministic explanations are tested. No arbitrary frontend metric names
or hardcoded business targets are accepted.

**Frontend:** goal configuration and performance views depend on this backend
contract; no UI should be built before the API and status policy are accepted.

## Phase 6 — Command Centre + top-level scores

**Objective:** the actual north-star homepage and explicit score registry,
now that Trust & Safety (Phase 2), System (Phase 3), bounded health (Phase
5A), and eventually Product/Growth-lite (Phase 5) have real,
non-fabricated inputs.

**Backend work:** score registry (METRICS.md §4) combining Phase
1–5 metrics per score; explicit `NOT CONFIGURED` handling for Revenue
Score (no billing) and full Growth Score (no attribution).

**Frontend work:** the actual Command Centre — six score cards, "what
changed," "what needs attention," each expandable per D8N-HQ-PLAN.md's
drill-down principle, backed by Phase 1's Member 360 and Phase 2's Trust
page as the drill-down destinations.

**Dependencies:** Phases 1, 2, 3, 5, and 6A for explicit target-backed
performance; Phase 4 remains a nice-to-have for release correlation.

**What becomes usable:** the actual product this whole effort is named
after — but arriving *after* several individually useful tools shipped,
not before any of them.

## Phase 7+ — Deferred, explicitly out of scope until named prerequisites exist

Not sequenced further because each is blocked on a real, separately-scoped
product/business capability that doesn't exist yet, per CURRENT-STATE.md:

- **Revenue/billing views** — blocked on billing existing at all
  (`domains/billing/` is an empty placeholder).
- **Verification review** — blocked on real identity verification
  existing at all (only OTP possession checks exist today).
- **Growth/acquisition/campaign economics** — blocked on attribution
  capture (`utm_*`) being added at registration.
- **Support/Customer Service surface** — blocked on a support system
  (Zendesk/Intercom/custom) existing at all.
- **Infrastructure cost / unit economics** — blocked on provider billing
  API integrations (R2, Twilio, Resend, hosting).
- **Universal free-text search / dedicated search index** — only if the
  federated router (ARCHITECTURE.md §5) proves insufficient.
- **Cross-brand ("All D8N") drill-down beyond fan-out** — blocked on the
  Option B ADR (SECURITY-AND-RBAC.md §2), which is itself blocked on this plan's
  Phase 0 decision being revisited with real usage evidence.
- **Company Intelligence, anomaly detection, Founder Mode, Executive
  Briefings** — explicitly named in the brief as coming *after*
  trustworthy data foundations (Phases 1–6). Not scoped further here.

## First vertical slice — the exact recommendation

**Build Phase 1 (Member 360 + admin read foundation) first, alone,
before any Command Centre work.**

**Why this and not Command Centre first:**

1. It requires **zero new instrumentation and zero new architecture
   decisions** — every table it reads already exists and is already
   correctly populated by the live product (CURRENT-STATE.md, repeatedly).
   Command Centre's scores, by contrast, would either need to fabricate
   numbers (explicitly forbidden by the brief) or wait for Phases 3/5.
2. It closes the highest-leverage gap found in the original audit: there
   was no admin-facing way to look up a member at all. The backend Member
   Directory and Member 360 now exist; this milestone completes bounded
   directory search/filtering and the operational contract.
3. It's real, immediate operational value for the live HookUs beta today
   (support, moderation investigation) — not a demo, not a placeholder.
4. It establishes the `api/v1/hq/` namespace, the
   `Admin::AuthorizationContext`-based authorization pattern for HQ, and the
   sensitive-read-auditing convention (SECURITY-AND-RBAC.md §4) that every later
   phase reuses — i.e., it's simultaneously the most useful and the
   lowest-risk phase to get the foundational patterns right in.
5. It directly matches D8N-HQ-PLAN.md §7's explicit callout: Member 360's
   "why is Discover empty" diagnostic was singled out in the product
   brief as "an important D8N operability goal," and this phase is the
   one place in the entire roadmap where that's buildable with zero new
   data.

### Exact backend tickets (Phase 1)

- **HQ-101** `Hq::Identity::Lookup` — resolve a member within one brand
  by email, phone, or `public_id`; returns `nil` cleanly (no
  enumeration), authorized via `Admin::AuthorizationContext`.
- **HQ-102** `Hq::Member360::Load` — six-section aggregator per
  ARCHITECTURE.md §6, one read query per section, brand-scoped.
- **HQ-103** Read endpoint: `SecurityEvent` + `AuthAttempt` history for
  one member (paginated).
- **HQ-104** Read endpoint: `AccountEnforcement` history for one member.
- **HQ-105** `api/v1/hq/members` controller wiring HQ-101 through
  HQ-104 into `GET /api/v1/hq/members/:lookup` + section sub-resources.
- **HQ-106** Sensitive-read audit: every HQ-105 call emits a
  `SecurityEvent` (`hq.member_360_viewed`) per SECURITY-AND-RBAC.md §4.
- **HQ-107** Tenant-isolation test suite: brand-A moderator cannot reach
  brand-B member data via any HQ-105 route, mirroring this repo's
  existing mandatory tenant-isolation test category.

### Exact frontend tickets (Phase 1)

- **HQ-F01** New HQ frontend shell (or new section of an existing admin
  frontend, if one is chosen over a standalone app — this is a Phase 0
  decision to make explicit if not already implicit in "D8N HQ WEB"):
  auth via the existing brand-scoped session, brand switcher scoped to
  the operator's actual `AdminAssignment`s (no free-text "All D8N" yet).
- **HQ-F02** Search box → member lookup (email/phone/id), calling
  HQ-105.
- **HQ-F03** Member 360 page: six collapsible sections, each rendering
  its HQ-105 sub-resource, empty/`INSUFFICIENT DATA` states handled
  explicitly (never a blank crash for a member with no photos, no
  matches, etc.).
- **HQ-F04** "Why is Discover empty" expandable card within the Product
  section, if HQ-102's discovery-diagnostic sub-read
  (ARCHITECTURE.md §6) is ready; otherwise ships as a fast-follow within
  Phase 1 without blocking the rest of the page.

## Open questions requiring founder/product decisions

Restated from throughout this plan, collected here:

1. **Cross-brand authorization (SECURITY-AND-RBAC.md §2):** confirm Option A
   (fan-out only) for V1, or commission the Option B ADR now instead of
   deferring it.
2. **Observability vendor** (ARCHITECTURE.md §4): which one, and
   budget — Sentry-class error tracker at minimum; APM vendor choice
   affects Phase 3/4 cost and timeline.
3. **HQ frontend placement:** new standalone app, or a section of
   whatever admin frontend gets built first — affects HQ-F01's shape.
4. **Admin MFA timeline:** does it land before or in parallel with Phase
   1 (SECURITY-AND-RBAC.md §3 treats it as a hard prerequisite for anything beyond
   read-only low-sensitivity views — Member 360 itself is arguably
   sensitive enough to want this first, not after).
5. **Score weights/targets** (METRICS.md §5): the six top-level scores'
   actual formulas are a founder/product call, not derivable from the
   audit — needed before Phase 6, not before.
6. **Revenue/verification/support/attribution timing:** each is blocked
   on a separate, larger product decision (build billing? build real
   verification? adopt a support tool? add campaign tracking?) that is
   out of this plan's scope entirely — flagging that HQ cannot make
   these capabilities exist by wanting to display them.
