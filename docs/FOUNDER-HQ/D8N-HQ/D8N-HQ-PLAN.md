# D8N HQ — Unified Company Command Centre

**Status: PLANNING. Nothing described here as "target" or "future" is
built.** Sections are explicitly labeled CURRENT REALITY, TARGET
ARCHITECTURE, or FUTURE/DEFERRED throughout — never assume a capability
exists because it's described in detail. This is the canonical,
self-contained D8N HQ plan; deeper engineering detail for each area lives
in the sibling documents linked throughout ([README.md](README.md) has
the full index).

---

## 1. Executive Summary

D8N HQ is the proposed unified command centre for operating D8N: one
surface to understand company state, drill into *why*, and act — instead
of the current reality, where understanding D8N requires reading founder
state files, running Rails console queries, and checking several
provider dashboards separately.

**Today, D8N HQ does not exist.** What exists is a real, working,
multi-brand dating platform backend (HookUs and DateZA live, Date9ja
planned) with a solid trust & safety domain, a solid notifications
domain, and almost no admin-facing visibility into any of it beyond a
narrow reports/photo-moderation/suspension API. There is no analytics
pipeline, no observability/APM, no billing, and no real identity
verification anywhere in the codebase. This plan is built directly on an
audit of that reality (§7), not aspiration, and its roadmap (§30–31) is
sequenced so the *first* thing built is genuinely useful today, using
data that already exists, rather than waiting for a full analytics/APM
stack.

## 2. Product Definition

> "Open D8N HQ and understand the state of the company in 60 seconds.
> Drill down and understand why in 5 minutes.
> Take action from the same place."

D8N HQ is not a rebuild of specialist tools. Specialist systems (an
observability vendor, an email/SMS provider, a payments processor) may
continue to exist underneath it, collecting and storing the detailed
telemetry they're good at. **D8N owns authoritative product, business,
and admin data. HQ aggregates, correlates, explains, and exposes it** —
and is where operators should actually live day to day, rather than
context-switching between five tools to answer one question.

## 3. North-Star Experience

None of the following is built. It is the design target §30's roadmap
builds toward, phase by phase.

**The Command Centre** (founder/operator homepage) answers: are we
winning or losing? What changed? What needs attention? It shows company
KPIs, brand performance, funnel performance, acquisition, revenue where
applicable, active users, marketplace activity, system health,
deployments, top errors, incidents, alerts, and D8N Intelligence
insights. Every card is expandable — see §6, the drill-down principle.

**Six top-level company scores** anchor it: Growth, Product, Revenue,
Customer, Safety, System. **A score is never a decoration.** Before any
score ships, it must have documented, versioned inputs, weights, a
target/baseline, a calculation version, an explanation, a trend, and a
drill-down path (§25 formalizes this). If its inputs aren't trustworthy
yet, it renders `UNKNOWN` / `NOT CONFIGURED` / `INSUFFICIENT DATA` — never
a manufactured number. Concretely, today: **Revenue Score has no data
source at all** (§7 — billing is an empty placeholder) and must render
`NOT CONFIGURED`, not zero, until billing exists.

Beyond the homepage: brands overview, business performance (growth,
product, marketplace), safety, systems, incidents, deployments, and
(much later, §27) intelligence — each its own area, all reachable from
the same command surface.

## 4. Product Principles

- **One operating surface.** Operators should not need to context-switch
  between D8N, provider dashboards, and Rails console to understand
  state.
- **No dead-end dashboards.** Every number drills down (§6). A metric
  with nowhere to go is a UI mistake, not a feature.
- **Evidence before conclusions.** Every claim HQ makes — a score, an
  alert, an intelligence answer — must be traceable to the underlying
  rows/events that produced it.
- **No fabricated metrics.** Missing data renders as missing data, never
  as zero, never as a plausible-looking placeholder.
- **Brand-aware by design.** Every metric, query, and action has explicit
  brand semantics from day one — see §8 and §9's cross-brand discussion.
  This is not a retrofit; it's foundational.
- **Backend authorization is authoritative.** HQ does not introduce a
  parallel authorization system. It calls the same
  `Admin::ModeratorContext` (and its eventual successor, §8) the product
  API already uses.
- **Specialist tools may exist underneath HQ.** HQ is the
  aggregation/control layer, not a from-scratch APM, log store, or
  tracing system (§17).

## 5. Information Architecture

Proposed navigation. **Not every item needs to exist in V1** — the
architecture must accommodate all of them without a rewrite, even where
a given page ships much later (§30).

- **Global:** Command Centre · Live/Events · Alerts · Incidents · Search
  Everything
- **Business:** Growth & Marketing · Product · Marketplace Health ·
  Revenue · Customers & Support · Executive Briefings
- **Trust:** Trust & Safety · Reports · Moderation · Verification ·
  Appeals · Enforcement
- **Engineering/Operations:** Reliability/SRE · APM/Observability ·
  Errors · Traces · Logs · Jobs & Queues · Database · Infrastructure ·
  Dependencies · Deployments · Data Health · Infrastructure Cost ·
  Security
- **Platform:** Brands · Brand Health · Admin/Operations · Admin Access ·
  Audit · Configuration · Integrations · Provisioning/Readiness
- **Intelligence:** Company Intelligence · Automated Insights · Anomaly
  Detection · Founder Mode

## 6. Drill-Down Model

The single most important architectural constraint in this plan: **no
dead-end dashboards.**

```
COMPANY → DOMAIN → METRIC → SEGMENT → EVENT → EVIDENCE → ACTION
```

**Business example:** Growth Score → Registrations → DateZA → Gauteng →
Organic → Mobile Safari → registration/onboarding conversion →
sessions/members/events.

**Technical example:** System Score → API → Messages → errors →
`NoMethodError` → release → trace → request → logs → affected members.

**Trust example:** Safety Score → Reports → Harassment → DateZA → case →
reported message → surrounding evidence → previous reports → enforcement
history → moderator action.

Every data/API decision in §9 onward is evaluated against whether it can
support this chain end to end. This is *why* Member 360 (§12) is
prioritized in the roadmap: the underlying evidence for the trust example
above (reports, enforcement history, evidence snapshots) already exists
in the database today — the chain is buildable now, not blocked on new
instrumentation.

## 7. Current D8N Reality

**Full detail and file-path evidence: [CURRENT-STATE.md](CURRENT-STATE.md).
This section is the executive summary; treat CURRENT-STATE.md as
authoritative if the two ever disagree.**

Legend: **READY** (production-grade, working API) · **PARTIAL** (some
code, real gap) · **MISSING** (not implemented) · **EXTERNAL** (belongs
to a vendor, not D8N) · **FUTURE** (deliberately deferred) · **DO NOT
REBUILD** (a mature capability exists elsewhere; adapt it, don't
reimplement it).

| Domain | Status | Notes |
| --- | --- | --- |
| Identity/Users (models, sessions) | READY | No admin lookup API exists at all — the single highest-leverage gap found (§12) |
| Brands / provisioning | READY | `Brands::Provisioner`, `bin/rails brands:provision[slug]` (this repo's Phase 1 work) — no `brands:doctor` readiness check yet |
| Admin / RBAC | PARTIAL | `AdminUser`/`AdminRole`/`AdminAssignment` exist and work; authorization is brand-scoped and role-name-blind (§8); no admin CRUD API; no dedicated audit read API |
| Trust & Safety (reports, enforcement, photo moderation) | READY (most mature domain) | Full `Report` model (ADR 0018), admin queue/detail/transition API, `AccountEnforcement` suspend/reinstate API. Missing: SLA/aging, repeat-offender aggregation, enforcement-history query — all *derivable*, no new tables needed |
| Identity/selfie/ID verification | **MISSING — a real product gap, not an HQ gap** | Only email/phone OTP possession checks exist; no `Verification`/`UserVerification` model anywhere |
| Dating loop (profiles, discovery, likes, matches, hooks, conversations, blocks) | READY (member-facing) | Zero admin read surface for any of it. Discovery's per-candidate ranking data is already persisted (`DiscoveryAllocationCandidate`) — the "why is discovery empty" diagnostic (§12) needs an API, not new data |
| Notifications & delivery | READY | Full per-channel delivery state machine (email/SMS/push), Resend + Twilio integrated. No provider delivery/bounce webhook ingestion. Push is intentionally fail-closed (no APNs/FCM provider) |
| Media/storage (R2) | READY | Upload/process/purge pipeline solid (EXIF strip, dimension guards). No storage cost/usage visibility (provider-API integration, EXTERNAL) |
| Jobs/queues | READY (Solid Queue) | Zero operator visibility beyond raw SQL against Solid Queue's own tables |
| Database/infra | READY (Postgres 17, Kamal) | **No release/version stamping anywhere** — blocks all deployment-intelligence work (§19) |
| Observability/APM/Errors/Traces/Logs | **MISSING** | Zero error-tracking/APM/tracing gems installed anywhere. Logging is stdout-only, not aggregated. **This is the strongest "do not rebuild from scratch" case in the whole plan** — adopt a vendor (§17) |
| Analytics/Events | **MISSING** | `domains/analytics/` is an empty placeholder. No canonical event system, no analytics gem, zero acquisition/UTM capture anywhere |
| Revenue/Billing | **MISSING (deliberately, current priority)** | `domains/billing/` is an empty placeholder. No Subscription/Payment/Stripe code exists |
| Support/Customer Service | **MISSING** | No ticketing system or model |
| Rate limiting / abuse protection | READY (auth + product-action) | Comprehensive, DB-backed. No general HTTP-layer limiter (Rack::Attack) yet; no admin read API over the audit tables it writes |
| CI/CD quality signals | READY | Brakeman, bundle-audit, Rubocop, Zeitwerk, full test suite all run in CI; no HQ-visible feed of these results |

## 8. Current Admin / Authorization Reality

**Full detail: [SECURITY-AND-RBAC.md](SECURITY-AND-RBAC.md) §1–2. This
is the single most consequential fact in this entire plan and must not be
glossed over.**

Audited directly from `domains/admin/moderator_context.rb`,
`app/models/admin_{user,role,assignment}.rb`, and ADR 0013:

- **Authorization is currently brand-scoped only.** There is no concept
  of a platform-wide/cross-brand admin anywhere in the codebase.
- **Role names currently do not provide differentiated authorization.**
  `Admin::ModeratorContext.resolve` checks only: is there a kept, active
  `AdminUser`, with a kept, active `AdminAssignment` for *this specific
  brand* — full stop. The `AdminRole.name` on that assignment
  (`"moderator"`, the only role that exists today) is never read by any
  authorization check. **Any admin role currently grants full moderation
  and enforcement power for its brand.** This is explicit and intentional
  per ADR 0013: "differentiated admin RBAC is deliberately deferred until
  more roles genuinely exist."
- **There is no genuine platform-wide founder role today.** Admins sign
  in as an ordinary `User` through the ordinary brand-scoped session and
  need an active `BrandMembership` on a brand to administer it at all —
  same code path as any member. This repo's own Phase 2 work
  (`Admin::FounderBootstrap`, `bin/rails d8n:bootstrap_founder`)
  deliberately does not invent a platform-wide role; it promotes one
  identity to the existing per-brand `moderator` role on every active
  brand, one assignment at a time.
- **Admin MFA does not exist**, and is an explicit, still-open pre-launch
  gate (`D8N_NOW_NEXT_LATER.md`).
- **Cross-brand HQ authorization remains an open architectural
  decision**, not resolved by this plan (§9, §32).

HQ makes every one of these facts more consequential, not less — a tool
whose purpose is "see and act on everything, across every brand, in one
place" is exactly the tool that turns "any admin role grants full power
for its brand" and "no MFA" from acceptable beta-scale risks into the
central risk of the whole product.

## 9. Target HQ Architecture

**Full detail: [ARCHITECTURE.md](ARCHITECTURE.md).**

```
D8N HQ Web                         (new frontend, per ADR 0004's API-only-core pattern)
        │
D8N HQ API / query layer           (new namespace inside the existing d8n Rails app — see below)
        │
        ├── Operational D8N data       — existing tables, read via scoped queries (READY today)
        ├── Analytics / metric layer   — new: versioned metric definitions (§25)
        ├── Canonical events           — new: event pipeline (§26)
        ├── Observability adapters     — new: reads an external vendor's API (§17)
        ├── Provider adapters          — new: Resend/Twilio/R2 status APIs (§21)
        ├── Deployment/release data    — new: version stamping + Kamal/GitHub API (§19)
        ├── Alerts/incidents           — FUTURE, after data is trustworthy (§20)
        └── Company Intelligence       — FUTURE, last (§27)
```

**One load-bearing decision this plan does commit to:** HQ is a
read/aggregate layer over D8N's existing operational database plus a
small number of new purpose-built tables (events, metric snapshots) — it
is **not** a second system of record. D8N DB stays authoritative for
product/business/admin data.

**Where does it live?** Recommendation: a new namespace inside the
existing `d8n` Rails app (`app/controllers/api/v1/hq/`, `domains/hq/`),
not a separate service — D8N is a modular monolith by deliberate choice
(ADR 0001), and a separate HQ service would mean solving cross-service
auth for a tool with, at launch, a handful of trusted operators. Revisit
only if HQ's query load is shown to risk product-API latency (§29).

**Belongs in D8N vs. stays in a specialist system:**

| Concern | Lives in |
| --- | --- |
| Product/business/admin data of record | D8N DB (always) |
| Distributed tracing, log storage, APM metrics | An adopted observability vendor — HQ links into it, never stores traces/logs itself |
| Email/SMS delivery mechanics | Resend/Twilio — HQ reads D8N's own `NotificationDelivery` state, which already tracks provider responses |
| Payments | A future payments provider, once billing exists — not built |
| Free-text/full-text search infrastructure | Deferred (§10) — no dedicated search index unless the federated router proves insufficient |

**What NOT to build, restated for emphasis:** no Kafka/event-streaming
platform, no separate analytics database, no in-house tracing/log
storage engine, no Elasticsearch cluster — see §26 and §17.

## 10. Universal Search

**Do not build a dedicated search index for V1.** The entities to search
(members, reports, matches, conversations, jobs, deployments) are a
small, well-indexed set of Postgres tables, most already keyed by a
`public_id` UUID by this codebase's own convention, plus a couple of
external systems (deployment history, observability). A **federated
query router** dispatches by input shape (email/phone/UUID → direct
lookup; request/trace/job ID → forwarded to the observability vendor or
Solid Queue tables; free text → deferred entirely for V1) and returns
authorization-filtered results. Revisit a real search index only if
free-text search over message/report content becomes a real requirement
— and if it does, that collides directly with the minimum-necessary-
access principle (§23) and needs its own privacy review first, not just
an engineering ticket. Full design: [ARCHITECTURE.md §5](ARCHITECTURE.md).

## 11. Live Event Stream

Target: an authorized, real-time operational activity view
(`member.registered`, `match.created`, `report.created`,
`job.failed`, `admin.action_performed`, etc.), filterable by brand, event
type, severity, member, environment, release, time — **must not become an
uncontrolled PII firehose** (§23). This depends entirely on the canonical
event pipeline (§26) existing first; it is not separately buildable
before that. Not scoped further in this plan — see §33.

## 12. Member 360

A complete, authorized operational view of one member: identity, profile,
product usage, communications (delivery state), safety (reports,
enforcement, appeals), activity (logins, sessions, lifecycle events), and
admin actions/audit history.

**This is fundamentally an aggregation service, not new
instrumentation.** CURRENT-STATE.md's central finding is that nearly
every underlying table Member 360 needs already exists and is already
populated by the live product — what's missing is the read API, not the
data. This is why it's the recommended first vertical slice (§31).

Should eventually answer **"why is Discover empty for this member?"** by
showing the real funnel: candidate pool → gender filter → age filter →
location filter → preferences → already-seen → blocked → eligibility →
final returned candidates. This is concretely buildable today because
`DiscoveryAllocationCandidate.ranking_payload` (jsonb) is *already*
written, per-candidate, per-viewer, per-day, by the live discovery engine
— the diagnostic is an explain-mode read over data that's already being
generated, not a new instrumentation project. Full design:
[ARCHITECTURE.md §6](ARCHITECTURE.md).

## 13. Marketplace Health

Active supply by gender/preference/geography, discovery inventory,
impressions/member, zero-impression/zero-like/zero-match rate, like rate,
reciprocal like/match rate, match→conversation, conversation depth, reply
rate, time-to-first-impression/like/match/conversation, geographic and
new-member liquidity. Segmentable by brand, country, region, city, gender,
age band, preference, platform, acquisition source, cohort, release.

**Nearly all of this is derivable today** from `Like`, `Match`,
`Conversation`, `Message`, `DiscoveryAllocation`, and `Profile` — no new
instrumentation required, only a rollup job (§29) so these aren't
computed live on every page load. Exact definitions: [METRICS.md §3](METRICS.md).

## 14. Growth & Marketing

Traffic, acquisition (organic/direct/referral/paid), campaign economics
(spend → impressions → clicks → registrations → activated members →
matches → conversations → retained members → revenue later). Principle:
**optimize for cost per valuable member, not cost per registration** — a
valuable member completes onboarding, publishes, participates in
discovery, matches, converses, and returns.

**Reality check: zero attribution data exists today.** No `utm_source`,
`referrer`, or `acquisition_source` field exists anywhere in the schema.
This entire domain is `NOT AVAILABLE` until registration captures
acquisition context — a small, well-scoped backend change (§33), not an
HQ-side problem.

## 15. Product Funnels / Retention

**Funnel:** Visitor → Registration started → Registration completed →
Onboarding started → Onboarding completed → Profile published → First
discovery → First like → First match → First conversation → Meaningful
conversation → Retained member → Paid member (later). Segmentable by
brand, acquisition source, campaign, geography, platform, device, gender,
age, cohort, release, verification, profile completeness.

**Reality check:** "Visitor" and "Registration started" are not
observable today — there is no pre-account event capture. Everything from
"Registration completed" onward is measurable now using existing tables;
everything before needs the event system (§26) first.

**Retention:** DAU/WAU/MAU, stickiness, D1/D7/D30, cohort retention,
resurrection, churn, sessions/likes/matches/conversations/messages per
member. HQ should eventually explain *why* retention changed, which
cohort changed, what correlates with retention, which acquisition
sources produce retained members, which releases correlate with
deterioration/improvement. DAU/WAU/MAU are buildable today from `Session`
timestamps (a first-pass "active" definition — see [METRICS.md](METRICS.md));
release correlation is blocked on §19 (no version stamping exists yet).

## 16. Trust & Safety

**This is the most mature domain in the backend today** — full detail:
[CURRENT-STATE.md §4](CURRENT-STATE.md), [ARCHITECTURE.md §8](ARCHITECTURE.md).

`Report` (ADR 0018) and `AccountEnforcement` (ADR 0013) are fully
modeled, tested, and have a working admin API
(`GET/PATCH /api/v1/admin/reports`,
`POST/DELETE /api/v1/admin/profiles/:id/suspension`). What's missing for
HQ specifically, and why each is small and additive (no schema redesign
needed):

- **SLA/aging** (open cases, overdue cases, age of oldest case) — "age"
  is `Time.current - created_at`, computable today with no schema
  change; a true SLA target/breach concept is new but small, and not
  urgent at current (beta) report volume.
- **Repeat-offender aggregation** and **reports/1k members** — a single
  new `GROUP BY` query/endpoint over the existing `reports` table.
- **Enforcement history** (per member, per brand) — a single new
  read-only endpoint over `AccountEnforcement`, no schema change.
- **Case/investigation timeline** — genuinely not needed at current
  volume; the existing `evidence` jsonb snapshot + linked `report_id` on
  `AccountEnforcement` already gives moderators a one-hop trail.

**Verification review is not buildable** — there is no identity
verification of any kind (only email/phone OTP possession checks). Don't
plan an HQ "verification review" page around anything beyond OTP delivery
status until real verification exists as a product capability.

**Privacy principle (see §23 in full):** moderators/operators get the
minimum sensitive information necessary. Message content is plaintext
today with **no admin retrieval endpoint at all** — that absence is a
deliberate current safety property, not a gap to casually fix with a raw
conversation viewer.

## 17. APM / Observability

**Zero observability infrastructure exists today** — no error tracker,
no APM, no tracing, no log aggregation (confirmed: zero relevant gems in
`Gemfile`; logging is stdout-only). This is the strongest "do not build
from scratch" case in the entire plan.

**Recommendation:** adopt one external vendor with Ruby/Rails support and
OpenTelemetry-compatible instrumentation where practical (a specific
vendor choice is a founder/cost decision — §32, not decided here). Once
adopted, HQ does not store traces/logs/APM metrics itself — it calls the
vendor's read API (or receives webhooks) and renders a summarized,
D8N-correlated view, tagging every captured error/span with D8N's own
correlation keys (`brand_id`, `user_id`, `request_id` — all already
exist; `trace_id` and release/version do not yet, see §19). Error
grouping into issues, request-level percentile metrics, database/queue
diagnostics — all of this is what a mature vendor already does well; HQ's
job is correlation and D8N-specific context, not reimplementation. Full
design: [ARCHITECTURE.md §4](ARCHITECTURE.md).

## 18. Error Intelligence

Once a vendor is adopted (§17), an "issue" view (exception, occurrences,
affected members/brands, first/last seen, release introduced, trend,
related traces/logs/deployment) is the vendor's native capability, with
D8N correlation keys attached at capture time. Not separately built by
HQ; not scoped as its own phase — it ships as part of §17's adoption, see
[ROADMAP.md Phase 3](ROADMAP.md).

## 19. Deployments / Release Correlation

**Blocked entirely on a real, standalone gap: there is no
version/release stamping anywhere in this codebase today** — no
`/version` endpoint, no `REVISION` file, no deployed-git-SHA mechanism of
any kind. Before "did this deploy hurt the product" can be answered, two
prerequisites, both small:

1. A version endpoint returning the deployed git SHA + deploy timestamp
   (trivial via Kamal's build-arg mechanism).
2. That SHA propagated as a `release` tag on captured errors (§17) and,
   once it exists, on analytics events (§26).

Once both exist, before/after comparisons on a release are a
straightforward `WHERE release = ?` query — no further architecture
needed. This plan does not implement either; they are Phase 0 of
[ROADMAP.md](ROADMAP.md), the literal first prerequisite for this whole
section.

## 20. Incident Centre

Target: incident ID, severity, status, affected service/brand(s)/members,
start/end, business impact, technical signals, related alerts/errors/
deployment, logs/traces/jobs, timeline, resolution. Correlates technical
failure with product/customer impact. **Deferred** — depends on §17
(observability), §19 (release correlation), and a real alerting system
(§25's "Alerting/Attention Engine" was descoped from this plan's
sections per §33) all existing first. Not scoped further here.

## 21. Provider / Communication Health

**Email:** sent/delivered/bounced/failed, delivery rate by
event/template/brand, provider status. **Mostly ready today** —
`NotificationDelivery` already tracks per-delivery provider responses
(Resend `external_id`, error codes) — but D8N does not consume Resend's
own delivery/bounce/complaint webhooks, so status past "accepted by
Resend" is unknown to D8N. Same gap for **SMS** (Twilio) — send-side
tracking exists, delivery-receipt webhooks don't. **Push** is
intentionally fail-closed today: `DeviceRegistration` is fully populated,
but no APNs/FCM provider is integrated, so every push attempt fails with
`provider_not_configured` by design. **Media/storage:** the upload/
process/purge pipeline is solid; storage usage/cost visibility would need
a Cloudflare R2 billing-API integration (EXTERNAL, not built).
Recommendation throughout: prefer provider APIs + D8N's own delivery
events over duplicating provider systems — see [CURRENT-STATE.md §6–7](CURRENT-STATE.md).

## 22. Data Health

HQ must not let future Company Intelligence (§27) reason over broken
telemetry. Once the event pipeline (§26) exists, HQ needs its own
self-monitoring: ingestion lag, duplicate-event rejection rate, unknown
brand/member references, rollup-job freshness. **Explicitly a
post-event-pipeline concern** — there is no data pipeline to monitor yet,
so building this now would monitor nothing. Scoped alongside the event
pipeline phase in [ROADMAP.md](ROADMAP.md), not before.

## 23. Security Centre

Visibility into failed logins, suspicious authentication, password
recovery events, rate limiting/abuse throttling, admin authentication,
admin privilege changes, sensitive lookups, security alerts. **Distinct
from Trust & Safety** — Trust & Safety is member/community safety;
Security is platform/account/administrative security.

The underlying data is fully written today and completely unreadable
outside Rails console: `AuthAttempt` (throttle audit) and `SecurityEvent`
(15+ event types across identity/admin/account domains) are both
write-only, with zero admin read API over either. Closing that read gap
is itself the first real Security Centre deliverable — no new
instrumentation needed, same pattern as Trust & Safety's gaps (§16).

**Every privileged HQ action must be auditable**, answering WHO, WHAT,
WHEN, WHY, TARGET, BRAND, BEFORE, AFTER, IP/session — exactly the fields
already present on `AccountEnforcement` today. **Sensitive reads may also
require auditing:** a Member 360 load that surfaces safety history should
itself emit a `SecurityEvent`, the same way viewing a report's full
evidence already does. Full design and the minimum-necessary-access
principle (message content, in particular): [SECURITY-AND-RBAC.md](SECURITY-AND-RBAC.md).

## 24. Brand Control Centre

Every brand should eventually have its own command page: status
(environment/readiness/health), product (users, discovery, matches,
conversations, retention), growth (traffic, registrations, acquisition),
safety (reports, verification, moderation), systems (errors, latency,
queues, dependencies), configuration (profile contract, capabilities,
notifications, discovery policy), and provisioning (installed
capabilities, domain resolution, profile catalogue, readiness state,
history).

**This builds directly on the existing `Brands::Provisioner`
architecture** (`domains/brands/{provisioner,dateza_installer,
hookus_installer}.rb`, `bin/rails 'brands:provision[slug]'` — this repo's
own Phase 1 work). A future read-only `brands:doctor`/readiness check
should be built as a sibling to `Provisioner`, reusing its pattern, not a
rewrite. No such readiness task exists yet.

## 25. Metric Semantic Layer

**Full detail: [METRICS.md](METRICS.md).**

The rule: **one definition per metric, versioned, tested, reused
everywhere** — every dashboard card and every future Company Intelligence
answer calls the same registry entry, never writes its own SQL for a
metric that already has one. This prevents the failure mode where two HQ
cards disagree about "active member" because one query used `status:
active` and another used "logged in in the last 30 days."

Design: a metric registry (`Hq::Metrics::X`), each entry a class with a
fixed id, a `VERSION` integer (bumped, not silently redefined, on any
definition change), a human `DEFINITION` string shown in the UI next to
the number, and a `compute` method — with a unit test asserting a fixed
value against a fixed fixture, exactly like every other domain service in
this codebase. A metric without a test cannot back a Command Centre
score. Canonical definitions already specified for `registered_member`,
`activated_member`, `published_member`, `active_member`, `DAU/WAU/MAU`,
`retained_member` (D1/D7/D30), `match_rate`, `conversation_rate`,
`zero_result_rate`, `report_rate`, `delivery_rate`, and several
time-to-first-X metrics — all `DERIVABLE` today from existing tables. Cost/
acquisition-channel metrics are explicitly `NOT AVAILABLE` pending §14's
prerequisite.

## 26. D8N Event Model

**Full detail: [ARCHITECTURE.md §3](ARCHITECTURE.md).**

**Current reality: no canonical product-analytics event system exists.**
`NotificationEvent` is real and proven, but purpose-built for
notification fan-out only — its shape and lifecycle are
notification-specific, not a general contract. **Reuse its proven
pattern** (a durable outbox row, idempotency-key-deduplicated, processed
async, with a recovery job) rather than repurposing the model itself.

**Proposed contract:** a single `AnalyticsEvent` table with a fixed
context envelope (`event_id`, `event_type`, `occurred_at`, `brand_id`
required, `user_id`/`profile_id`/`session_id` nullable, `platform`,
`app_version`, `release`, `country`/`region`, `utm_*`, free-form
`properties` jsonb). **Do not blindly implement the full example event
list from the original product brief** — derive the initial event set
from existing domain-service call sites (registration, onboarding,
publish, discovery, like, match, conversation, message, report), adding
one `AnalyticsEvents::Emit.call(...)` line at each already-tested call
site, not new business logic. Do not double-instrument anything already
fully derivable from existing tables (§25).

**Platform-wide contract, not per-brand dialects — the brief's most
important instruction here:** event types, the context envelope, and
`properties` key names for a given event type are a D8N platform
capability, defined once and composed from by brands — mirroring how
`Identity::AuthPolicy::SUPPORTED_METHODS` and
`Profiles::CapabilityCatalog` already centralize brand-agnostic
vocabulary today (ADR 0008's pattern, reused). DateZA/HookUs/Date9ja
never invent their own event language.

**Correlation identifiers that already exist:** `request_id`, `brand_id`,
`user_id`/`profile_id`, `session_id`, and (for notifications)
`external_id` from the provider. **Do not exist yet:** `trace_id`
(depends on §17's vendor choice), `release` (§19), consistent job-level
correlation. **What NOT to build:** no Kafka/streaming platform, no
separate event-store database — a Postgres table plus Solid Queue fan-out
matches every existing pattern in this codebase and is sufficient at
current scale.

## 27. Company Intelligence

Target questions: "Are we winning?" "Anything worrying today?" "Why did
DateZA retention fall?" "Which acquisition channel gives the best
members?" "Did the latest deployment affect onboarding?" "Compare DateZA
and Date9ja." The intelligence layer must reason from authoritative D8N
metrics and observable evidence, and must be able to show *why* it
reached a conclusion.

**Explicitly comes last, and is not scoped by this plan at all.** It
requires the metric semantic layer (§25) and event pipeline (§26) to
already be trustworthy — reasoning over broken or fabricated telemetry is
worse than no intelligence layer at all. See [ROADMAP.md](ROADMAP.md)
Phase 7+.

## 28. Founder Mode

Target: an executive compression layer reducing the whole company to
OVERALL ("are we winning?"), WINNING (what improved), LOSING (what
deteriorated), WATCH (what may become a problem), SYSTEMS (is D8N
healthy), TODAY (what happened), ATTENTION (what needs a decision), and
INTELLIGENCE (what D8N thinks is worth investigating) — never hiding the
underlying evidence it's compressing. Depends on the Command Centre (§3)
and Company Intelligence (§27) existing first. Not scoped further here.

## 29. Performance / Scale / Safety

**HQ must never become a production outage generator.** Concrete
boundaries, not deferred to "later":

- **Unsafe to run synchronously against production:** any query spanning
  all brands' reports/likes/matches without a date bound; any full-table
  aggregate on `messages` (plaintext, high row count); any cohort
  comparison without a pre-materialized cohort table.
- **Needs a rollup, not a live query:** DAU/WAU/MAU, retention cohorts,
  marketplace-health trends, funnel conversion.
- **Needs event aggregation, not just an existing-table rollup:**
  acquisition/attribution, anything keyed on `utm_*` (doesn't exist as a
  column yet), pre-registration funnel steps.
- **Expensive cross-brand queries:** by definition, anything under an
  "All D8N" view — this is an authorization boundary as much as a
  performance one (§8).
- **PII-sensitive / needs elevated auth:** any Member 360 load, any raw
  message-content view (has no surface today — keep it that way absent
  specific, reviewed justification), any identity-lookup search.
- **Where caching/materialized views/read replicas eventually help:**
  Command Centre's top-level scores (cache aggressively, refresh on
  schedule, never compute live); a read replica is worth its operational
  cost only once measured HQ query volume is shown (via the adopted
  observability vendor) to compete with product traffic for primary DB
  capacity — not before.
- **Analytics storage:** a Postgres table (§26), not a new datastore,
  until proven insufficient.
- **Failure isolation / HQ availability:** HQ being down or slow must
  never degrade the product API — living in the same Rails app (§9) means
  this has to be enforced by query discipline (the rules above), not by
  physical isolation, until/unless HQ's load genuinely justifies
  splitting it out.

Full design reasoning: [ARCHITECTURE.md §2 and §10](ARCHITECTURE.md).

## 30. Implementation Roadmap

**Full detail with exact backend/frontend tickets:
[ROADMAP.md](ROADMAP.md).**

Sequencing is derived from three dependency chains found in the audit,
not from copying the brief's suggested phase order verbatim:

1. Nothing cross-brand can ship before the authorization boundary is
   decided (§8, §32).
2. Nothing release/deploy-correlated can ship before version stamping
   exists (§19).
3. Nothing analytics/growth/retention-shaped can ship before the event
   pipeline exists (§26) — but Trust & Safety and Member 360 need **no
   new instrumentation at all**, which is why they come first, ahead of
   Command Centre itself.

**Phases:** 0. Decisions & prerequisites (no product code) → 1. Member
360 + admin read foundation (**first vertical slice**, see §31) → 2.
Trust & Safety command surface → 3. System health / observability
foundation → 4. Deployment/release intelligence → 5. Event pipeline +
marketplace health + funnel → 6. Command Centre + top-level scores →
7+. Everything blocked on a separate product decision (revenue,
verification, support, attribution, cross-brand drill-down, Company
Intelligence) — see §33.

## 31. First Vertical Slice

**Build Member 360 + admin read foundation first, alone, before any
Command Centre work.**

**Why:**

1. It requires **zero new instrumentation and zero new architecture
   decisions** — every table it reads already exists and is already
   correctly populated by the live product.
2. It closes the single gap that showed up most consistently across the
   entire audit: there is currently **no admin-facing way to look up a
   member at all**, for anything.
3. It's real, immediate operational value for the live HookUs beta today
   — not a demo.
4. It establishes the `api/v1/hq/` namespace, the
   `Admin::ModeratorContext`-based HQ authorization pattern, and the
   sensitive-read-auditing convention that every later phase reuses.
5. It directly builds the "why is Discover empty" diagnostic (§12, §6)
   the product brief singled out as an important operability goal — and
   it's the one place in the whole roadmap buildable with zero new data.

**Backend tickets:**
- **HQ-101** `Hq::Identity::Lookup` — resolve a member within one brand
  by email, phone, or `public_id`; returns `nil` cleanly (no
  enumeration).
- **HQ-102** `Hq::Member360::Load` — six-section aggregator (Identity,
  Profile, Product, Comms, Safety, Activity), one read query per section,
  brand-scoped.
- **HQ-103** Read endpoint: `SecurityEvent` + `AuthAttempt` history for
  one member.
- **HQ-104** Read endpoint: `AccountEnforcement` history for one member.
- **HQ-105** `api/v1/hq/members` controller wiring HQ-101–104 into
  `GET /api/v1/hq/members/:lookup` + section sub-resources.
- **HQ-106** Sensitive-read audit: every HQ-105 call emits a
  `SecurityEvent` (`hq.member_360_viewed`).
- **HQ-107** Tenant-isolation test suite: brand-A moderator cannot reach
  brand-B member data via any HQ-105 route.

**Frontend tickets:**
- **HQ-F01** HQ frontend shell, auth via the existing brand-scoped
  session, brand switcher scoped to the operator's actual
  `AdminAssignment`s (no free-text "All D8N" yet).
- **HQ-F02** Search box → member lookup, calling HQ-105.
- **HQ-F03** Member 360 page: six collapsible sections, explicit
  empty/`INSUFFICIENT DATA` states (never a blank crash for a member with
  no photos, no matches, etc.).
- **HQ-F04** "Why is Discover empty" expandable card within the Product
  section (fast-follow within the same phase if not ready day one).

**Acceptance criteria:** an operator can find any HookUs or DateZA member
by email and see accurate profile/product/safety state, for a brand they
have an active `AdminAssignment` on, and nothing for a brand they don't.

**What becomes usable at completion:** the actual, daily-useful "look up
this user and see what's going on" tool — replacing a large share of
today's Rails-console-driven support/moderation work.

## 32. Open Decisions

Collected from throughout this plan; each requires a founder/architecture
decision before the relevant phase can start:

1. **Cross-brand authorization** (§8, [SECURITY-AND-RBAC.md §2](SECURITY-AND-RBAC.md)):
   confirm the V1 approach — per-brand fan-out only, no new cross-brand
   grant — or commission the platform-level-grant ADR now instead of
   deferring it.
2. **Observability vendor** (§17): which one, and budget.
3. **HQ frontend placement:** new standalone app, or a section of
   whatever admin frontend gets built first.
4. **Admin MFA timeline:** before or in parallel with Phase 1 — Member
   360 itself is sensitive enough to want this resolved first, not after.
5. **Score weights/targets** (§25): the six top-level scores' actual
   formulas are a founder/product call, needed before Phase 6, not
   before.
6. **Revenue/verification/support/attribution timing:** each is blocked
   on a separate, larger product decision (build billing? build real
   verification? adopt a support tool? add campaign tracking?) entirely
   outside HQ's scope — HQ cannot make these capabilities exist by
   wanting to display them.

## 33. Deferred Work

Explicitly **not** built or further scoped by this plan, each blocked on
a named prerequisite:

- **Revenue/billing views** — blocked on billing existing at all.
- **Verification review** — blocked on real identity verification
  existing at all.
- **Growth/acquisition/campaign economics** — blocked on attribution
  capture being added at registration.
- **Support/Customer Service surface** — blocked on a support system
  existing.
- **Infrastructure cost/unit economics** — blocked on provider billing
  API integrations.
- **Universal free-text search / dedicated search index** — only if the
  federated router (§10) proves insufficient.
- **Cross-brand ("All D8N") drill-down beyond fan-out** — blocked on the
  platform-level-grant decision (§32.1).
- **Live Event Stream (§11), Incident Centre (§20), Alerting/Attention
  Engine, Company Intelligence (§27), Founder Mode (§28), Executive
  Briefings** — each explicitly named as coming after the data
  foundations in Phases 1–6 are trustworthy; none is sequenced further in
  this plan.

Also explicitly out of scope for *this planning pass itself* (per the
originating brief): building the HQ UI, dashboard endpoints, installing
any observability vendor, implementing OpenTelemetry, implementing the
analytics event pipeline, implementing Company Intelligence or anomaly
detection, redesigning D8N authentication, or inventing platform-wide
founder authorization.
