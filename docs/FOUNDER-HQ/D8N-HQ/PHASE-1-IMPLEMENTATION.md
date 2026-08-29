# D8N HQ — Phase 1 Backend Implementation (Member 360)

Status: **BUILT.** This document records what actually shipped for Phase 1
(ROADMAP.md's first vertical slice — HQ-101 through HQ-107), as evidence
against the plan, not as a new plan. If this document and ROADMAP.md/
D8N-HQ-PLAN.md ever disagree about what's *planned*, those remain
canonical; this document is a snapshot of what's *built*, dated by git
history from this point forward.

The full JSON contract for every endpoint below is in
[`docs/api/openapi.yaml`](../../api/openapi.yaml) (tag: `Hq`) — that file,
not this one, is the source of truth the frontend should generate/validate
against. This document is the narrative walkthrough.

## What shipped

- `Hq::Identity::Lookup` (HQ-101) — `domains/hq/identity/lookup.rb`
- `Hq::Member360::Load` (HQ-102) — `domains/hq/member360/load.rb`
- `Hq::SecurityEventHistory` / `Hq::AuthAttemptHistory` (HQ-103) —
  `domains/hq/security_event_history.rb`, `domains/hq/auth_attempt_history.rb`
- `Hq::EnforcementHistory` (HQ-104) — `domains/hq/enforcement_history.rb`
- `Api::V1::Hq::MembersController` + `api/v1/hq` routes (HQ-105) —
  `app/controllers/api/v1/hq/{base_controller,members_controller}.rb`,
  `config/routes.rb`
- `Hq::SensitiveReadAudit` (HQ-106) — `domains/hq/sensitive_read_audit.rb`,
  called from every action in `MembersController`
- Tenant-isolation + full test suite (HQ-107) —
  `test/domains/hq/**`, `test/controllers/api/v1/hq/**`
- **Fast-follow, also shipped:** `Hq::Member360::DiscoveryDiagnostic` (the
  "why is Discover empty" diagnostic named in D8N-HQ-PLAN.md §12) —
  `domains/hq/member360/discovery_diagnostic.rb`, exposed as a fifth
  endpoint rather than embedded in the Member 360 payload (see below).

## Routes

All under `GET /api/v1/hq/members/:lookup...`, namespaced separately from
`/api/v1/admin` per ARCHITECTURE.md §1.1 (same Rails app, new namespace —
not a separate service):

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/hq/members/{lookup}` | Member 360 six-section summary |
| GET | `/api/v1/hq/members/{lookup}/security_events` | Paginated `SecurityEvent` history |
| GET | `/api/v1/hq/members/{lookup}/auth_attempts` | Paginated `AuthAttempt` history |
| GET | `/api/v1/hq/members/{lookup}/enforcements` | Paginated `AccountEnforcement` history |
| GET | `/api/v1/hq/members/{lookup}/discovery_diagnostic` | Read-only discovery funnel diagnostic |

`{lookup}` accepts an email, a phone number, or a profile `public_id` UUID.
The route has an explicit `constraints: { lookup: /[^\/]+/ }` because Rails'
default routing treats a trailing `.xyz` in a path segment as a format
suffix, which would otherwise mis-parse an email address.

## Authorization model used

**No new authorization mechanism.** Every HQ route requires the same thing
`/api/v1/admin/*` already requires: an authenticated `Current.user` that
resolves via `Admin::ModeratorContext.resolve(user:, brand:)` to a kept,
active `AdminUser` with a kept, active `AdminAssignment` on the request's
brand (`Api::V1::Hq::BaseController#authenticate_admin!`, byte-for-byte the
same logic as `Api::V1::Admin::BaseController`). Unauthenticated → 401.
Authenticated but not an admin, or an admin assigned to a *different*
brand → 403. This confirms SECURITY-AND-RBAC.md §3 step 1 in practice: HQ
ships under the existing `moderator` role, no new role, no new table.

Per SECURITY-AND-RBAC.md §1's still-open gaps (no differentiated admin RBAC,
no admin MFA): HQ Phase 1 does not change or work around either. Any
active admin assignment on a brand can see that brand's Member 360 today —
identical blast radius to the existing reports queue, not a new one. Admin
MFA remains the same pre-launch gate it already was; HQ raises its
priority (per SECURITY-AND-RBAC.md §3) but does not gate on it, matching
ROADMAP.md Phase 1's explicit scope.

## Brand isolation

Every lookup and every read is scoped to `Current.brand` (server-derived
from the request host, never client-supplied — same as the admin
namespace). `Hq::Identity::Lookup` requires a **kept `BrandMembership` on
this brand** before returning anything; an identifier that only exists on
another brand, or doesn't exist at all, returns `nil` from the same code
path — the controller cannot tell the two cases apart, so it can't leak
which one occurred. This is Option A from SECURITY-AND-RBAC.md §2
(fan-out only, no new cross-brand grant) — there is no "All D8N" view in
this slice, and none of the query/service code accepts a brand parameter
from anywhere but `Current.brand`.

Verified by `test/controllers/api/v1/hq/members_controller_test.rb`
("a member who only exists on another brand is not found here") and
`test/domains/hq/identity/lookup_test.rb` ("returns nil ... when the
identifier belongs to another brand only").

## Member lookup behavior

- **Identifiers:** email (case-insensitive), phone (normalized via the
  same `Identity::LoginIdentifier`/`Identity::PhoneNormalizer` the login
  flow uses — no separate normalization logic invented), or a profile
  `public_id` UUID.
- **No enumeration:** unknown, cross-brand, and malformed lookups are all
  the same `member_unavailable` (404). The controller never distinguishes
  "doesn't exist" from "exists somewhere else."
- **Deterministic:** the same lookup value always resolves to the same
  member (or consistently to nothing) — no fuzzy matching, no partial
  matching, no free-text search (per ARCHITECTURE.md §5, deferred
  entirely for V1).
- **A member without a profile yet resolves successfully** — `Lookup`
  returns `profile: nil`, and every downstream section handles that
  (`Member360::Load#profile_section` returns `{ exists: false }`; product/
  safety counts are all `0`/`[]` rather than raising).

## Member 360 data available

Six sections, exactly as ARCHITECTURE.md §6 specifies, each a **thin,
bounded read against an existing table** — zero new instrumentation, zero
new tables:

- **identity** — `User` status/name, `BrandMembership` status, up to 10
  kept email/phone `IdentityIdentifier`s, up to 5 most-recent `Session`s
  (no token digests).
- **profile** — `Profile` core fields, `Profiles::OnboardingStatus` (reused
  verbatim, not reimplemented), up to 20 kept `ProfilePhoto`s (state only,
  no image URLs — that's a separate, already-existing moderation surface),
  `ProfilePreference`.
- **product** — `Like`/`Match`/`Hook`/`HookTonightState`/`Conversation`/
  `ProfileBlock` counts, plus up to 5 recent conversations (id/status/
  timestamp only — never message content).
- **comms** — `NotificationDelivery` counts by status/channel (computed
  over the 200 most recent rows in Ruby, not a DB `GROUP BY`, to sidestep
  Rails enum-grouping ambiguity — safe at this per-member scale) and up to
  10 recent deliveries.
- **safety** — report-filed/received counts, up to 5 recent reports
  (id/status/reason/target_type/direction — no evidence, that's what
  `GET /api/v1/admin/reports/{id}` is for), current active
  `AccountEnforcement` (reuses `Admin::EnforcementSerializer` verbatim),
  enforcement count, `AccountClosure` summary if present.
- **activity** — last successful login timestamp, up to 5 recent
  `AuthAttempt`s and `SecurityEvent`s (full paginated history lives behind
  the two sub-resource endpoints, not embedded here, so the main payload
  stays small and fast).

**Full history for security events, auth attempts, and enforcements is
deliberately NOT embedded in the Member 360 payload** — it's cursor-
paginated behind its own endpoint (`Hq::Cursor`, a generic, signed,
brand+user+purpose-bound keyset cursor, modeled on `Admin::ReportCursor`).
This keeps the primary Member 360 read cheap (per ARCHITECTURE.md §2's
"cheap, indexed, single-row-ish reads are fine synchronously" rule) while
still making the full trail available on demand.

## Discovery diagnostic

`Hq::Member360::DiscoveryDiagnostic` re-runs the **live** discovery
engine's own scopes — `Matching::VisibilityScope`,
`Matching::EligibilityScope`, `Matching::ExclusionsScope` — read-only, and
reports a candidate count at each stage. It never touches
`DiscoveryAllocation`/`DiscoveryAllocationCandidate` and never consumes the
member's daily discovery quota (verified by
`assert_no_difference -> { DiscoveryAllocation.count }` in the test suite).

**Known limitation, documented rather than worked around:**
`Matching::EligibilityScope` applies gender/age/distance as one private,
chained scope and doesn't expose those three as separate counts today.
Reproducing the product brief's ideal per-filter breakdown would mean
either reimplementing that filter logic here (explicitly disallowed by
this task's brief) or changing `EligibilityScope`'s public interface,
which is out of scope for this slice. The diagnostic currently reports
three coarser stages: `visible_active_profiles` →
`reciprocal_gender_age_distance` → `final_eligible_candidates`. Splitting
the middle stage further is a small, well-scoped follow-up once
`EligibilityScope` is refactored to expose intermediate scopes — not a
redesign.

When the member themselves isn't eligible to see discovery at all
(incomplete profile, wrong lifecycle state, etc. — same check
`Matching::Discovery` itself uses via `ProfileParticipant.discoverable!`),
the endpoint returns `eligible: false` with a reason, not an error.

## Privacy / security review

- No passwords, credential hashes, auth tokens, session token digests, or
  provider credentials appear anywhere in any HQ response (asserted
  directly in the controller test: `%w[password credential token_digest]`
  are grepped out of the full response body).
- No message/conversation content. Conversations appear only as
  id/status/timestamp. Reports appear only as id/status/reason/
  target_type/direction — the existing `Report.evidence` snapshot is
  intentionally *not* duplicated here; a moderator who needs it already
  has `GET /api/v1/admin/reports/{id}` for that.
- No raw photo URLs — photo state (status/visibility/processing_state)
  only.
- Every read across every one of the five endpoints is individually
  audited via `Hq::SensitiveReadAudit`, writing a `SecurityEvent` with
  `event_type` one of `hq.member_360_viewed`,
  `hq.member_security_events_viewed`, `hq.member_auth_attempts_viewed`,
  `hq.member_enforcements_viewed`, `hq.member_discovery_diagnostic_viewed`,
  and `metadata: { admin_user_id:, target_user_id: }` — mirroring
  `Admin::ModerationAudit`'s existing pattern exactly (SECURITY-AND-RBAC.md
  §4). This means HQ itself is now answerable to the same "who looked up
  this member, and when" question it exists to help answer about the rest
  of the system.
- `first_name`/`last_name` (the private legal-ish identity fields on
  `User`, distinct from the public `Profile.display_name`) and raw
  `AuthAttempt`/`Session` IP addresses ARE exposed in Member 360 — this is
  a deliberate call, not an oversight: they're core to the IDENTITY/
  ACTIVITY sections' stated purpose (support/investigation), the read is
  fully audited, and access requires the same admin assignment that
  already grants report/enforcement visibility. If this needs tightening
  before real user data goes live (e.g. before admin MFA ships, per
  SECURITY-AND-RBAC.md §3), that's a founder call, not something this
  implementation should have silently decided either way.

## Performance / query review

- Every section is a single indexed query or a `.limit()`-bounded scan —
  no unbounded cross-brand aggregate, no full-table scan on `messages`, no
  N+1 (counts and bounded `.limit(N)` lists are separate, cheap, indexed
  queries per section; nothing loads a full association just to count it).
- `comms` section caps its Ruby-side tally at the 200 most recent
  deliveries per member (`NOTIFICATION_SCAN_LIMIT`), not unbounded.
- Cursor pagination on the three history endpoints uses the same
  `(created_at, id)` keyset pattern as `Admin::ReportCursor` — no
  `OFFSET`-based pagination, which would degrade on deep pages.
- The discovery diagnostic issues three `.count` queries reusing the
  engine's real indexed scopes — acceptable for an admin-triggered,
  single-viewer diagnostic (not a bulk operation, not on any member-facing
  request path), consistent with ARCHITECTURE.md §10's "PII-sensitive
  searches / requiring elevated auth" bucket rather than its "unsafe
  synchronous" bucket (which is about *cross-brand, unbounded* aggregates).

## Tests / results

- `test/domains/hq/identity/lookup_test.rb` — 7 tests: email/phone/
  public_id resolution, no-profile-yet, unknown lookup, cross-brand
  identifier not found, membership-less user not found.
- `test/domains/hq/member360/load_test.rb` — 5 tests: full six-section
  shape, no-profile empty state, product counts, safety counts +
  enforcement, activity brand-scoping.
- `test/domains/hq/member360/discovery_diagnostic_test.rb` — 3 tests:
  full funnel for an eligible member, ineligible-member handling, exclusion
  of an already-liked candidate with a `DiscoveryAllocation` no-op assertion.
- `test/controllers/api/v1/hq/members_controller_test.rb` — 17 tests:
  401/403 auth rejection, cross-brand admin rejection, cross-brand member
  not found, unknown lookup, case-insensitive email, public_id lookup,
  full Member 360 payload + audit + no-credential-leak assertion,
  no-profile-yet empty state, security_events pagination + brand scoping +
  audit, auth_attempts cursor pagination (no duplicates across pages),
  invalid limit/cursor rejection, cursor-cannot-be-replayed-against-another-
  member, enforcements sub-resource, discovery_diagnostic ineligible/
  eligible/no-profile cases.
- **All 32 new tests pass.** RuboCop clean on every new/changed file
  (`domains/hq/**`, `app/controllers/api/v1/hq/**`, `config/routes.rb`,
  `test/domains/hq/**`, `test/controllers/api/v1/hq/**`).
- Full existing suite re-run after this change: **no regressions**
  introduced. `test/contracts/openapi_contract_test.rb` (route/schema
  parity) required and received an update — every new route is documented
  in `docs/api/openapi.yaml` under the `Hq` tag. One pre-existing failure
  (`Notifications::DeliverProductNotificationJobTest`, an unrelated email-
  template assertion) was confirmed present on `dev` before this change
  (via `git stash`) and is not touched by this work.

## Known limitations / what's deliberately not built

- No "All D8N" cross-brand view (Option A only, per SECURITY-AND-RBAC.md
  §2 — this is the founder decision Phase 0 asked for, not resolved here).
- No admin MFA gate on these endpoints (pre-existing, restated priority
  per SECURITY-AND-RBAC.md §3 — not this slice's decision to make).
- Discovery diagnostic's middle stage is coarser than the product brief's
  ideal (see above).
- No free-text/fuzzy member search — exact identifier lookup only, per
  ARCHITECTURE.md §5.
- `comms` section's delivery counts are per-member and bounded — no
  brand-wide delivery-health rollup (that's Phase 2+/Provider Health
  territory, not Member 360).

## What remains for the next HQ slice

Per ROADMAP.md Phase 2 (Trust & Safety command surface): repeat-offender
aggregation, brand-wide enforcement history, "age of oldest open report" /
queue stats — all additive reads over `Report`/`AccountEnforcement`, no
schema change, and explicitly meant to link into this Member 360 page
(every report/enforcement view should deep-link to
`GET /api/v1/hq/members/{lookup}` for the relevant member).

## Frontend integration notes

- Generate/validate against `docs/api/openapi.yaml` (tag `Hq`) — don't
  reverse-engineer the controllers.
- Auth: same brand-scoped session as the rest of the app (bearer token or
  cookie) — no separate HQ login. A 403 with `{"error": "forbidden"}` means
  "authenticated but not an admin for this brand," not "log in again."
- `lookup` in the URL must not be pre-encoded in a way that strips `+`/`.`
  from a phone/email — pass the raw string, let the client's URL encoder
  handle it normally (the route constraint already accounts for dots).
- `sections.profile.exists === false` is the only signal needed to render
  an empty-profile state — every other key in that section is simply
  absent, not `null`, when `exists` is `false`.
- Cursors from `security_events`/`auth_attempts`/`enforcements` are opaque
  and **not interchangeable** between endpoints or between members — always
  pass back exactly the `next_cursor` a given endpoint returned, for the
  same `lookup` you requested it with.
- `HQ-F04` ("why is Discover empty" card) can call
  `GET /api/v1/hq/members/{lookup}/discovery_diagnostic` directly now — it
  shipped as part of this slice, not deferred.
