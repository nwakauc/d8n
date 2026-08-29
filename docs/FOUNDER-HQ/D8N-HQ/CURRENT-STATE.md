# D8N HQ — Current-State Capability Matrix

Status: **CURRENT REALITY.** Audited directly against the repository at
`/Users/uchechinwaka/pro/d8n` on 2026-08-29 (code, schema, routes, tests,
Gemfile, CI, Kamal config — not inferred from model/file names alone).
Every row below can be traced to a file path. Where a claim could not be
verified against actual behavior (not just a model existing), it is
marked `PARTIAL` or `MISSING` even if a plausible-sounding class exists.

Legend —
**Status:** READY (production-grade, working API) · PARTIAL (some code,
real gap) · MISSING (not implemented) · EXTERNAL (belongs to a
vendor/provider, not D8N) · FUTURE (deliberately deferred elsewhere) ·
DO NOT REBUILD (a mature capability exists elsewhere; HQ should adapt it,
not reimplement it).
**Data:** LIVE (real-time queryable) · HISTORICAL (persisted, queryable
after the fact) · EVENT NEEDED (requires new instrumentation) · DERIVABLE
(computable from existing tables without new instrumentation) · NOT
AVAILABLE.
**Source:** D8N DB · D8N EVENT PIPELINE (doesn't exist yet) · OBSERVABILITY
SYSTEM (doesn't exist yet) · PROVIDER API · DEPLOYMENT SYSTEM · OTHER.

---

## 1. Identity / Users

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 1.1 | User/IdentityIdentifier/Credential models | READY | LIVE | D8N DB | `app/models/{user,identity_identifier,credential}.rb` |
| 1.2 | Admin-facing member lookup API (by id/email/phone) | **MISSING** | NOT AVAILABLE | — | No controller under `app/controllers/api/v1/admin/` does this; `config/routes.rb` admin namespace has only `reports`, `profile_photos`, `suspensions` |
| 1.3 | Session/device tracking | READY | LIVE+HISTORICAL | D8N DB | `app/models/session.rb` — token-hashed, 30-day TTL, revocable |
| 1.4 | Auth attempt / throttle audit | READY (write-only) | HISTORICAL | D8N DB | `app/models/auth_attempt.rb`; recorded by `domains/identity/password_audit.rb`; **no read API** |

**Gap for HQ:** Member 360 and Universal Search both need #1.2 — a basic
"find this person" admin read path does not exist at all today, for any
brand, for any field. This is the single highest-leverage missing piece.

## 2. BrandMembership / Brands / Provisioning

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 2.1 | `Brand`, `BrandDomain`, `BrandMembership` models | READY | LIVE | D8N DB | `app/models/{brand,brand_domain,brand_membership}.rb` |
| 2.2 | Reproducible brand provisioning | READY | — | — | `domains/brands/{provisioner,dateza_installer,hookus_installer}.rb`, `bin/rails 'brands:provision[slug]'` (this repo's Phase 1 work — see § Recently landed work below) |
| 2.3 | Brand readiness/health check ("brands:doctor") | **MISSING** | — | — | No such rake task exists; confirmed by grep. Only generic `/api/v1/health` (DB connectivity, not brand-specific) |
| 2.4 | Per-brand feature/config surface (auth methods, profile catalog, capabilities) | READY (code, not DB) | LIVE | D8N DB (Brand row) + code (`BrandRegistry`, `Profiles::*ProfileCatalog`) | Intentional — see ADR 0002/0006/0008; this is correct today, not a gap |

## 3. Admin / RBAC / Audit

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 3.1 | `AdminUser`/`AdminRole`/`AdminAssignment` models | READY | LIVE | D8N DB | `app/models/admin_{user,role,assignment}.rb` |
| 3.2 | Authorization check (`Admin::ModeratorContext`) | READY, but **role-name-blind** | LIVE | D8N DB | `domains/admin/moderator_context.rb` — any active assignment of any role grants full moderator power (ADR 0013, explicit, intentional deferral) |
| 3.3 | Founder/initial-admin bootstrap | READY | — | — | `domains/admin/founder_bootstrap.rb`, `bin/rails d8n:bootstrap_founder` (this repo's Phase 2 work) |
| 3.4 | Admin CRUD API (list/create/modify AdminUsers, Roles, Assignments) | **MISSING** | — | — | No routes exist beyond the 3 domain-specific admin controllers below |
| 3.5 | `SecurityEvent` audit trail | READY (write + member-scoped HQ read) | HISTORICAL | D8N DB | `app/models/security_event.rb`, `domains/hq/security_event_history.rb`; Phase 1 added a paginated, brand-scoped member read, but no general audit browser |
| 3.6 | Dedicated `AuditLog` model | **PARTIAL / deliberately not duplicated** — see reconciliation below | HISTORICAL | D8N DB | `SecurityEvent` + `AuthAttempt` remain separate; Phase 1 added member-scoped reads over both, not a third table or unified general browser |
| 3.7 | Authorization framework | READY (hand-rolled) | — | — | No Pundit/CanCanCan in `Gemfile`; authorization is inline per-domain (`Admin::ModeratorContext`, `Trust::ReportTargets::*`) |

## 4. Trust & Safety

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 4.1 | `Report` model + polymorphic target (ADR 0018) | READY | LIVE+HISTORICAL | D8N DB | `app/models/report.rb`; reasons incl. violence/non-consensual/impersonation; targets: profile/message/profile_media/hook/conversation |
| 4.2 | Admin report queue/detail/transition API | READY | LIVE | D8N DB | `GET/PATCH /api/v1/admin/reports[/:id]`, `domains/admin/{report_queue,report_detail,transition_report}.rb` |
| 4.3 | SLA/aging on reports (age of oldest case, overdue) | **PARTIAL** | LIVE/DERIVABLE | D8N DB | Phase 2 HQ overview exposes oldest-open age and queue counts; true overdue/SLA remains `not_configured` because no approved threshold exists |
| 4.4 | Repeat-offender / reports-per-member aggregation | READY (bounded HQ read) | LIVE/DERIVABLE | D8N DB | `GET /api/v1/hq/trust_safety/repeat_offenders`, `domains/hq/trust_safety/repeat_offenders.rb` |
| 4.5 | Case/investigation timeline concept | **MISSING** | — | — | Reports are atomic; no nested case, no linked-evidence timeline beyond the single `evidence` jsonb snapshot |
| 4.6 | `AccountEnforcement` (suspend/reinstate) | READY | HISTORICAL | D8N DB | `app/models/account_enforcement.rb`; one active enforcement per (brand,user) DB-enforced |
| 4.7 | Admin suspend/reinstate API | READY | LIVE | D8N DB | `POST/DELETE /api/v1/admin/profiles/:id/suspension` |
| 4.8 | Enforcement history query (per member / per brand) | READY | LIVE+HISTORICAL | D8N DB | Phase 1: `GET /api/v1/hq/members/:lookup/enforcements`; Phase 2: `GET /api/v1/hq/trust_safety/enforcements` |
| 4.9 | Profile photo moderation queue + decision API | READY | LIVE | D8N DB | `GET/PATCH /api/v1/admin/profile_photos`; `Trust::ModerateProfilePhoto` |
| 4.10 | Photo moderation analytics (queue depth trend, review time, reviewer load) | **MISSING** | DERIVABLE | D8N DB | Queue exists; no aggregation |
| 4.11 | Identity/selfie/ID verification | **MISSING (not a gap to "surface", a real product gap)** | NOT AVAILABLE | — | Confirmed: no `Verification`/`UserVerification` model exists anywhere. Only email/phone OTP possession checks (`OtpChallenge`). Do not plan an HQ "verification review" page around anything beyond OTP delivery status until this product capability is actually built. |
| 4.12 | Conversation/message admin retrieval for investigation | **MISSING — likely intentional, not a bug** | — | — | `Message.body` is plaintext, no admin read endpoint exists. See SECURITY-AND-RBAC.md before proposing one — minimum-necessary-access principle applies directly here. |
| 4.13 | `AccountClosure` (account deletion, ADR 0014) | READY (write path); admin visibility **MISSING** | HISTORICAL | D8N DB | `app/models/account_closure.rb`, async R2 purge tracked via `media_purge_state`; no admin query/retry endpoint |

## 5. Product / Dating Loop

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 5.1 | Profile, ProfilePreference, ProfilePhoto, ProfileOption*, ProfilePrompt*, ProfileLocation | READY | LIVE | D8N DB | Full CRUD member API; well-tested; no admin read surface |
| 5.2 | Onboarding status | READY, but **computed only, not stored/auditable historically** | LIVE (point-in-time), not HISTORICAL | D8N DB (derived) | `domains/profiles/onboarding_status.rb`; member-facing only (`GET /api/v1/profile/configuration`); nothing snapshots "what was this member's onboarding state on date X" |
| 5.3 | Discovery / eligibility engine | READY | LIVE | D8N DB | `domains/matching/discovery.rb`; ranked, cursor-paginated, brand-strategy-pluggable |
| 5.4 | Discovery exposure audit trail | READY (data exists), **no query surface** | HISTORICAL | D8N DB | `DiscoveryAllocation`/`DiscoveryAllocationCandidate` persist per-candidate ranking payloads per viewer per day — this is exactly the data Member 360's "why is discovery empty" needs; it is being written today and simply isn't exposed |
| 5.5 | "Why is discovery empty for this member" diagnostic | **MISSING (API), data present** | DERIVABLE from #5.4 | D8N DB | No endpoint synthesizes the funnel view described in D8N-HQ-PLAN.md §7 |
| 5.6 | Like / Pass / Match | READY | LIVE+HISTORICAL | D8N DB | No admin read API for any of the three |
| 5.7 | Openers / Hooks / Hook Tonight (ADR 0015/0016) | READY | LIVE+HISTORICAL | D8N DB | Full member API; no admin surface |
| 5.8 | Conversations / Messages | READY (member); **no admin surface (see 4.12)** | LIVE+HISTORICAL | D8N DB | Plaintext `body`, attachment processing pipeline all working |
| 5.9 | Blocks | READY | LIVE | D8N DB | No admin surface |

## 6. Notifications & Delivery

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 6.1 | Notification/NotificationEvent/NotificationDelivery/NotificationPreference | READY | LIVE+HISTORICAL | D8N DB | Full per-channel delivery state machine: pending→processing→sent/failed/skipped, provider + `external_id` + error code/message persisted per delivery |
| 6.2 | Email delivery (Resend prod, ActionMailer dev) | READY | LIVE | PROVIDER API (Resend) | `domains/notifications/email/*_gateway.rb`; idempotency key; transient/permanent error classification |
| 6.3 | Email delivery/bounce/complaint **webhook** ingestion | **MISSING** | NOT AVAILABLE | — | Resend supports this; D8N does not consume it — delivery status past "sent to Resend" is unknown to D8N |
| 6.4 | SMS delivery (Twilio) | READY | LIVE | PROVIDER API (Twilio) | `domains/notifications/sms/twilio_gateway.rb`; per-brand messaging service SID |
| 6.5 | SMS delivery-receipt **webhook** ingestion | **MISSING** | NOT AVAILABLE | — | Same gap as 6.3, for Twilio status callbacks |
| 6.6 | Push notifications | **MISSING — intentionally fail-closed** | NOT AVAILABLE | — | `DeviceRegistration` model exists and is populated; `Push::RequiredGateway` always returns `provider_not_configured`. No APNs/FCM integration exists. |
| 6.7 | Message send debounce (leading-send, trailing-suppress) | READY | — | — | `domains/notifications/message_debounce.rb`, 90s window — this repo's own recent correction (see memory: rate-limit/debounce design) |
| 6.8 | Admin visibility into delivery health (bounce rate, failure rate by provider/brand) | **MISSING** | DERIVABLE from #6.1 | D8N DB | Data is fully persisted per-delivery; no aggregation endpoint |

## 7. Media / Storage

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 7.1 | R2 upload/process/purge pipeline | READY | LIVE+HISTORICAL | D8N DB + PROVIDER (R2) | `Media::{ObjectKey,ImageProcessor,ProcessProfilePhotoJob,PurgeProfileMediaJob}`; EXIF/GPS strip, dimension/decompression-bomb guards |
| 7.2 | Storage usage / cost visibility | **MISSING** | NOT AVAILABLE (would need R2 billing/usage API) | PROVIDER API (Cloudflare) — EXTERNAL | No integration exists; this is genuinely a provider-API integration, not a D8N DB query |
| 7.3 | Failed-upload / stuck-processing visibility | **MISSING** | DERIVABLE from `processing_state` column | D8N DB | Data exists (`pending/processing/ready/failed`); no aggregation endpoint |

## 8. Jobs / Queues

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 8.1 | Solid Queue (Postgres-backed), separate queue DB | READY | LIVE | D8N DB (`d8n_production_queue`) | `config/queue.yml`, `config/database.yml` |
| 8.2 | Recurring jobs (cleanup, notification recovery) | READY | — | — | `config/recurring.yml` — 4 scheduled jobs |
| 8.3 | Operator visibility into queue depth / failed jobs / retry rate | **MISSING** | LIVE, queryable directly from Solid Queue's own tables today | D8N DB | No admin API; Solid Queue's tables (`solid_queue_jobs`, `solid_queue_failed_executions`, etc.) exist and are queryable via raw SQL per `docs/operations/observability.md`, but nothing wraps them |
| 8.4 | Solid Queue built-in web UI (Mission Control Jobs) | **MISSING (not installed)** — DO NOT REBUILD if adopted | — | — | Not in Gemfile. Recommended: adopt `mission_control-jobs` rather than building a custom jobs dashboard (see ARCHITECTURE.md) |

## 9. Database / Infrastructure

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 9.1 | Postgres 17, primary + separate queue DB | READY | LIVE | D8N DB | `config/database.yml`, `config/deploy.production.yml` |
| 9.2 | Read replicas | **MISSING (not needed yet)** | — | — | No replica config; fine at current scale, flagged as a future performance-boundary concern (ARCHITECTURE.md) |
| 9.3 | DB diagnostics (slow queries, connection counts, size) | **MISSING** | LIVE (queryable via `pg_stat_*` directly) | D8N DB | No rake task/endpoint; manual SQL only, documented in `docs/operations/observability.md` |
| 9.4 | Backup/restore | READY (script), **no automated verification surface for HQ** | — | — | `script/operations/postgres_backup`; `docs/operations/postgres-backup-restore.md` |
| 9.5 | Deploy infra (Kamal) | READY | — | DEPLOYMENT SYSTEM | `config/deploy*.yml` — dual host prod, single accessory-DB staging |
| 9.6 | Healthcheck endpoint | READY | LIVE | D8N DB | `GET /api/v1/health` — checks primary + queue DB connectivity only, not a full readiness/dependency check |
| 9.7 | Release/version stamping (git SHA, deployed-at) | **MISSING** | NOT AVAILABLE | — | No `/version` endpoint, no `REVISION` file, no `Rails.application.config.x` version constant anywhere. This blocks all "did this deploy hurt the product" work in ARCHITECTURE.md § Deployment Intelligence. |

## 10. Observability / APM / Errors / Logs / Traces

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 10.1 | Error tracking (Sentry/Honeybadger/etc.) | **MISSING** | NOT AVAILABLE | — | Zero such gems in `Gemfile` |
| 10.2 | APM (New Relic/Datadog/Scout/Skylight) | **MISSING** | NOT AVAILABLE | — | Zero such gems |
| 10.3 | Structured/centralized logging | **PARTIAL** | LIVE (stdout only, not aggregated) | — | `ActiveSupport::TaggedLogging` to stdout with `request_id` tag; no log shipper/aggregator configured |
| 10.4 | Distributed tracing / OpenTelemetry | **MISSING** | NOT AVAILABLE | — | Not installed |
| 10.5 | Request-level metrics (throughput, p50/p95/p99, error rate) | **MISSING** | NOT AVAILABLE | — | No instrumentation exists to compute these today |

**This entire domain (#10) is the "DO NOT REBUILD from scratch" case named
explicitly in the product brief.** The correct move is adopting one
observability vendor (with OpenTelemetry-compatible instrumentation
where practical) and having HQ summarize/link into it — never building an
in-house APM. See ARCHITECTURE.md § Observability Integration.

## 11. Analytics / Events

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 11.1 | Canonical product-analytics event system | **MISSING** | NOT AVAILABLE | — | `domains/analytics/` contains only a `.keep` placeholder. No `AnalyticsEvent` model, no Segment/PostHog/Mixpanel/Amplitude gem, no `track_event` call anywhere in the codebase. |
| 11.2 | Operational "event" models that already exist (do not confuse with #11.1) | READY, but purpose-built, not general | HISTORICAL | D8N DB | `NotificationEvent` (durable outbox for notification fan-out only) and `SecurityEvent` (audit only) are real, working, event-sourced-ish patterns — reusable *as a pattern* for the canonical event system, not repurposable directly |

This is the single largest gap for the BUSINESS section of D8N-HQ-PLAN.md
(growth funnel, acquisition, retention cohorts). See ARCHITECTURE.md §
Event Architecture for the proposed canonical contract, built on the
`NotificationEvent`/`EventPublisher` pattern already proven in this
codebase rather than invented from nothing.

## 12. Revenue / Billing

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 12.1 | Any billing/monetization code | **MISSING (deliberately, per current product priorities)** | NOT AVAILABLE | — | `domains/billing/` contains only a `.keep` placeholder. No Subscription/Payment/Product/Price/Entitlement model, no Stripe/Paystack gem. |

Every "Revenue Score" / revenue-segmented view in D8N-HQ-PLAN.md must render
`NOT CONFIGURED` until this exists. This is not an HQ engineering gap; it
is a correct reflection of current product scope (LATER, per
`D8N_NOW_NEXT_LATER.md`).

## 13. Support / Customer Service

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 13.1 | Support ticketing (Zendesk/Intercom/Front or custom) | **MISSING** | NOT AVAILABLE | — | No gem, no model. The closest thing today is the internal moderation queue (Report), which is a different concept (community safety, not customer support). |

## 14. Growth / Acquisition / Attribution

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 14.1 | UTM/referrer/campaign capture at registration | **MISSING** | NOT AVAILABLE | — | No `utm_*`/`referrer`/`acquisition_source` field anywhere in the schema or registration controller |

## 15. Rate limiting / abuse protection (relevant to Security Centre)

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 15.1 | Auth throttling (registration/login/change), DB-backed, fail-closed | READY | HISTORICAL | D8N DB | `domains/identity/{password_throttle,otp_throttle,authentication_lock}.rb` |
| 15.2 | Generic product-action rate limiting (like/message/hook/etc.), fail-open | READY | HISTORICAL | D8N DB | `domains/abuse_protection/{rate_limiter,policy}.rb`, `RateLimitCounter` model, 14 configured actions |
| 15.3 | General HTTP-layer rate limiting (Rack::Attack or similar) | **MISSING** | — | — | Not installed; known, documented gap (`D8N_NOW_NEXT_LATER.md`: message send rate-limiting still open as of last product update) |
| 15.4 | Admin read API over `AuthAttempt`/`SecurityEvent`/`RateLimitCounter` for a Security Centre | **MISSING** | DERIVABLE | D8N DB | All three tables are fully populated; nothing reads them back for operators today |

## 16. CI/CD quality signals (feed HQ's "Deployments"/"System Score")

| # | Item | Status | Data | Source | Evidence |
|---|---|---|---|---|---|
| 16.1 | Brakeman (security scan), bundle-audit (dep vulns), Rubocop (lint), Zeitwerk check, full test suite | READY | HISTORICAL (per CI run, not queryable by HQ) | GitHub Actions | `.github/workflows/ci.yml` — 4 jobs |
| 16.2 | HQ-visible CI/quality signal feed | **MISSING** | EVENT NEEDED (GitHub webhook/API integration) | GitHub | No integration exists; would be a straightforward GitHub API/webhook read, not new instrumentation on D8N's side |

---

## Reconciliation with the original admin plan (`PLAN_OF_ACTION.md` Phase 10)

The repository's original founding plan (`/Users/uchechinwaka/pro/d8n/PLAN_OF_ACTION.md`,
written before implementation began) already specified a "Phase 10: D8N
Admin" with: network dashboard, brand dashboard, user search, profile
review, reports queue, moderation, verification review, billing support
view, and role-based permissions — with core models `AdminUser`,
`AdminRole`, `AdminPermission`, `AuditLog`.

What actually shipped, and how it compares:

| Planned (Phase 10) | What exists today | Verdict |
| --- | --- | --- |
| `AdminUser`, `AdminRole` | Built exactly as planned | **Still correct** — reuse as-is |
| `AdminAssignment` (brand-scoped access) | Built, and is *the* authorization mechanism | **Still correct**, but simpler than planned: no `AdminPermission` model was ever built. Authorization today is binary (has an active assignment on this brand, or doesn't) — not the granular role-based permission matrix Phase 10 envisioned. |
| `AdminPermission` (granular RBAC) | **Never built** | This is a real, acknowledged gap, and ADR 0013 says so explicitly: "differentiated admin RBAC is deliberately deferred until more roles genuinely exist." HQ's eventual permission model (SECURITY-AND-RBAC.md) picks up exactly here — it should not reinvent the decision, just implement it now that HQ creates the "more roles" trigger. |
| `AuditLog` (dedicated audit model) | **Never built as a single model.** Its job is split between `SecurityEvent` (audit-flavored, has severity) and `AuthAttempt` (auth-flavored) — both real, both write-only, neither has a read API. | **Partially superseded, not replaced.** HQ needs a read API over the union of these two, not a third table, unless a real modeling gap is found once building it (see ARCHITECTURE.md § Audit). |
| Reports queue, moderation | Built (`Report`, admin reports API) — went further than Phase 10 sketched, with typed reasons and polymorphic targets (ADR 0018) | **Exceeded plan** |
| Verification review | Verification itself was never built (see §4.11) | **Blocked on a real product gap**, not an admin-surface gap |
| Billing support view | Billing itself was never built (see §12) | **Blocked on a real product gap** |
| Network dashboard / brand dashboard / user search | **Never built** | This is what D8N HQ *is* — this plan is the direct continuation of that unfinished Phase 10 item, informed by two more years... rather, several more weeks of actual product surface having been built since (Reports, Enforcement, Hooks, notifications, etc.) that Phase 10 could not have anticipated in detail |
| Mandatory admin MFA (Phase 10's security baseline, restated in ADR 0013) | **Still not built.** Explicitly flagged as a pre-launch gate in `D8N_NOW_NEXT_LATER.md`. | Still open — HQ concentrates admin power further, which raises the cost of this gap rather than lowering it. See SECURITY-AND-RBAC.md. |

**Bottom line:** the original plan's instincts (separate brand membership
from admin assignment, brand-scoped moderators, network-level access only
for trusted/eventually-differentiated roles, mandatory audit trails,
mandatory admin MFA before broad admin surfaces) are all still correct and
are carried forward unchanged into SECURITY-AND-RBAC.md. What changed is scope and
sequencing: the granular `AdminPermission`/`AuditLog` machinery was
deliberately deferred rather than built speculatively, and HQ is the
forcing function that finally justifies building it for real.

---

## Recently landed work relevant to HQ (this session's prior phases)

For context — these already exist in the codebase and HQ should build on
them directly, not duplicate them:

- **Phase 1 (brand provisioning):** `Brands::HookusInstaller`,
  `Brands::Provisioner`, `bin/rails brands:provision[slug]`, truthful
  baseline `moderator` `AdminRole` seed. This is the correct foundation
  for HQ's "Provisioning/Readiness" page (§ ARCHITECTURE.md § Brand
  Control Centre) — a future `brands:doctor` read-only check should be
  built as a sibling to `Provisioner`, not a rewrite of it.
- **Phase 2 (founder bootstrap):** `Admin::FounderBootstrap`,
  `bin/rails d8n:bootstrap_founder`. Promotes one existing D8N identity to
  `moderator` on every active brand, using the *current* (brand-scoped,
  role-name-blind) authorization model — deliberately does not invent
  platform-wide authorization. **Known, carried-forward open question:**
  normal brand login requires an active `BrandMembership`, so founder
  bootstrap creates/uses memberships on brands the founder didn't
  originally join. This is treated as a known architectural concern in
  this plan too (see SECURITY-AND-RBAC.md), not silently redesigned here.
