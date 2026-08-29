# D8N HQ — Target Architecture

Status: **TARGET ARCHITECTURE.** Proposed, not built. Every section states
what exists today (cross-referencing CURRENT-STATE.md) before proposing
what to add, and is explicit about what NOT to build.

## 1. Layered architecture (smallest version that can grow into the
north-star)

```
D8N HQ WEB (separate frontend app, per ADR 0004's API-only-core pattern)
        │
D8N HQ API / QUERY LAYER  (new Rails engine or namespace inside d8n, see §1.1)
        │
        ├── Operational D8N data        — existing tables, read via scoped queries (READY today)
        ├── Metric/semantic layer       — new: versioned metric definitions (see METRICS.md)
        ├── Event system                — new: canonical event pipeline (see §3)
        ├── Observability adapter       — new: reads an external vendor's API (see §4)
        ├── Provider adapters           — new: Resend/Twilio/R2 status APIs (see §7)
        ├── Deployment/release data     — new: version stamping + Kamal/GitHub API (see §9)
        └── Alert/intelligence layer    — FUTURE, after the above are trustworthy (see §11)
```

**Do not assume this exact shape is final.** The one load-bearing
decision this plan does commit to: **HQ is a read/aggregate layer over
D8N's existing operational database and a small number of new
purpose-built tables (events, metric snapshots) — it is not a second
system of record.** D8N DB stays authoritative for product/business/admin
data. This directly satisfies the product brief's "D8N owns authoritative
product/business/admin data; HQ aggregates, correlates, explains."

### 1.1 Where does HQ's backend live?

Two real options, not decided here:

- **(a) New namespace inside the existing `d8n` Rails app**
  (`app/controllers/api/v1/hq/`, `domains/hq/`), reusing brand resolution,
  session auth, and every existing model directly with zero
  network hops.
- **(b) A separate Rails app/engine** that queries `d8n`'s database (or an
  API) from outside.

**Recommendation: (a) for V1.** D8N is a modular monolith by deliberate
choice (ADR 0001); HQ querying `Report`, `AccountEnforcement`,
`NotificationDelivery`, etc. in-process is strictly simpler and faster to
ship than standing up cross-service auth and a second deploy target for
a tool with, at launch, a handful of trusted operators. Revisit only if
HQ's own load profile (heavy aggregate queries) starts to risk the
product API's latency — see §10 Performance/Safety.

## 2. Read vs. write APIs, and keeping HQ from hurting production

**Every HQ read is a read against the same Postgres primary the product
API uses, until proven otherwise.** This is the single biggest operational
risk this plan introduces, so the rule is explicit:

- **Cheap, indexed, single-row-ish reads** (Member 360 lookups, a
  member's reports, a brand's active enforcement) — fine to run directly,
  synchronously, against the primary. These mirror what the existing
  admin controllers already do.
- **Expensive aggregate reads** (marketplace-health rollups across
  brand/country/cohort, funnel conversion over weeks of data, DAU/WAU/MAU)
  — **must not** run as ad-hoc synchronous queries against the primary in
  the request path. These need either (a) a scheduled rollup job that
  writes small pre-aggregated summary rows HQ reads instantly, or (b) a
  dedicated analytics store fed by the event pipeline (§3), once that
  exists. Until then, these metrics simply render `INSUFFICIENT DATA` /
  "computed as of last rollup" rather than being computed live on every
  page load.
- **Writes** (admin actions — suspend, dismiss a report, approve a photo)
  reuse the *existing* domain services (`Admin::SuspendProfile`,
  `Admin::TransitionReport`, `Trust::ModerateProfilePhoto`) verbatim. HQ
  is a new caller of these, not a reimplementation.

No read replica, materialized view infrastructure, or dedicated
analytics database is introduced in this plan. CURRENT-STATE.md confirms
none exist today; §10 identifies exactly where they'll first become
necessary so they're added when the evidence (measured query cost/count),
not speculation, justifies it.

## 3. Event architecture

**Current reality (CURRENT-STATE.md §11): there is no canonical
product-analytics event system.** `NotificationEvent` is real,
event-sourced, and battle-tested, but it exists only to drive notification
fan-out (`Notifications::EventPublisher` → `NotificationEvent` →
`Notifications::ProcessEventJob` → `Notification`/`NotificationDelivery`
rows) — its payload shape and lifecycle are notification-specific, not a
general analytics contract. **Do not repurpose `NotificationEvent`
directly for analytics.** Do reuse its proven pattern: a durable outbox
row, `idempotency_key`-deduplicated, processed async, with a job that
survives partial failure (`Notifications::RecoverPendingJob` already
proves this pattern works at scale in this codebase).

### Recommended canonical event contract

A single `AnalyticsEvent` table (new), with a fixed context envelope and
a free-form `properties` jsonb, following exactly this codebase's existing
conventions (soft-delete not needed — events are immutable and append-only;
brand-scoped like everything else per ADR 0002):

```
analytics_events
  id
  event_id          uuid, unique (client-supplied, for de-dup on retry)
  event_type        string   e.g. "member.registered", "discover.requested"
  occurred_at       datetime
  brand_id          bigint, required (ADR 0002 — every event belongs to a brand)
  user_id           bigint, nullable (nullable: pre-account events, e.g. visitor)
  profile_id        bigint, nullable
  session_id        bigint, nullable, references sessions
  platform          string, nullable  (ios/android/web)
  app_version       string, nullable
  release           string, nullable  (git SHA / deploy version — see §9)
  country, region    string, nullable
  utm_source, utm_medium, utm_campaign   string, nullable
  properties        jsonb, default {}
  created_at
```

**Do not blindly implement the full example event list from the product
brief.** Recommend deriving the *initial* event set from what's already
observable as a side effect of existing domain services, which is nearly
all of it — e.g. `member.registered` fires from
`Identity::PasswordRegistration#create_account`, `match.created` fires
from wherever `Match.create!` happens today, etc. Each is a single
`AnalyticsEvents::Emit.call(...)` line added at an already-existing,
already-tested call site — not new business logic. Concretely, do NOT add:
- `discover.requested`/`discover.results_returned` as *separate* events
  from what `domains/matching/discovery.rb` already computes per-request —
  reuse the exact `DiscoveryAllocationCandidate` write that already
  happens today as the event, rather than a second redundant write.
- Any event whose only purpose is a metric already fully derivable from
  an existing table (see METRICS.md) — don't double-instrument.

### Platform-wide contract, not per-brand dialects

The product brief's most important instruction here: **do not let
DateZA/HookUs/Date9ja invent incompatible analytics languages.** Concretely:
`event_type` values, the context envelope columns above, and `properties`
key names for a given `event_type` are a **D8N platform capability**,
defined once in `domains/analytics/event_types.rb` (mirroring how
`Identity::AuthPolicy::SUPPORTED_METHODS` or
`Profiles::CapabilityCatalog` already centralize brand-agnostic
vocabulary while brands compose from it — ADR 0008's pattern, reused).
Brand-specific product surfaces (Hook Tonight, DateZA's curated openers)
emit the *same* `hook.sent`/`opener.sent` event types with brand-specific
`properties`, never a `dateza_opener.sent` variant.

### What NOT to build

No Kafka/event-streaming platform, no separate event-store database. A
Postgres table plus Solid Queue fan-out is enough at current scale and
matches every existing pattern in this codebase (Notifications, jobs).
Revisit only if write volume genuinely threatens the primary — see §10.

## 4. Observability / APM integration

**Current reality (CURRENT-STATE.md §10): zero observability
infrastructure exists** — no error tracker, no APM, no tracing, no log
aggregation. This is the strongest "DO NOT REBUILD" case in the whole
plan.

**Recommendation:** adopt one external vendor with Ruby/Rails support and
OpenTelemetry-compatible instrumentation (evaluate Sentry for errors +
one of Honeybadger/New Relic/Datadog for APM — the specific vendor choice
is a founder/cost decision, not an architecture decision, see ROADMAP.md
§ Open Questions). Once adopted:

- **HQ does not store traces, logs, or APM metrics itself.** It calls the
  vendor's read API (or receives their webhooks for
  errors/deploy-markers) and renders a summarized, D8N-correlated view —
  e.g. "this error's `member_id` property links to Member 360."
- **Error grouping into issues** (exception, occurrences, affected
  members/brands, first/last seen, release introduced, trend) is exactly
  what a mature error tracker already does — HQ's job is to attach D8N's
  own correlation keys (`brand_id`, `member_id`, `request_id`) as tags on
  every captured error/span, not to reimplement grouping.
- **Database/queue/infrastructure metrics** (§ Jobs, § Database in
  CURRENT-STATE.md) similarly should come from the chosen APM vendor's
  Postgres/Ruby integration rather than hand-rolled polling — Solid
  Queue's tables are directly queryable today as a stopgap (documented in
  `docs/operations/observability.md`) but should not become a permanently
  hand-maintained HQ dashboard once real APM exists.

### Correlation keys — audit of what exists today

| Concept | Exists today? | Where |
| --- | --- | --- |
| `request_id` | Yes | Rails default, tagged in production logs (`config/environments/production.rb`) |
| `brand_id` | Yes, everywhere | Every brand-owned table |
| `user_id` / `profile_id` | Yes, everywhere | Every product table |
| `session_id` | Yes | `Session` model |
| `trace_id` | **No** | Would come from whichever APM/OTel vendor is adopted |
| `job_id` | Partial | Solid Queue has internal job IDs; not currently propagated into app-level logs/events |
| `release` / deployed version | **No** | See §9 — this is a real, standalone gap blocking release correlation entirely |
| `notification_delivery_id` ↔ `external_id` (provider message id) | Yes | Already correlatable today, see CURRENT-STATE.md §6 |

**Recommendation:** once a `request_id` is available on a request, thread
it through to any `AnalyticsEvent` and any admin-action `SecurityEvent`
emitted during that request (single `Current.request_id` accessor, same
pattern as the existing `Current.brand`/`Current.user`). This is the one
piece of "context propagation" worth doing proactively; everything else
(`trace_id`, job correlation) should wait for the vendor choice so we
don't invent a correlation ID scheme the vendor's own SDK then makes
redundant.

## 5. Universal search architecture

**Do not build a dedicated search index (Elasticsearch or similar) for
V1.** Justification: the entities to search (members, reports, matches,
conversations, jobs, deployments) are a small, well-indexed set of
Postgres tables plus a couple of external systems (deployment history,
observability). A **federated query router** is sufficient and far
cheaper to operate correctly (no second datastore to keep consistent,
no reindexing pipeline, no separate authorization model to maintain):

```
SearchQuery
  │
  ├── looks like an email/phone/UUID/public_id → direct indexed lookups
  │     (IdentityIdentifier, Profile.public_id, Report.id, Match.public_id, ...)
  ├── looks like a request/trace/job id → forwarded to the observability
  │     vendor's own search API (once adopted, §4) or Solid Queue tables
  └── free text → deferred; not required for V1 (see below)
```

Every entity type in the product brief's search list already has a
natural unique key that's already indexed (`public_id` UUIDs throughout
this codebase, per its own conventions) — the router's job is dispatching
a query to the right table/service by input shape, and returning
authorization-filtered results. **Revisit a real search index only if/when
free-text search over message/report content becomes a real requirement**
— and if it does, that requirement collides directly with the
minimum-necessary-access principle in SECURITY-AND-RBAC.md and needs its own
privacy review before being built, not just an engineering ticket.

## 6. Member 360 architecture

Given CURRENT-STATE.md's finding that nearly every underlying table
already exists (profile, product usage, communications, safety, activity)
but almost nothing has an admin read API, Member 360 is fundamentally an
**aggregation service**, not new instrumentation:

```
Hq::Member360::Load.call(brand:, member: <id|email|phone>)
  → resolves identity (new capability, CURRENT-STATE.md #1.2)
  → IDENTITY   section: User, IdentityIdentifier(s), Session(s), BrandMembership(s)
  → PROFILE    section: Profile, ProfilePreference, ProfilePhoto(s), completeness (via
                 existing Profiles::OnboardingStatus, reused not reimplemented)
  → PRODUCT    section: Like/Pass/Match/Hook/HookTonightState/Conversation counts + recent
  → COMMS      section: NotificationDelivery rows (already has full per-channel state)
  → SAFETY     section: Report(s) made/received, AccountEnforcement history, AccountClosure
  → ACTIVITY   section: AuthAttempt/SecurityEvent rows for this user (already exist, write-only today)
  → ADMIN      section: any admin actions taken against this member (SecurityEvent, once read API exists)
```

Every section is a **thin read query against an existing table**, scoped
by brand and authorized via the same `Admin::ModeratorContext` used
today. No new product-side instrumentation is required to ship a
first version of Member 360 — see ROADMAP.md, this is the recommended
first vertical slice.

### "Why is Discover empty for this member?" diagnostic

Concretely buildable today because `DiscoveryAllocationCandidate.ranking_payload`
(jsonb) already exists and is written per-candidate, per-viewer, per-day
by the discovery engine (`domains/matching/discovery.rb`). The diagnostic
is: read the viewer's latest `DiscoveryAllocation` + candidates, and
separately re-run (read-only, in isolation) the `EligibilityScope` build
to show which filter step (gender/age/location/preferences/already-seen/
blocked) reduced the candidate pool at each stage. This is new code (an
explain-mode wrapper around the existing eligibility scope), but it
requires zero new persisted data.

## 7. Marketplace health architecture

All the core metrics in D8N-HQ-PLAN.md §8 (zero-impression rate, like rate,
match rate, conversation depth, time-to-first-X) are **derivable today**
from `DiscoveryAllocationCandidate`, `Like`, `Match`, `Conversation`,
`Message`, and `Profile` without new instrumentation — see METRICS.md for
exact definitions. The only architectural addition needed is the rollup
job pattern from §2 (pre-aggregate daily/weekly per
brand×country×gender×cohort, because computing these live from raw rows
at query time does not scale past a small dataset and risks the
"unsafe synchronous query" failure mode in §10).

## 8. Trust & Safety architecture additions

Given CURRENT-STATE.md §4's finding that `Report`/`AccountEnforcement`
are the most mature domain, the additions needed are small and additive
(no redesign of ADR 0018 or ADR 0013):

- **SLA/aging:** add nothing to the `reports` table for V1 — "age" is
  `Time.current - created_at`, computable in the existing serializer.
  A true SLA (target/breach) needs a `severity`→`target_duration` policy
  table, which is new but small, and should be scoped as its own ticket
  once case volume justifies it (currently: not urgent, beta-scale).
- **Repeat-offender aggregation:** a single new read-only query/endpoint
  — `GROUP BY reported_profile_id` over `reports`, no schema change.
- **Enforcement history:** a single new read-only endpoint over
  `AccountEnforcement`, no schema change.
- **Case/investigation timeline:** genuinely not needed at current
  report volume (beta-scale, per `D8N_NOW_NEXT_LATER.md`). Defer; the
  `evidence` jsonb + linked `report_id` on `AccountEnforcement` already
  gives moderators a one-hop trail today.

## 9. Deployment/release intelligence

**Blocked entirely on a real gap: there is no version/release stamping
anywhere in this codebase today** (CURRENT-STATE.md #9.7). Before any
"did this deploy hurt the product" question can be answered, D8N needs:

1. A `/api/v1/version` (or extend `/api/v1/health`) endpoint returning the
   deployed git SHA and deploy timestamp — trivially added via Kamal's
   `KAMAL_VERSION`/build-arg mechanism baked into the image at build time.
2. That SHA propagated as the `release` field on `AnalyticsEvent` (§3) and
   any adopted APM vendor's deploy-marker API (§4).

Once both exist, "error rate/latency/product-KPI before vs. after a
release" is a straightforward `WHERE release = ?` comparison — no new
architecture, just the two prerequisites above. This plan does not
implement either; it flags them as the literal first prerequisite for
this entire HQ section (see ROADMAP.md).

## 10. Performance / safety boundaries (explicit, not deferred)

Direct answer to the product brief's request to identify boundaries now
without prematurely building infrastructure for them:

- **Unsafe to run synchronously against production today:** any query
  spanning all brands' `reports`/`likes`/`matches` without a date bound;
  any full-table aggregate on `messages` (plaintext content column, high
  row count expected); any "compare cohort A vs B" query without a
  pre-materialized cohort table.
- **Needs a rollup, not a live query:** DAU/WAU/MAU, retention cohorts,
  marketplace health trends, funnel conversion — all of §7/§11/§12 in
  D8N-HQ-PLAN.md.
- **Needs event aggregation (post-§3), not just a rollup of existing
  tables:** acquisition/attribution, anything keyed on `utm_*` (doesn't
  exist as a column yet), pre-registration funnel steps (visitor →
  registration started).
- **Expensive cross-brand queries:** by definition, anything under an
  "All D8N" view — see SECURITY-AND-RBAC.md, this is also an authorization boundary,
  not just a performance one.
- **PII-sensitive searches / requiring elevated auth:** any Member 360
  load, any raw message content view (currently has no surface at all —
  keep it that way absent a specific, reviewed justification), any
  identity-lookup search.
- **Where caching/materialized views/read replicas will eventually help:**
  Command Centre's top-level scores (cache aggressively, refresh on a
  schedule, never compute live); a read replica becomes worth the
  operational cost only once HQ's own query volume is shown (via the
  adopted APM, §4) to be measurably competing with product traffic for
  primary DB capacity — not before.

## 11. Data health strategy

HQ must not let "Company Intelligence" (out of scope for this plan
entirely, see ROADMAP.md) reason over broken telemetry once it exists.
Concretely, once §3's event pipeline ships, HQ needs its own
self-monitoring: ingestion lag (event `occurred_at` vs. `created_at` on
the row), duplicate `event_id` rejection rate, unknown `brand_id`/`user_id`
references, rollup job freshness (last successful run timestamp per
rollup). This is explicitly a **Phase 4+ concern** (ROADMAP.md) — there is
no data pipeline to monitor yet, so building this now would be monitoring
nothing.

## 12. Cross-brand access boundary (the load-bearing open question)

Restated from D8N-HQ-PLAN.md §4 because it constrains every architectural
choice above: **every HQ query and every HQ API endpoint must take an
explicit brand parameter (or an explicit, audited "all brands" grant) —
there is no such thing as a brand-implicit HQ query.** Until SECURITY-AND-RBAC.md's
proposed resolution is decided and implemented, HQ's V1 "All D8N" view
(if built at all) can only be a *client-side fan-out* over N single-brand,
individually-authorized API calls — never a single query that silently
spans brands server-side. This is slower and less elegant than a real
cross-brand read path, and that's the point: it fails safe by
construction rather than depending on every future engineer remembering
not to write an unscoped query.
