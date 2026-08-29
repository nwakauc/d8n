# D8N HQ — Metric Semantic Layer

Status: **TARGET ARCHITECTURE**, with concrete CURRENT REALITY definitions
where a metric is already computable from existing tables (marked ✅
below). No metric registry code exists yet.

## 1. Why this document exists

The product brief's rule: **one definition per metric, versioned, tested,
reused everywhere** (every dashboard, every score, every future Company
Intelligence answer). The failure mode this prevents: two HQ cards
disagreeing about "active member" because one query used `status: active`
and another used `last_used_at within 30 days`, and nobody can tell which
is right.

## 2. Design: a metric registry, not ad-hoc queries

```ruby
module Hq
  module Metrics
    class RegisteredMember < Base
      VERSION = 1
      DEFINITION = "A User with at least one kept BrandMembership."
      def self.compute(brand:, as_of: Time.current)
        # ...
      end
    end
  end
end
```

Every metric is a class with: a fixed `id` (the class/file name), a
`VERSION` integer (bump on any definition change — old dashboards/reports
can pin a version), a human `DEFINITION` string (shown in the UI next to
the number, per D8N-HQ-PLAN.md's "explanation" requirement), and a `compute`
method. **Every dashboard card and every future Company Intelligence
answer calls `Hq::Metrics::X.compute(...)` — never writes its own SQL for
a metric that already has a registry entry.** This mirrors an existing,
proven pattern in this codebase: `Identity::AuthPolicy`,
`AbuseProtection::Policy`, and `Profiles::CapabilityCatalog` are all
"one source of truth, brands compose from it" modules already; the metric
registry is the same idea applied to numbers instead of capabilities.

**Testing requirement:** every metric class gets a unit test with a fixed
fixture scenario and an expected value — exactly like every other domain
service in this codebase (see `test/domains/` conventions). A metric
without a test is not allowed to back a Command Centre score.

## 3. Canonical metric definitions

Each entry: name, one-sentence definition, data availability today
(cross-referenced to CURRENT-STATE.md), and the exact source.

| Metric | Definition | Availability | Source |
| --- | --- | --- | --- |
| `registered_member` | A `User` with ≥1 kept `BrandMembership` for the brand in question | ✅ DERIVABLE today | `User` + `BrandMembership` |
| `activated_member` | A member whose `Profile` has `status: active` (i.e. completed the brand's required fields — see `Profile#profile_completion_requirements`) | ✅ DERIVABLE today | `Profile` |
| `published_member` | A member with a `Profile` where `status: active` AND `visibility: visible` | ✅ DERIVABLE today | `Profile` |
| `active_member` (a given day/window) | A member with a `Session` whose `last_used_at` falls within the window, OR (once §3 event pipeline exists) any `AnalyticsEvent` in the window | ✅ DERIVABLE today (session-based definition); event-based refinement is FUTURE | `Session` |
| `DAU` / `WAU` / `MAU` | Distinct `active_member` count over a 1/7/30-day trailing window | ✅ DERIVABLE today, needs a rollup job (ARCHITECTURE.md §2) to avoid live full-table scans at scale | `Session` |
| `retained_member` (D1/D7/D30) | A member who registered on day 0 and has ≥1 `active_member` day at day N | ✅ DERIVABLE today, cohort rollup needed | `User.created_at` (via first `BrandMembership`) + `Session` |
| `match_rate` | matches ÷ likes sent, over a window, segmentable by brand/cohort | ✅ DERIVABLE today | `Like` + `Match` |
| `conversation_rate` | conversations started ÷ matches created | ✅ DERIVABLE today | `Match` + `Conversation` |
| `zero_result_rate` | share of `DiscoveryAllocation` rows with zero `DiscoveryAllocationCandidate` rows | ✅ DERIVABLE today | `DiscoveryAllocation`/`DiscoveryAllocationCandidate` |
| `zero_like_rate` / `zero_match_rate` | share of published members with zero `Like`/`Match` rows in a trailing window | ✅ DERIVABLE today | `Profile` + `Like`/`Match` |
| `report_rate` | reports filed per 1,000 published members, per brand, per window | ✅ DERIVABLE today | `Report` + `Profile` |
| `delivery_rate` (notifications) | `NotificationDelivery.status: sent` ÷ total attempted, per channel/provider | ✅ DERIVABLE today | `NotificationDelivery` |
| `time_to_first_match` / `_conversation` / `_like` | duration between `Profile.status → active` (or `created_at`) and first `Like`/`Match`/`Conversation` row | ✅ DERIVABLE today | `Profile`, `Like`, `Match`, `Conversation` |
| `cost_per_registration` / `cost_per_valuable_member` | spend ÷ registrations (or ÷ members meeting a "valuable" definition — onboarded + published + ≥1 match) | ❌ NOT AVAILABLE — no campaign spend data and no acquisition attribution exist (CURRENT-STATE.md §14) | EXTERNAL (ad platform APIs) + new `utm_*` capture |
| Anything keyed on acquisition channel/campaign | | ❌ NOT AVAILABLE, same reason | — |
| Anything keyed on `release`/deployed version | | ❌ NOT AVAILABLE — no version stamping exists (CURRENT-STATE.md #9.7) | — |

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
