# D8N HQ — Goals & Performance Scoreboard

Status: **FUTURE DESIGN — NOT IMPLEMENTED.** Product Intelligence remains the
active delivery stream. This document defines the smallest backend capability
needed for Founder HQ to answer: **“Are we winning or losing against the
targets we explicitly set?”**

## 1. Scope and non-goals

This is a deterministic target-tracking layer over the canonical HQ metric
registry. It is not a new analytics store, scorecard, recommendation engine,
AI system, or arbitrary dashboard-query builder. It must not create business
targets in code or allow the frontend to invent metric names.

## 2. Smallest persistence model

The future `Hq::Goal` record should contain:

| Field | Rule |
|---|---|
| `metric_id` | Required controlled identifier from `Hq::Metrics::Catalog`; foreign-key-like validation against the registry |
| `scope_type` / `scope_id` | `Brand` for brand goals; an explicit D8N/company scope only for an authorized company-level capability |
| `period` | One of `daily`, `weekly`, `monthly`, `yearly` |
| `target_value` | Required non-negative numeric target for `higher_is_better` / `lower_is_better` |
| `target_min` / `target_max` | Required pair for `within_range`; inclusive bounds with `min <= max` |
| `direction` | Registry-declared `higher_is_better`, `lower_is_better`, or `within_range`; clients cannot override it |
| `effective_start_date` / `effective_end_date` | Required bounded date range; end may be open only if explicitly supported by implementation |
| `active` | Explicit active/inactive state; inactive goals do not appear in the active scoreboard |
| `created_by_admin_user_id` / `updated_by_admin_user_id` | Required actor attribution |
| timestamps | Creation and update timestamps |

Target changes should be represented by an append-only goal-change audit
record, or an equivalent immutable revision table, containing old value, new
value, actor, reason if required by policy, timestamp, and brand/company scope.
The original goal row must not erase target history.

## 3. Metric registry contract

Every goalable metric must already exist in the canonical registry and declare:

- stable metric identifier and definition version
- unit and numeric type
- supported scopes and periods
- aggregation semantics
- `higher_is_better`, `lower_is_better`, or `within_range`
- whether a target value or target range is valid
- availability and maturity limitations

Examples:

| Metric | Direction |
|---|---|
| `memberships.new` | `higher_is_better` |
| account closures, once registered in the metric catalog | `lower_is_better` |
| marketplace share, once its denominator and segment semantics are accepted | `within_range` |

The registry, not the frontend, owns direction and supported target shape.
Adding a goalable metric requires a versioned metric-definition change and
tests.

## 4. Authorization and scope

Goal reads and writes must reuse `Admin::AuthorizationContext`, MFA, and
capabilities. The smallest proposed capabilities are:

- `hq.goals.read`
- `hq.goals.manage`

These are a future capability-catalog decision, not a role-name check.

Brand goals require an active assignment for that brand. Company/D8N-wide
goals require an explicit company-scope capability and separate authorization
decision; Founder/Super Admin labels alone must not create a global bypass.
Every read of target history and every mutation is audited.

## 5. Evaluation semantics

For a goal period, the evaluator resolves one canonical metric definition and
returns:

- target or target range
- actual value
- expected-to-date / target pace when the period has elapsed time and the
  metric supports a meaningful pace
- remaining amount when subtraction is meaningful
- attainment percentage only when the direction and denominator make it
  mathematically valid
- metric status: `available`, `unavailable`, or `insufficient_data`
- goal status: `ahead`, `on_track`, `at_risk`, `behind`, `achieved`,
  `unavailable`, or `insufficient_data`
- metric-definition version and limitations

“Higher” is never interpreted as universally good. For higher/lower goals,
remaining and attainment are direction-aware. For range goals, health means
the actual is inside the inclusive range; the range pacing rule must be
approved and versioned before implementation rather than guessed.

An immature period returns `insufficient_data` or `not_yet_eligible` where a
comparison cannot be made. It must not manufacture a false failure.

The status thresholds and range-pacing rule are policy inputs that require
founder approval before coding. They are not business targets and must be
versioned separately from the metric definition.

## 6. Period and comparison rules

Periods use the existing HQ canonical timezone, `Africa/Johannesburg`, and
brand-local calendar boundaries. The evaluator must use half-open intervals to
avoid overlap at midnight.

Previous-period comparison is returned only when the previous equivalent period
is comparable, the metric definition version is compatible, and both values
are available. Otherwise it returns an explicit unavailable/insufficient state
with a limitation.

## 7. Future API shape

The smallest future API could be:

```text
GET   /api/v1/hq/goals
POST  /api/v1/hq/goals
PATCH /api/v1/hq/goals/:id
GET   /api/v1/hq/goals/:id/performance
GET   /api/v1/hq/goals/:id/history
```

Responses should include drill-down metadata: definition, target, actual,
expected by now, historical trend when available, previous-period comparison,
authorized contributing brands/segments, limitations, and audit/version
information. No arbitrary SQL, metric names, or unbounded cross-brand query
parameters are accepted.

## 8. Dependencies and acceptance criteria

Implementation should wait until:

1. Product Intelligence has stable metric IDs, versions, availability states,
   and bounded historical queries.
2. Direction metadata and goalable-period metadata are added to the canonical
   metric registry.
3. Founder-approved status thresholds and within-range pacing semantics exist.
4. Goal scope capabilities and company-scope authorization are explicitly
   approved.
5. Audit retention and target-change reason policy are agreed.

Acceptance requires tests for metric validation, target/range constraints,
brand isolation, company-scope denial, MFA, actor attribution, target history,
each direction, each period, date boundaries, unavailable and immature data,
zero values, previous-period comparability, and deterministic explanations.

## 9. Explicitly deferred

- AI recommendations or explanations
- automatic target generation
- universal company bypass
- revenue, billing, attribution, or advertising goals before those metrics
  exist in the registry
- executive “winning/losing” scores; those belong after goal evaluation is
  trustworthy
