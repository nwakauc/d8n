# D8N HQ — Metric Semantic Layer

Status as of 2026-09-01: **IMPLEMENTED FOUNDATION**. The first canonical
metric layer is available at `Hq::Metrics::Catalog` and
`Hq::Metrics::Compute`, and is exposed through the Founder HQ Command Centre
snapshot endpoints. This is a bounded operational snapshot, not a warehouse,
event pipeline, scorecard, or historical rollup system.

## 1. Why this document exists

The product brief's rule: **one definition per metric, versioned, tested,
reused everywhere** (every dashboard, every score, every future Company
Intelligence answer). The failure mode this prevents: two HQ cards
disagreeing about "active member" because one query used `status: active`
and another used `last_used_at within 30 days`, and nobody can tell which
is right.

## 2. Design: a metric registry, not ad-hoc queries

`Catalog::DEFINITIONS` is the single definition/version source and `Compute`
owns the brand-scoped SQL. `MetricValue` distinguishes a real zero
(`available` with `value: 0`) from `unavailable` and `insufficient_data`.
Every snapshot metric carries its definition, unit, limitations, and version.
The legacy `Hq::Analytics::Overview` endpoint remains backward compatible and
is not yet migrated to the new response shape.

**Testing requirement:** every metric class gets a unit test with a fixed
fixture scenario and an expected value — exactly like every other domain
service in this codebase (see `test/domains/` conventions). A metric
without a test is not allowed to back a Command Centre score.

## 3. Canonical metric definitions

Each entry: name, one-sentence definition, data availability today
(cross-referenced to CURRENT-STATE.md), and the exact source.

| Metric | Definition | Availability | Source |
| --- | --- | --- | --- |
| `memberships.total` | Distinct users with ≥1 kept `BrandMembership` for the brand | ✅ IMPLEMENTED | `BrandMembership` |
| `memberships.new` | Kept `BrandMembership` rows created in the named time window | ✅ IMPLEMENTED | `BrandMembership` |
| `profiles.by_status` | Kept profiles grouped by current lifecycle status | ✅ IMPLEMENTED | `Profile` |
| `profiles.visible_published` | Kept profiles with `status: active` and `visibility: visible` | ✅ IMPLEMENTED | `Profile` |
| `profiles.activation_ratio` | Active profiles divided by kept brand memberships; insufficient when denominator is zero | ✅ IMPLEMENTED | `Profile` + `BrandMembership` |
| `active_member` (a given day/window) | A member with a `Session` whose `last_used_at` falls within the window, OR (once §3 event pipeline exists) any `AnalyticsEvent` in the window | ✅ DERIVABLE today (session-based definition); event-based refinement is FUTURE | `Session` |
| `users.active` | Distinct users with a session `last_used_at` in the named window | ✅ IMPLEMENTED | `Session` |
| `marketplace.likes_created` / `matches_created` / `conversations_created` | Kept rows created in the named window | ✅ IMPLEMENTED | `Like` / `Match` / `Conversation` |
| `marketplace.zero_discovery_allocations` | Allocations on completed local calendar dates with zero kept candidates | ✅ IMPLEMENTED | `DiscoveryAllocation` + candidates |
| `marketplace.published_without_likes` / `_matches` | Published profiles with no lifetime kept interaction on either side | ✅ IMPLEMENTED | `Profile` + `Like` / `Match` |
| `marketplace.time_to_first_*_median` | Intended duration metrics | 🟡 OPERATIONAL ACCEPTANCE REQUIRED | No bounded rollup exists; API returns `unavailable` |
| `trust.open_reports` / `awaiting_decision` | Current open or open/reviewing report counts | ✅ IMPLEMENTED | `Report` |
| `trust.active_enforcements` | Current non-reverted enforcement count | ✅ IMPLEMENTED | `AccountEnforcement` |
| `trust.pending_photo_reviews` | Kept profile photos with `pending_review` status | ✅ IMPLEMENTED | `ProfilePhoto` |
| `trust.oldest_open_report_age_seconds` | Age of the oldest open report, or insufficient data when none exists | ✅ IMPLEMENTED | `Report` |
| `retained_member` (D1/D7/D30) | A member who registered on day 0 and has ≥1 `active_member` day at day N | ✅ DERIVABLE today, cohort rollup needed | `User.created_at` (via first `BrandMembership`) + `Session` |
| `match_rate` | matches ÷ likes sent, over a window, segmentable by brand/cohort | 📝 DOCUMENTATION ONLY | Not exposed until matching attribution semantics are accepted |
| `conversation_rate` | conversations started ÷ matches created | ✅ DERIVABLE today | `Match` + `Conversation` |
| `zero_result_rate` | share of `DiscoveryAllocation` rows with zero candidates | 📝 DOCUMENTATION ONLY | The zero-allocation count is implemented; denominator/rate is not exposed |
| `zero_like_rate` / `zero_match_rate` | share of published members with zero `Like`/`Match` rows in a trailing window | ✅ DERIVABLE today | `Profile` + `Like`/`Match` |
| `report_rate` | reports filed per 1,000 published members, per brand, per window | ⚪ NOT STARTED | No accepted rate endpoint |
| `delivery_rate` (notifications) | `NotificationDelivery.status: sent` ÷ total attempted, per channel/provider | ✅ DERIVABLE today | `NotificationDelivery` |
| `time_to_first_match` / `_conversation` / `_like` | duration between profile activation and first interaction | 🟡 OPERATIONAL ACCEPTANCE REQUIRED | Existing rows lack a bounded rollup for safe live median calculation |
| `cost_per_registration` / `cost_per_valuable_member` | spend ÷ registrations (or ÷ members meeting a "valuable" definition — onboarded + published + ≥1 match) | ❌ NOT AVAILABLE — no campaign spend data and no acquisition attribution exist (CURRENT-STATE.md §14) | EXTERNAL (ad platform APIs) + new `utm_*` capture |
| Anything keyed on acquisition channel/campaign | | ❌ NOT AVAILABLE, same reason | — |
| Anything keyed on `release`/deployed version | | 🟡 PARTIAL — release identity exists at `/api/v1/version`, but no metric/event/error correlation exists yet | `D8n::ReleaseIdentity`; future event/observability integrations |

## 4. Versioning & change policy

- Bumping a metric's `VERSION` is a reviewable, deliberate change — not a
  silent query tweak. The changelog entry states old vs. new definition
  and why.
- Historical dashboard values computed under an old version are labeled
  with that version, not silently recomputed under the new one (avoids
  the "why did last month's number change" trust problem).
- A score (D8N-HQ-PLAN.md's Growth/Product/Revenue/Customer/Safety/System
  Score) is itself just a weighted combination of registry metrics, with
  its own `VERSION`. If any input metric is `NOT AVAILABLE`, the score
  computes as `NOT CONFIGURED`, not a partial number with silently
  zeroed inputs.

## 5. What this document deliberately does not do

It does not assign weights or targets to the six top-level company
scores — those are product/business decisions for the founder, not an
engineering default (see ROADMAP.md § Open Questions). It does not define
every metric in the product brief's long lists (growth, campaign
economics, infra cost) — those are `NOT AVAILABLE` per CURRENT-STATE.md
and get a registry entry only once their data source exists.

## 6. Product Intelligence foundation

Phase 4 adds `AnalyticsEvent` as a separate append-only event table. The
initial allowlisted taxonomy is intentionally small:

| Event | Authoritative producer | Backfill status |
|---|---|---|
| `member.registered` | `Identity::PasswordRegistration#create_account` after membership creation | Exactly backfillable from kept membership creation time, but no backfill is run automatically |
| `profile.published` | `Profiles::Publication.activate!` after the publication transition | Not backfillable exactly; current `Profile.updated_at` is not treated as publication time |

Likes, matches, and conversations are not duplicated as analytics events in
this phase: their kept transaction rows and `created_at` values are the
authoritative historical source. Onboarding completion is computed today but
has no persisted completion timestamp and is therefore unavailable for
historical funnel conversion.

`GET /api/v1/hq/product_intelligence/funnel` uses a kept-membership
registration cohort and a bounded window. It exposes the recorded publication
stage and first-like stage, while explicitly returning onboarding as
`unavailable` until a durable completion transition exists. The trends
endpoint is similarly bounded and brand-scoped. Neither endpoint claims
retention, attribution, or historical values that cannot be reconstructed.

Events accept only the fixed context envelope and allowlisted properties for
their event type. No message bodies, credentials, tokens, report evidence,
precise location, email, or phone values are accepted. Event rows are
immutable and idempotency-key deduplicated. Account closure policy for this
new event class remains: retain only the minimum pseudonymous foreign-key
context needed for aggregate integrity, subject to the final legal retention
period and future platform-wide identity-erasure decision; no personal text is
stored in event properties.
