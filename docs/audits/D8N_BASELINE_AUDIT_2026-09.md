# D8N Baseline Repository, Architecture & Implementation Audit

**Audit date:** 2026-09-05
**Revision inspected:** `931bb04` on branch `date9ja-parity` (working tree clean; `dev` compared where relevant)
**Stack:** Ruby 3.3.12, Rails 8.1.3.1, PostgreSQL, Solid Queue, Kamal
**Type:** Read-only baseline audit. No production code, schema, database, or deployment was changed.
**Method:** Implementation-first. Routes, controllers, domain services, models, migrations, schema, configuration, jobs, tasks and tests were read directly. Documents were treated as *intent* and compared against code. Test suite, RuboCop, Brakeman and bundle-audit were executed locally.

**Evidence convention used throughout:**
- **FACT** — directly verified in this repository at `931bb04`.
- **INFERENCE** — strongly implied by verified evidence but not directly proven.
- **UNKNOWN** — cannot be safely established from this repository alone.

**Relationship to prior audits.** This document does not supersede
`docs/audits/D8N_PLATFORM_ARCHITECTURE_REUSE_AUDIT.md` (2026-08-24, `dev@917de86`);
it re-verifies that audit's findings and records which have been remediated. It also
does not supersede `docs/migrations/date9ja-to-d8n/CAPABILITY-PARITY.md`, which
remains the authoritative Date9ja parity inventory per
`docs/engineering/DOCUMENTATION-POLICY.md`.

---

## 1. Executive summary

D8N is a **single, genuinely shared, API-only multi-brand Rails platform with an
unusually strong tenancy foundation and an unusually honest documentation set** —
and it is **early in the platform's operational and product lifecycle**, not near
Date9ja migration.

### What is true

1. **FACT — Tenancy is enforced in the database, not just in application code.** 150
   foreign keys exist; brand-bearing tables carry composite unique keys such as
   `idx_profiles_on_id_brand` and composite FKs such as
   `fk_messages_conversation_tenant`, `fk_likes_liker_profile_tenant`,
   `fk_conversation_participants_profile_tenant`
   (`db/schema.rb:950-953`, `db/schema.rb:1069-1199`). A cross-brand row association
   is rejected by PostgreSQL, not merely by a scope someone remembered to add. This
   is the single strongest thing in the repository.

2. **FACT — There is one platform, not three brand forks.** One `User`/`Credential`
   identity model, one `BrandMembership`, one `Profile` engine composed from brand
   catalogues, one eligibility/discovery core, one Like/Pass/Match engine, one
   conversation/message engine, one media pipeline, one block/report/enforcement
   system, one notification pipeline. There is no parallel DateZA or HookUs backend.

3. **FACT — The four architectural-drift findings of the 2026-08-24 audit have been
   remediated.** `Matching::FacetFilter` no longer contains HookUs `vibes`;
   `Matching::ExclusionsScope` (`domains/matching/exclusions_scope.rb`) now takes
   injected `contributors` rather than always querying Hooks;
   `Profiles::StatusFields` no longer imports HookUs location policy; and
   `Api::V1::ProfileController#profile_params`
   (`app/controllers/api/v1/profile_controller.rb:41-51`) now derives permitted
   params from `Profiles::FieldPolicy#writable_profile_fields` rather than accepting
   the whole shared scalar set.

4. **FACT — HQ's backend is real and reads production tables.** Every HQ endpoint
   inspected returns live queries. No mock or hardcoded data was found in any HQ
   controller or service. Where a metric cannot be computed, the code says so
   explicitly rather than fabricating it (`Hq::ProductIntelligence::Funnel#unavailable_stage`;
   `not_configured` SLA in the Trust & Safety overview).

5. **FACT — Quality gates are structurally strong where they exist.**
   `test/contracts/openapi_contract_test.rb` asserts that every `api/v1` route is
   documented in `docs/api/openapi.yaml` **exactly once**, which structurally
   prevents API contract drift. 2003 tests, 11942 assertions. Brakeman: 0 warnings.
   bundle-audit: 0 vulnerabilities. No secret value has ever been committed.

### What is not true

1. **FACT — `dev` and `date9ja-parity` both carry a permanently failing test.**
   `test/jobs/notifications/deliver_product_notification_job_test.rb:41` asserts the
   DateZA welcome email contains no `href=`, but
   `Notifications::DeepLink::DATEZA_DEFAULT_BASE_URL` guarantees a CTA link always
   renders for `dateza`. This is not environment-dependent and is not new to this
   branch. **CI has been red on the mainline and the team has continued shipping.**
   That is a process finding, not a test finding.

2. **FACT — Two production recovery sweepers exist, are tested, and are never run.**
   `Media::ProfilePhotoProcessingSweeper` and `Media::ProfileVideoProcessingSweeper`
   appear in no `config/recurring.yml` entry, no rake task, and no production code
   path. Media stuck in `processing` is unrecoverable in production today.

3. **FACT — Admin MFA step-up never expires.** `Session#admin_mfa_verified_for?`
   (`app/models/session.rb:45-50`) checks only `admin_mfa_verified_at.present?`.
   Sessions have a 30-day TTL (`Session::DEFAULT_TTL`). A single TOTP verification
   grants MFA-verified access to the entire control plane for up to 30 days.

4. **FACT — Member 360 is read-only.** No HQ endpoint can edit a member. Gender
   cannot be corrected, preferences cannot be corrected, and no write path to
   discovery eligibility exists for staff.

5. **FACT — Date9ja is not close to migration.** `CAPABILITY-PARITY.md` (the
   project's own authoritative matrix, last updated 2026-09-05) records **1 of 95
   capabilities at PARITY**, 42 PARTIAL, 40 MISSING, 11 DIFFERENT SEMANTICS, 1
   NEEDS PRODUCT DECISION.

6. **FACT — Whole intended domains are empty.** `domains/verification/` and
   `domains/billing/` contain only `.keep`. `domains/analytics/` defines exactly two
   event types. There is no realtime capability (no `app/channels`, no ActionCable).

### Verdict

> D8N is at the **end of shared-platform foundation and the beginning of HQ
> operational build-out**, with a Date9ja migration program in *evidence-gathering
> and rehearsal*, not execution. It is **not migration ready** and **not
> parity-accepted**. It is, however, on a sound architecture with real safety rails,
> and the largest risks in this report are operational discipline problems, not
> architectural ones.

---

## 2. Repository map

**FACT.** API-only Rails monolith with a `domains/` layer sitting alongside `app/`
(ADR 0001, ADR 0004).

```
/                     Rails app root
  app/
    controllers/api/v1/          59 controllers (consumer, admin, hq namespaces)
    controllers/api/v1/admin/    legacy moderation namespace (4 controllers)
    controllers/api/v1/hq/       HQ control plane (10 controllers)
    models/                      57 models, flat, no engines
    jobs/                        11 jobs (media, notifications, abuse, infra)
    views/                       mailer templates ONLY — no HTML UI
    mailers/
  domains/                       23 domain namespaces, ~370 .rb files
  config/
    routes.rb                    144 lines, fully explicit (no `resources`)
    deploy.yml / .production / .staging   Kamal
    recurring.yml                Solid Queue recurring schedule
    queue.yml
  db/
    migrate/                     75 migrations
    schema.rb                    1199 lines, 150 foreign keys
    queue_schema.rb              separate Solid Queue database
  test/                          268 test files, 2003 tests
  lib/tasks/                     9 rake files (brands, demo seeds, date9ja import)
  scripts/date9ja/               migration operator scripts
  docs/                          ~118 markdown docs + ADR set (0001-0030)
  TODO/                          private-beta execution tracker
  .github/workflows/ci.yml       brakeman, bundle-audit, docker build, rubocop, test
```

### Domain inventory (file counts, FACT)

| Domain | .rb | Assessment |
|---|---:|---|
| `date9ja` | 37 | Migration tooling (snapshot/import/storage) |
| `profiles` | 35 | Core; brand catalogues + field policy |
| `identity` | 31 | Core; auth, OTP, sessions, throttles |
| `matching` | 30 | Core; discovery, find, likes, matches |
| `hq` | 29 | HQ control-plane reads |
| `admin` | 28 | RBAC, MFA, moderation, enforcement |
| `notifications` | 28 | Email/SMS/push pipeline |
| `d8n` | 26 | Platform capability catalogue + brand contracts |
| `messaging` | 16 | Match-gated chat |
| `trust` | 15 | Blocks, reports, moderation |
| `media` | 12 | Photo/video processing, R2, policies |
| `hooks` | 11 | HookUs interaction |
| `migration` | 7 | Generic media transfer |
| `hook_tonight` | 6 | HookUs Tonight |
| `brands` | 5 | Provisioning/resolution |
| `geography` | 5 | Places catalogue |
| `accounts` | 3 | Closure/deactivation |
| `abuse_protection` | 2 | Rate limiting |
| `analytics` | 2 | **Scaffold only (2 event types)** |
| `infrastructure` | 1 | Readiness |
| **`verification`** | **0** | **EMPTY — `.keep` only** |
| **`billing`** | **0** | **EMPTY — `.keep` only** |

### Not in this repository

**FACT.** There is **no frontend code of any kind** in this repository.
`app/views/` contains only mailer templates and `public/` contains only
`robots.txt` and vendored Swagger UI assets. This is deliberate per **ADR 0004
(API-only core and separate frontends)**. Section 11 is answered accordingly.

---

## 3. Architecture discovered

### Tenancy model (FACT)

| Layer | Mechanism | Evidence |
|---|---|---|
| Brand identity | `Brand` + `BrandDomain` rows (DB-backed, not config) | `app/models/brand.rb`, `brand_domain.rb` |
| Request → brand | Hostname lookup only | `Brands::Resolver` (`domains/brands/resolver.rb`) |
| Brand nil | Fails closed — authentication returns `:brand_required` | `Identity::SessionAuthenticator:15` |
| User ↔ brand | `BrandMembership` (user is global, membership is per-brand) | ADR 0003 |
| Session | Brand-bound; `session.brand_id != brand.id` → `:wrong_brand` | `Identity::SessionAuthenticator:20` |
| Query scoping | Every tenant query passes `brand:` explicitly; no global default scope | verified by sweep, §7 |
| DB enforcement | Composite `(id, brand_id)` unique keys + composite FKs | `db/schema.rb` |
| Capability gating | `D8n::Platform::BrandRegistry` → `BrandContract` → `CapabilityAccess` | `domains/d8n/platform/` |

**Notable:** the tenancy model deliberately avoids `default_scope` / thread-local
implicit scoping. It requires explicit `brand:` at every call site and backstops that
with database constraints. **INFERENCE:** this is more robust than a
`default_scope` model for a codebase where jobs and rake tasks run outside a request
context, because it cannot silently lose tenant context.

### Capability composition (FACT)

`D8n::Platform::Catalog` (`domains/d8n/platform/catalog.rb`) aggregates 13 capability
modules (`id`, `profile`, `discovery`, `verify`, `match`, `chat`, `trust`, `media`,
`notify`, `pay`, `ai`, `insights`, `admin`) into one keyed registry with dependency
validation. Three brand contracts consume it: `Brands::Date9ja`, `Brands::Dateza`,
`Brands::Hookus`. Controllers declare requirements with
`requires_platform_capability` / `requires_platform_contract`
(`app/controllers/application_controller.rb:12-22`).

**INFERENCE:** this is the "one auditable brand contract" the 2026-08-24 audit asked
for, and it has landed. However brand knowledge is still *also* present in
`Profiles::{Date9ja,Dateza,Hookus}ProfileCatalog`, `Brands::*Installer`,
`Matching::StrategyRegistry`, `Matching::Find::PolicyRegistry`, and notification
presenters — so composition is now *coherent* but not yet *single-sourced* (§15).

### Authentication (FACT)

One mechanism only. `rodauth-rails` is used **solely as a password hashing and
policy library** (`Identity::PasswordEngine`, `config/initializers/rodauth.rb` —
`render: false`); Rodauth owns no routes and no sessions. Sessions are opaque,
token-digest-indexed, brand-bound, 30-day TTL, revocable. Browser cookie sessions
carry CSRF verification (`Identity::BrowserSession`, ADR 0019). There is **no second
auth system** — a genuine strength.

---

## 4. Capability matrix

Status vocabulary as requested. "Shared?" = implemented once at platform level.
"Multi-brand safe?" reflects verified tenant scoping.

| # | Capability | Exists | Status | Ownership | Shared? | Multi-brand safe? | HQ visibility | Tests | Priority |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | Identity / Auth | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Yes (fails closed) | Read (auth attempts, security events, sessions) | Extensive | — |
| 2 | Members / Profile | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Yes | Read-only | Extensive | P1 (no HQ write) |
| 3 | Brands / Tenants | Yes | **COMPLETE** | D8N shared | Yes | Yes (DB-enforced) | Read (`command_centre/brands`) | Yes | — |
| 4 | Discovery / Matching | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Yes | Diagnostic read | Extensive | — |
| 5 | Likes / Connections | Yes | **COMPLETE** | D8N shared | Yes | Yes | Counts in Member 360 | Yes | — |
| 6 | Chat / Messaging | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Yes | Counts only, no content | Yes | P2 |
| 7 | Media | Yes | **PARTIAL** | D8N shared | Yes | Yes (per-brand R2) | Photo moderation | Extensive | **P1 (sweepers unwired)** |
| 8 | Notifications | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Yes | Delivery summary | Yes | P2 |
| 9 | Verification | Contact only | **PARTIAL** | Unclear (`domains/verification/` empty) | n/a | n/a | Verified flags | Partial | P1 for Date9ja |
| 10 | Trust & Safety | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Yes | Overview + repeat offenders | Yes | — |
| 11 | Blocking | Yes | **COMPLETE** | D8N shared | Yes | Yes | Counts | Yes | — |
| 12 | Reporting | Yes | **COMPLETE** (ADR 0018) | D8N shared | Yes | Yes | Queue + detail | Yes | — |
| 13 | Moderation | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Yes | Report queue, photo review | Yes | P2 |
| 14 | Enforcement | Yes | **COMPLETE** | D8N shared | Yes | Yes (DB-unique active) | History + create/revert | Yes | — |
| 15 | Payments / Entitlements | No | **ABSENT** | — (`domains/billing/` empty) | — | — | None | None | P2 (Date9ja premium) |
| 16 | Analytics / Insights | Barely | **SCAFFOLDED** (2 event types) | D8N shared | Yes | Yes (validated) | Overview + funnel + trends | Yes | P2 |
| 17 | HQ / Admin | Yes | **FUNCTIONAL BUT INCOMPLETE** | HQ | Yes | Yes (per-brand assignment) | n/a | Yes | P1 |
| 18 | Audit / Security logging | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Yes | Member-scoped reads | Yes | P2 (no browser) |
| 19 | Realtime | No | **ABSENT** | — | — | — | — | — | P2 (Date9ja parity) |
| 20 | Background jobs / events | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Tenant passed explicitly | Health check | Yes | **P1 (unwired sweepers)** |
| 21 | Geography / Places | Yes | **COMPLETE** | D8N shared | Yes | Brand-agnostic catalogue | None | Yes | P3 |
| 22 | Hooks / Hook Tonight | Yes | **COMPLETE** | HookUs-gated shared | Yes | Yes (capability-gated) | Counts | Yes | — |
| 23 | Account lifecycle | Yes | **COMPLETE** (ADR 0014) | D8N shared | Yes | Yes | Closure state | Yes | — |
| 24 | Abuse protection | Yes | **FUNCTIONAL BUT INCOMPLETE** | D8N shared | Yes | Yes | None | Yes | P3 |
| 25 | Migration tooling | Yes | **PARTIAL** | Date9ja-specific + generic seam | Partly | Yes | None | Extensive | — |
| 26 | Community / Dating Hub / AI | No | **ABSENT** | — | — | — | — | — | P2 (Date9ja parity) |

---

## 5. HQ status

**FACT.** HQ is a backend-only control plane at `/api/v1/hq/*` (18 routes,
`config/routes.rb:65-93`). Its UI lives outside this repository.

### Authorization chain (FACT)

`Api::V1::Hq::BaseController` applies four independent server-side checks before any
action (`app/controllers/api/v1/hq/base_controller.rb`):

1. `authenticate_admin!` — requires an authenticated `Current.user`, then resolves
   `Admin::AuthorizationContext` for `Current.brand`.
2. `require_admin_mfa!` — requires session TOTP step-up bound to this admin's
   credential.
3. `requires_admin_capability` — per-action capability from `Admin::Capabilities`.
4. `disable_admin_http_caching` — `Cache-Control: no-store, private`, ETag stripped.

`Admin::AuthorizationContext.resolve` (`domains/admin/authorization_context.rb`)
fails closed on: no admin user, no active brand assignment, **more than one active
assignment** (`assignments.one?` — ambiguity is refused, not merged), a deleted role,
or an unknown role name.

### Per-surface status

| Surface | Route | Backing | Auditing | Status |
|---|---|---|---|---|
| Current operator | `GET /hq/operator` | Live | — | **REAL** |
| Operator directory | `GET /hq/operators` | Live | Yes | **REAL** |
| Operator create/update | `POST`/`PATCH /hq/operators[/:id]` | Live | Yes (`Admin::OperatorManagement.audit!`) | **REAL** |
| MFA enrol/confirm/challenge/reset | `/hq/mfa/*` | Live | Yes (`Admin::Mfa::Audit`) | **REAL** |
| Member directory | `GET /hq/members` | Live, filters + signed cursor | Yes | **REAL** |
| Member 360 | `GET /hq/members/:lookup` | Live, 6 sections | Yes | **REAL** |
| Security events | `GET /hq/members/:lookup/security_events` | Live, paginated | Yes | **REAL** |
| Auth attempts | `GET /hq/members/:lookup/auth_attempts` | Live, paginated | Yes | **REAL** |
| Enforcement history | `GET /hq/members/:lookup/enforcements` | Live, paginated | Yes | **REAL** |
| Discovery diagnostic | `GET /hq/members/:lookup/discovery_diagnostic` | Live, stage-by-stage | Yes | **REAL** |
| Trust & Safety overview | `GET /hq/trust_safety/overview` | Live | Yes | **REAL** (SLA = `not_configured`) |
| Repeat offenders | `GET /hq/trust_safety/repeat_offenders` | Live aggregate | Yes | **REAL** |
| Brand enforcements | `GET /hq/trust_safety/enforcements` | Live, signed cursor | Yes | **REAL** |
| Analytics overview | `GET /hq/analytics/overview` | Live | Yes | **REAL** |
| Command centre health | `GET /hq/command_centre/health` | Live | Yes | **REAL** |
| Brand comparison | `GET /hq/command_centre/brands` | Live, per-assignment gated | Yes | **REAL** |
| Product intelligence funnel | `GET /hq/product_intelligence/funnel` | Live + explicit `unavailable_stage` | Yes | **REAL, partially unavailable** |
| Product intelligence trends | `GET /hq/product_intelligence/trends` | Live | Yes | **REAL** |
| Security alerts | `GET /hq/security_alerts` | Live | Yes | **REAL** (limit only, no cursor) |

**FACT: zero mock, static, or hardcoded data was found in any HQ controller or
service.** Every value traced to a database query. Where a number is not derivable,
the code returns an explicit unavailable/`not_configured` marker rather than a
plausible-looking placeholder. This is a genuine and unusual strength.

### RBAC inventory (FACT)

19 capabilities, 9 roles (`domains/admin/capabilities.rb`):

| Role | Capabilities |
|---|---|
| `founder` | ALL (19) |
| `super_admin` | ALL (19) |
| `operations` | 11 — sensitive/security read, diagnostics, T&S read, reports read, enforcement read+create, analytics, operators read, brand ops, security alerts |
| `trust_safety` | 10 — adds reports moderate, enforcements manage, photo moderate |
| `support` | 2 — `hq.member.sensitive_read`, `hq.discovery_diagnostics.read` |
| `engineering` | 2 — diagnostics, `hq.system.read` |
| `marketing` | 1 — `hq.analytics.read` |
| `analyst` | 1 — `hq.analytics.read` |
| `moderator` | ADR-0013 compatibility role |

`Admin::RolePolicy` prevents self-management, founder-role management by anyone, and
super-admin management by non-founders.

### HQ gaps (FACT)

| Gap | Consequence |
|---|---|
| **No member write path at all** | Staff cannot correct any member data. See §6. |
| **HQ is brand-scoped by request hostname** | A founder must switch hosts to view another brand's members. No cross-brand member search exists (documented as deliberate in `CURRENT-STATE.md` §1). |
| **MFA step-up never expires** | See §8, P1-1. |
| **No general audit browser** | `SecurityEvent` is readable only member-scoped. "Who did what across the brand yesterday" is unanswerable via API. |
| **No case/investigation timeline** | Reports are atomic. |
| **No brand health rake/doctor task** | Confirmed absent. |
| **No rate limiting on HQ endpoints** | Mitigated by MFA + capability gating. |

---

## 6. Member 360 status

**FACT.** End-to-end trace of `GET /api/v1/hq/members/:lookup`:

```
(external UI, not in this repo)
  → routes.rb:88  hq/members#show
  → Api::V1::Hq::BaseController  authenticate_admin! → require_admin_mfa! → no-store
  → MembersController  requires_admin_capability hq.member.sensitive_read
  → Hq::Identity::Lookup.call(brand: Current.brand, lookup:)   [brand-scoped]
  → Hq::Member360::Load.call(brand:, brand_membership:)        [read-only]
  → PostgreSQL (bounded reads across ~15 tables)
  → Hq::SensitiveReadAudit.record(... event_type: "hq.member_360_viewed")
  → SecurityEvent row (actor, target, session, ip, user agent)
```

### Six sections returned (FACT, `domains/hq/member360/load.rb`)

| Section | Fields |
|---|---|
| **Identity** | user id/status/names/created_at, membership status, member_since, up to 10 contact identifiers (**including plaintext normalized email/phone values** and verified/last-seen), 5 recent sessions (device, IP, last used, expiry, revoked) |
| **Profile** | public_id, display name, status, visibility, **gender**, **birthdate**, country/city, onboarding state + next step + completion %, photo count, up to 20 photos (id, position, status, visibility, processing state), preference summary (min/max age, distance, intent, **interested_in**, country) |
| **Product** | likes given/received, active matches, hooks sent/received/live, hook-tonight live, conversation count, 5 recent conversations (**ids and status only — no message content**), blocks given/received |
| **Comms** | delivery tallies by status and channel over the last 200 rows, 10 recent deliveries with provider/error codes |
| **Safety** | reports filed/received counts, 5 recent reports, active enforcement, lifetime enforcement count, account closure + media purge state |
| **Activity** | last login, 5 recent auth attempts (kind/result/IP), 5 recent security events |

### Answers to the specific questions asked

| Question | Answer | Evidence |
|---|---|---|
| What fields are visible? | The table above. Broad, including PII. | `member360/load.rb` |
| What fields are editable? | **NONE.** | No PATCH/POST/PUT under `hq/members` in `config/routes.rb` |
| What actions can staff perform? | Read only, from Member 360. Suspend/ban/reinstate and report transitions exist but live in the separate `/api/v1/admin/*` namespace. | `routes.rb:52-62` |
| Are sensitive reads logged? | **Yes — every action, individually.** `hq.member_360_viewed`, `hq.member_security_events_viewed`, `hq.member_auth_attempts_viewed`, `hq.member_enforcements_viewed`, `hq.member_discovery_diagnostic_viewed`, `hq.member_directory_viewed`. Actor, target user, session, IP, user agent recorded. | `Hq::SensitiveReadAudit` |
| Are writes audited? | Yes, for the writes that exist elsewhere (`Admin::EnforcementAudit`, `Admin::ModerationAudit`, `Admin::OperatorManagement.audit!`, `Admin::Mfa::Audit`). Reason text is deliberately **not** stored — only `has_reason`. | `domains/admin/enforcement_audit.rb` |
| Are brand boundaries enforced? | Yes. Lookup, load, and every sub-read are `Current.brand`-scoped, and the brand comes from the request host, not a client parameter. | `Hq::Identity::Lookup` |
| **Can gender be safely corrected?** | **No — there is no path to correct it at all.** `profiles.gender` is a plain nullable `string` with no DB constraint (`db/schema.rb:928`); the only writer is the member's own `PATCH /api/v1/profile`. | — |
| **Can looking-for / preferences be corrected?** | **No.** Same — only `PATCH /api/v1/profile/preferences` by the member. | — |
| Do changes propagate to discovery eligibility? | **N/A — no staff changes are possible.** For member-initiated changes, `Profiles::Publication.unpublish_if_incomplete!` re-gates publication on completion, and discovery reads live profile state, so propagation is immediate. `Hq::Member360::DiscoveryDiagnostic` lets staff *observe* eligibility stage by stage. | `domains/profiles/publication.rb:52-58` |
| Is moderation/enforcement history visible? | Yes — active enforcement + lifetime count inline; full paginated history at `/hq/members/:lookup/enforcements`. | — |
| Does messaging/activity context exist? | Partially. Conversation counts, ids, status, and recent-conversation metadata. **Message content is deliberately never exposed** (ADR 0010). Auth and security activity are present. | — |

**Assessment: Member 360 is the most complete vertical slice in the repository and
is genuinely production-shaped on the read side. It is exactly half a slice — the
write half does not exist.** For a support operator, "I can see the member's whole
state but cannot fix anything" is the defining current limitation of HQ.

---

## 7. Multi-tenancy / brand isolation findings

**This section was audited most aggressively. No cross-tenant leakage was found.**

| Check | Result | Evidence |
|---|---|---|
| How brands are represented | `Brand` rows + `BrandDomain` host mappings, DB-backed | `app/models/brand.rb` |
| How users relate to brands | `BrandMembership`, unique on `(user_id, brand_id) WHERE deleted_at IS NULL` | `db/schema.rb:195` |
| How requests establish brand | Hostname only, via `Brands::Resolver`. **Never a client-supplied parameter or header.** | `application_controller.rb:31` |
| Nil-brand behaviour | **Fails closed.** `SessionAuthenticator` returns `:brand_required`; no request can authenticate without a resolved brand. | `session_authenticator.rb:15` |
| Session cross-brand replay | **Blocked.** `session.brand_id != brand.id` → `:wrong_brand`. | `session_authenticator.rb:20` |
| Query scoping | Explicit `brand:` at call sites; **no `default_scope`**, so no silent context loss in jobs/tasks | verified by sweep |
| **Unscoped-query sweep** | Swept `Profile`, `Match`, `Like`, `Message`, `Conversation`, `Hook`, `Report`, `ProfilePhoto`, `ProfileVideo`, `AccountEnforcement`, `Session`, `SecurityEvent`, `AuthAttempt`, `Notification` for `find_by`/`where`/`find`/`exists?`/`count` without a brand term. **10 hits, all reviewed, none unsafe** (see below). | — |
| Jobs preserve tenant context | Jobs take record ids and re-derive `brand` from the record's own `brand_id`; they do not rely on `Current`. | `app/jobs/**` |
| HQ intentional cross-tenant | Only `command_centre#brands`, and it iterates **the admin's own active assignments** and requires `hq.analytics.read` **on each assignment**. | `Hq::CommandCentre::BrandComparison#assignments` |
| Consumer APIs accidental cross-tenant | Not found. | — |
| Cache tenant safety | **N/A by construction** — `config.cache_store = :null_store` in production and test. Nothing is cached, so nothing can leak. | `config/environments/production.rb:107` |
| Events tenant-aware | `Analytics::Emit#validate_scope!` **rejects** a profile or session whose `brand_id` differs from the event brand, and a session/profile mismatched to the user. | `domains/analytics/emit.rb:60-68` |
| Uniqueness constraints scoped | Yes — every pair/state uniqueness index is brand-prefixed (`idx_likes_active_pair`, `idx_matches_active_pair`, `idx_profile_blocks_active_pair`, `idx_hooks_sender_recipient`, `idx_reports_open_target`, `idx_account_enforcements_active_unique`, …). | `db/schema.rb` |
| IDs expose cross-brand info | No. External identifiers are `uuid public_id` columns; internal bigints are never routed. | `db/schema.rb` |
| Authorization depends on UI filtering | **No.** All four HQ checks are server-side; there is no UI in this repo to depend on. | §5 |

### The 10 sweep hits, individually cleared (FACT)

| Location | Why safe |
|---|---|
| `domains/hq/trust_safety/repeat_offenders.rb:31` | `profile_ids` derive from a `brand:`-scoped `Report` aggregate |
| `domains/trust/list_blocked_profiles.rb:13` | `.merge(Profile.kept)` refines an already brand-scoped `ProfileBlock` join |
| `domains/notifications/email_presenters/dateza.rb:89` | Both `find_by` calls pass `brand:` |
| `domains/hq/member360/load.rb:144-145` | `profile` is brand-resolved; `Hook` composite FK forbids a cross-brand pair |
| `domains/date9ja/import/photo_transfer.rb:381` | Migration tooling; id from a brand-scoped import batch |
| `domains/admin/mfa/offline_reset.rb:20` | Cross-brand **by design** — revoking a compromised credential must revoke everywhere |
| `domains/admin/mfa/throttle.rb:10` | Cross-brand **by design** — a stricter throttle than per-brand |
| `domains/identity/password_throttle.rb:90` | Brand scoping is an explicit, documented per-purpose policy (`brand_scoped:`), defaulting to `true` |
| `domains/accounts/close_account.rb:53` | `profile` is brand-resolved |
| `domains/profiles/{video_library,detail_serializer}.rb` | `profile` is brand-resolved; a defence-in-depth `ProfileVideo.brand_id == Profile.brand_id` guard was added per `CAPABILITY-PARITY.md` delta log |

### Assessment

**FACT: no P0 tenant-leakage finding.** The database-level composite-FK design means
even a future coding mistake that forgets `brand:` on an association write is
rejected by PostgreSQL. **INFERENCE:** this is the strongest part of the platform and
should be treated as a non-negotiable invariant for every new table.

**One residual risk (P2):** the design depends entirely on developer discipline for
*read* scoping — a forgotten `brand:` on a read is not caught by the database, only
by review. There is no automated guard (no lint rule, no `Current.brand`-asserting
test helper) that would catch a new unscoped read. The sweep above is a point-in-time
result, not a standing gate.

---

## 8. RBAC / security findings

### Positive findings (FACT)

| Area | Finding |
|---|---|
| Static analysis | **Brakeman 8.0.5: 0 security warnings** across 59 controllers, 57 models, 9 templates |
| Dependencies | **bundle-audit: 0 vulnerabilities** (advisory DB updated 2026-09-04) |
| Secrets in repo | **None, ever.** `.kamal/secrets.production` and `.kamal/secrets.staging` are tracked but contain **only `$ENV_VAR` references** — verified across every commit that ever touched them. `.env*`, `config/master.key`, `config/credentials/*.key` are gitignored. |
| Mass assignment | Guarded. `ProfileController#profile_params` derives permitted keys from `Profiles::FieldPolicy`; `Brand#profile_requirements` validates against `Profiles::FieldCatalog` |
| PII in logs | Broad `filter_parameters`: passwords, email, phone, identifier, tokens, OTP/codes, **lat/long/coordinates**, first/last name, and **message `body`** (ADR 0010) |
| Authorization framework | Central capability policy; no controller-only authorization found; unknown role names fail closed |
| Ambiguous privilege | Refused, not merged — `assignments.one?` |
| Privilege escalation | `Admin::RolePolicy` blocks self-management, founder management, and super-admin management by non-founders |
| Write auditing | Every enforcement, moderation, operator, and MFA write emits a `SecurityEvent`; reason text is deliberately excluded (only `has_reason`) |
| Sensitive-read auditing | Every HQ read is audited (§6) |
| Admin response caching | `no-store, private` + ETag stripped on all admin/HQ responses |
| CSRF | Enforced for cookie-authenticated browser sessions (`Identity::BrowserSession`) |
| Encryption at rest | Active Record Encryption keys are mandatory in production (app raises at boot if absent) for OTP delivery codes |
| Founder bootstrap | Deliberately cannot originate an identity — it only promotes an already-registered, verified account, with the reasoning documented in the class itself |

### Negative findings

**P1-1 — Admin MFA step-up has no freshness window. (FACT)**
`Session#admin_mfa_verified_for?` (`app/models/session.rb:45-50`) checks
`admin_mfa_verified_at.present?` and never compares it to a maximum age. Sessions
live 30 days (`Session::DEFAULT_TTL`). `admin_mfa_verified_at` is cleared only by
`Admin::Mfa::Reset`, `Admin::Mfa::OfflineReset`, or credential deletion — never by
elapsed time. **Consequence:** one TOTP entry grants MFA-verified access to the
entire control plane (member PII, security history, enforcement, operator
management) for up to 30 days from any device holding that session token. ADR 0021
documents credential-based invalidation but is silent on time-based freshness.
**Recommendation:** add a step-up freshness window (a small number of hours) and, for
privileged writes, re-challenge. Also consider a shorter session TTL for sessions
that have ever performed admin step-up.

**P2-1 — No general audit browser. (FACT)**
`SecurityEvent` is queryable only member-scoped (`/hq/members/:lookup/security_events`)
or filtered to `warning|high|critical` (`/hq/security_alerts`). There is no way to
answer "what did operator X do this week", which is the primary reason an audit trail
exists.

**P2-2 — No error tracking or APM. (FACT)**
No Sentry/Rollbar/Honeybadger/AppSignal/Datadog/OpenTelemetry in `Gemfile.lock`.
Production observability is tagged STDOUT logs only.

**P3-1 — `security_alerts#index` has no cursor pagination** (limit-clamped to 100).
Every other HQ history endpoint uses a signed cursor.

**P3-2 — No rate limiting on HQ/admin endpoints.** Mitigated by MFA + capability
gating; noted for completeness.

---

## 9. Database findings

### Structure (FACT)

- 57 tables, 75 migrations, 150 foreign keys, schema version `2026_09_04_120000`.
- Separate Solid Queue database (`db/queue_schema.rb`).
- Soft deletion (`deleted_at`) is pervasive, and **every** uniqueness index that
  needs it is partial on `WHERE deleted_at IS NULL` — so soft-deleted rows correctly
  free their unique slot.

### Strengths (FACT)

| Pattern | Example |
|---|---|
| Composite tenant FKs | `fk_messages_conversation_tenant` uses `(conversation_id, brand_id) → (id, brand_id)` — cross-brand association is impossible |
| Triple-key ownership FKs | `fk_profiles_membership_tenant` uses `(brand_membership_id, user_id, brand_id)` — a profile cannot be attached to another user's membership |
| Partial uniqueness for state | `idx_account_enforcements_active_unique ... WHERE reverted_at IS NULL` — at most one active enforcement per (brand,user), enforced by the DB |
| Idempotency at the DB | `analytics_events.idempotency_key`, `notification_events.idempotency_key`, `notification_deliveries.idempotency_key` all unique |
| Delivery fan-out safety | `idx_notification_deliveries_one_channel` / `_one_device_channel` — double-send is a constraint violation, not a bug |
| Check constraints | `chk_profiles_children_count` (0..30) |
| Restrictive associations | `Brand has_many ..., dependent: :restrict_with_exception` on ~25 associations — a brand cannot be deleted out from under its data |
| Opaque external ids | `uuid public_id` with `gen_random_uuid()` defaults on profiles, matches, messages, hooks, conversations, photos, videos, notifications, devices |

### Migration / null-safety review

The concern raised — *"required fields receiving null values in production"* — was
audited directly.

**FACT: only one migration in the entire history tightens an existing column to NOT
NULL**, and it is done correctly:
`db/migrate/20260819000100_add_public_id_to_profile_photos.rb` adds the column
nullable, backfills every row with `gen_random_uuid()` in a single statement, *then*
applies `change_column_null(..., false)` and the unique index — with the reasoning
written into the migration.

Every other NOT NULL column is created NOT NULL at table-creation time, so the class
of failure previously encountered has no remaining instance in this schema.

### Residual data-model observations

| # | Observation | Severity |
|---|---|---|
| 1 | `profiles.gender` is a plain nullable `string` with no enum, check constraint, or catalogue-backed validation at the DB level. Correctness depends entirely on `Profiles::FieldPolicy`. Combined with §6 (no HQ write path), a bad gender value is currently uncorrectable by staff. | **P2** |
| 2 | `profiles.languages` and `profiles.languages_spoken` both exist. ADR 0017 deprecates `languages_spoken`; the column and its `jsonb default: []` remain. Legacy field carrying a live default. | **P3** |
| 3 | Date9ja sensitive fields (`tribe`, `ethnicity`, `genotype`, `denomination`, `religion`) have **no columns**. They exist in `Profiles::FieldCatalog` as `storage: :pending`, `sensitivity: :sensitive_identity`, and are proven fail-closed by `test/domains/profiles/sensitive_capability_fail_closed_test.rb`. This is correct and deliberate — but it means those parity rows are design-only. | Informational |
| 4 | `security_events` and `auth_attempts` have no retention policy in `config/recurring.yml`. They grow without bound. `docs/operations/data-retention.md` exists; no enforcing job does. | **P2** |
| 5 | `discovery_allocations` / `discovery_allocation_candidates` / `find_profile_exposures` are per-member-per-day rows with no pruning job. | **P2** |

---

## 10. API findings

**FACT.** 115 `api/v1` routes across three families. All routes are declared
explicitly — `config/routes.rb` uses no `resources` macro anywhere, so the routing
surface is exactly what is written.

| Family | Routes | Auth | Authorization | Tenant context |
|---|---:|---|---|---|
| Consumer `/api/v1/*` | ~93 | Bearer token or brand cookie | `authenticate_user!` + platform capability gating | Host → `Brands::Resolver` |
| Moderation `/api/v1/admin/*` | 9 | Same session | Admin context + MFA + capability | Host |
| Control plane `/api/v1/hq/*` | 18 | Same session | Admin context + MFA + capability | Host |
| Unauthenticated | 4 | none | none | `health` skips brand resolution entirely |

### Contract discipline (FACT — a genuine strength)

`test/contracts/openapi_contract_test.rb` enforces, as a **passing test**:

1. every routed `api/v1` operation is documented in `docs/api/openapi.yaml` **exactly
   once** (`assert_equal routed_operations, documented_operations`);
2. `operationId`s are unique;
3. every `$ref` is local and resolvable;
4. the runtime `/api/v1/openapi.json` matches the checked-in contract.

**Frontend/backend contract drift is therefore structurally prevented at the route
level.** This is the correct mechanism and it is working.

### Conventions observed (FACT)

- Errors: `{ "error": "<snake_case_code>" }`, occasionally with `details`. Codes are
  chosen per capability (`matching_not_configured`, `messaging_not_configured`,
  `admin_mfa_required`, `csrf_token_invalid`, `session_expired`, `session_revoked`).
- Pagination: signed, purpose-bound, brand-bound cursors — a cursor cannot be
  replayed against another member, brand, or resource type
  (`Hq::Cursor`, `Matching::Cursor`, `Messaging::MessageCursor`, …).
- Admin responses: `Cache-Control: no-store, private`, ETag removed.
- Rate limiting: 15 named policies in `AbuseProtection::Policy` covering messaging,
  likes, passes, reports, hooks, media intent/attach, profile writes, discovery,
  find, hook-tonight, and location search.

### Gaps

| # | Finding | Severity |
|---|---|---|
| 1 | Some consumer mutations carry no rate limit: `profile_blocks#create`/`#destroy`, `matches#unmatch`, `conversations#create`, `notifications#read_all`. | **P3** |
| 2 | No API versioning strategy beyond the `v1` path segment. No deprecation header, no sunset policy. Relevant for Date9ja, whose clients need a compatibility surface. | **P2** |
| 3 | `GET /hq/members/:lookup` uses a permissive route constraint (`/[^\/]+/`) because a lookup may be an email, phone, or UUID. Documented in `routes.rb:63-64`; behaviour is correct, but the route accepts arbitrary strings and relies on `Hq::Identity::Lookup` to reject them. | **P3** |
| 4 | No dead or duplicate endpoints were found. `POST /reports` (generic) and `POST /profiles/:id/report` (legacy) coexist **deliberately** per ADR 0018 to preserve the existing client contract. | Informational |

---

## 11. Frontend findings

**FACT: there is no frontend in this repository.**

- `app/views/` contains **only** mailer templates (identity verification, product
  notifications, DateZA welcome) and mailer layouts.
- `public/` contains **only** `robots.txt` and vendored Swagger UI assets.
- No JavaScript build, no `package.json`, no asset pipeline for a UI.
- `WelcomeController#index` returns a JSON service-status document, not a page.

This is deliberate: **ADR 0004 — API-only core and separate frontends**.

**Therefore the requested MOCK-vs-REAL data distinction was applied to the API layer
instead**, which is where it can be established from this repository. The answer is
in §5: **every HQ endpoint returns live database queries; no mock, static, or
hardcoded data was found.**

**UNKNOWN:** the state of the HQ web client, the DateZA web/mobile clients, and the
HookUs client — including their route structure, state management, role handling,
brand context, loading/empty/error states, responsiveness, and accessibility. These
live in other repositories and **cannot be assessed from here**. `admin-ui.png` at
the repository root is a screenshot with no accompanying source.

**Recommendation:** audit the HQ frontend repository separately before HQ operational
completeness is declared. The backend being real does not establish that the screens
built on it are.

---

## 12. Testing / QA findings

### Commands run (FACT — all executed locally at `931bb04`)

| Command | Result | Detail |
|---|---|---|
| `bin/rails db:test:prepare` | **PASS** | — |
| `bin/rails test` | **FAIL (exit 1)** | 2003 runs, 11942 assertions, **1 failure**, 0 errors, 0 skips, 113.8s, 16 parallel processes |
| `bin/rubocop` | **FAIL** | 832 files, **4 offenses**, all `Layout/TrailingWhitespace`, all autocorrectable, all in `domains/notifications/email_presenters/dateza.rb:170-173` |
| `bin/brakeman` | **PASS** | 0 security warnings, 0 errors |
| `bundle exec bundle-audit check --update` | **PASS** | 0 vulnerabilities |

### The single test failure (FACT)

```
Notifications::DeliverProductNotificationJobTest
  #test_welcome_email_uses_the_DateZA_template_and_a_brand_sender_exactly_once
  test/jobs/notifications/deliver_product_notification_job_test.rb:41
  Expected "<...>" to not include "href=".
```

**Cause, verified:** the test asserts `assert_not_includes message.fetch(:html), "href="`.
The template renders a CTA whenever `@cta_url` is present
(`app/views/product_notification_mailer/dateza_welcome.html.erb:17-18`), and
`Notifications::DeepLink.for` returns a URL unconditionally for `dateza` because of
`DATEZA_DEFAULT_BASE_URL = "https://www.date-za.com"`
(`domains/notifications/deep_link.rb:3,7`). **This is not environment-dependent** — no
env var can make it pass. The assertion is stale relative to an intentional template
change.

**This is pre-existing on `dev`, not introduced by `date9ja-parity`** — verified:
`dev`'s copy of `deep_link.rb` contains the same default constant, and both files
were last touched by the same commit `0537f74`.

**The real finding is not the assertion — it is that `dev` has been red and work
continued.** CI runs `test` on every push to `dev` (`.github/workflows/ci.yml`), so
this has been failing visibly. `docs/engineering/QUALITY-GATES.md` exists and defines
gates; the gate is not being honoured. **Severity: P1 (process).**

### Coverage assessment (FACT)

268 test files, 2003 tests, organised to mirror the domain layer:

| Layer | Coverage |
|---|---|
| Domain services | Strong — `test/domains/` mirrors all 23 domains |
| Request/API | `test/controllers/api/v1/` including `admin/` and `hq/` sub-namespaces |
| Contract | `test/contracts/openapi_contract_test.rb` — route/document parity enforced |
| **Configuration** | **Unusually strong.** `test/config/` asserts CORS, the Docker entrypoint, log parameter filtering, **Kamal production config**, **Kamal staging R2 config**, **production media safety**, and **Solid Queue config**. Deployment configuration is unit-tested. |
| Authorization | Yes — capability, MFA, and fail-closed tests present |
| Tenancy isolation | Present within domain tests; **no dedicated cross-tenant isolation suite** |
| Security | Fail-closed serializer/field tests, MFA throttle, password throttle |
| Migration rehearsal | Extensive — L2 synthetic corpora, byte-transfer, claim/reclaim, derivative integrity |
| Frontend | N/A |
| Type checking | None (Ruby, no Sorbet/RBS) |

### Test-quality findings

| # | Finding | Severity |
|---|---|---|
| 1 | `dev` mainline is red; see above. | **P1** |
| 2 | RuboCop fails on 4 trivial autocorrectable offenses — the lint gate is also red. | **P3** |
| 3 | Two tests merge a **string** key `"enabled_profile_fields"` into a **symbol**-keyed `REQUIREMENTS` hash (`test/domains/profiles/field_catalog_derivation_test.rb:58`, `test/domains/profiles/serializer_fail_closed_test.rb:37`), producing repeated `duplicate key` warnings that will become **errors under json 3.0**. Production is unaffected — `Brand#profile_completion_requirements` calls `deep_stringify_keys` at the boundary. | **P3** |
| 4 | No standing automated guard against unscoped tenant reads (§7). | **P2** |
| 5 | `test/lib/load_testing/` exists; no load test runs in CI. | **P3** |

---

## 13. Production / deployment findings

### Architecture (FACT)

| Aspect | Configuration |
|---|---|
| Orchestration | Kamal, `require_destination: true` — a destination must always be named |
| Environments | `staging` and `production`, separate secret files and separate hosts |
| Production hosts | One server (`164.68.106.97`) running both `web` and `job` roles |
| Proxy | Kamal proxy, SSL on, hosts `api.d8n.tech` and `dateza-api.d8n.tech` |
| Database | External PostgreSQL at `172.18.0.1:5432`; `d8n_production` + `d8n_production_queue` |
| Cache/Redis | **None.** `config.cache_store = :null_store` in production |
| Background jobs | Solid Queue, DB-backed, `JOB_CONCURRENCY=1`, 3 threads |
| Media | Cloudflare R2, **per-brand buckets and per-brand bucket-scoped credentials** |
| Health check | `GET /api/v1/health` — verifies both DB pools, returns 503 when degraded |
| Migrations | `bin/rails db:prepare` on **every** web and job container boot |
| Secrets | Kamal secret files containing only `$ENV` references; resolved from the deploy host |
| Encryption | AR Encryption keys mandatory — app raises at boot in production if absent |
| Brand host mapping | DB-backed `BrandDomain`, installed idempotently at boot via `brands:install_dateza` / `brands:install_date9ja` when the corresponding host env var is set |
| Observability | Tagged STDOUT logs with `request_id`; **no APM, no error tracking** |
| Backup | `docs/operations/postgres-backup-restore.md` exists (**UNKNOWN** whether the schedule is actually running — cannot be verified from this repository) |
| Rollback | `docs/operations/deploy-rollback.md` exists |

### Recurring jobs configured (FACT, `config/recurring.yml`)

| Job | Schedule |
|---|---|
| `SolidQueue::Job.clear_finished_in_batches` | hourly at :12 |
| `Media::PurgeUnattachedUploadsJob` | daily 03:00 |
| `AbuseProtection::PurgeRateLimitCountersJob` | hourly at :27 |
| `Notifications::RecoverPendingJob` | every minute |

### Findings

**P1-2 — Two media recovery sweepers are built, tested, and never scheduled. (FACT)**
`Media::ProfilePhotoProcessingSweeper` (`domains/media/profile_photo_processing_sweeper.rb`)
and `Media::ProfileVideoProcessingSweeper`
(`domains/media/profile_video_processing_sweeper.rb`) exist with passing tests
(`test/domains/media/profile_photo_processing_sweeper_test.rb`,
`test/domains/media/process_profile_video_job_claim_test.rb:117`). A repository-wide
search found **no `config/recurring.yml` entry, no rake task, and no production call
site**. The video sweeper's own comment describes its purpose as re-enqueuing
`Media::ProcessProfileVideoJob` for rows stranded in `processing`.
**Consequence:** if a media processing job dies mid-flight in production — worker
restart, deploy, OOM — the photo or video is stuck in `processing` **permanently**,
with no automatic recovery. The claim-token/stale-reclaim machinery added in
migrations `20260903130000` and `20260904120000` exists precisely to make recovery
safe, and nothing invokes it. **Remediation:** add both to `config/recurring.yml`.
This is a small, low-risk change with a real production consequence.

**P2-3 — Migrations run on container boot with no pre-deploy gate. (FACT)**
`bin/docker-entrypoint` runs `db:prepare` for both the web and job roles. With `web`
and `job` on the same host this is a startup race (mitigated by Rails' migration
advisory lock, **INFERENCE**), but more importantly there is no pre-deploy migration
step, no dry run, and no automated rollback path for a bad migration. Kamal hooks are
all still `.sample`.

**P2-4 — Single production host, both roles. (FACT)** `web` and `job` share
`164.68.106.97`. A host failure is total. No horizontal redundancy.

**P2-5 — No error tracking or APM. (FACT)** Repeated from §8. For a platform now
carrying real users on two brands, "grep the logs" is the only incident tool.

**P2-6 — No retention enforcement.** `security_events`, `auth_attempts`,
`analytics_events`, `discovery_allocations`, and `find_profile_exposures` grow
without bound. `docs/operations/data-retention.md` documents intent; no job enforces
it.

**P3-3 — Kamal hooks unused.** All nine hooks are `.sample`. No pre-deploy health
gate, no post-deploy verification.

**UNKNOWN (cannot be established from this repository, and deliberately not
investigated because it would require touching production):** whether backups are
actually running and restorable; current production data volumes; whether the
production database has drifted from `db/schema.rb`; actual uptime and error rates.

---

## 14. Date9ja → D8N parity matrix

**The authoritative matrix is `docs/migrations/date9ja-to-d8n/CAPABILITY-PARITY.md`
(95 capabilities, updated 2026-09-05), and this audit does not replace it.** Its
counts were verified against implementation for the capabilities requested:

| Status | Count |
|---|---:|
| PARITY | **1** |
| PARTIAL | 42 |
| MISSING | 40 |
| DIFFERENT SEMANTICS | 11 |
| NEEDS PRODUCT DECISION | 1 |
| **Total** | **95** |

### Requested capability rollup, verified against code

| Capability | Date9ja requirement | D8N implementation (verified) | Gap | Migration blocker? |
|---|---|---|---|---|
| **Auth** | Devise email/password + JWT, confirmable, custom phone OTP | `Identity::Password{Registration,Login}`, opaque brand-bound sessions, OTP challenges, recovery, reactivation. **bcrypt `$2a$12$` compatibility proven** (`scripts/date9ja/bcrypt_proof.rb`, VERIFIED 2026-09-02) | JWT→session semantics differ; client contract change required | **Yes** |
| **Profiles** | Progressive user-column onboarding, broad `/me` writes | Server-owned configuration + `Profiles::FieldPolicy` + brand catalogues (ADR 0030). **Importer rehearsal VERIFIED 2026-09-03: 280/288 imported, 8 `source_soft_deleted`, 0 failed, idempotent on rerun** | Field-by-field mapping incomplete | **Yes** |
| **Gender / preferences** | Integer enums on `users` | `profiles.gender` string, `profile_preferences.interested_in` | Mapping + validation contract; **no staff correction path** (§6) | **Yes** |
| **Discovery** | Daily picks, explore, impressions, limits | `Matching::Discovery`, `StableDailySelection`, `Find`, per-brand strategies incl. `Date9jaContract` | Semantics differ; Date9ja strategy is a stub contract | **Yes** |
| **Likes** | Direct user relationships | Profile-scoped `Like` with brand-partial unique pair | Identity → profile remapping | **Yes** |
| **Matching** | Match doubles as chat container | First-class `Match` + `Conversation` + `ConversationParticipant` | Structural remap of every legacy match | **Yes** |
| **Chat** | Match-scoped CRUD, reactions, realtime, typing | `Messaging::*` — conversation-scoped, attachments, reply-to, per-participant `last_read_at` | **No reactions model. No realtime — `app/channels` does not exist.** No typing/presence | **Yes** |
| **Notifications** | Inbox, email, push, preferences, Cable toasts | `NotificationEvent` → `Notification` → `NotificationDelivery`; email (Resend) + SMS (Twilio) + push scaffolding; typed preferences | Push provider gated; no realtime | **Yes** |
| **Media** | 6 photos, video, moderation | Photos + one video per profile, R2 direct upload, signed retrieval, derivatives, moderation. **Photo pass 2 byte transfer VERIFIED (Codex ACCEPT 2026-09-03); video pass 1 preflight VERIFIED, 35/35** | Video pass 2 in progress (ADR 0029). **Sweepers unwired (P1-2)** | **Yes** |
| **Verification** | Selfie, video, gov-ID/RealMe, badges, tiers, history | **`domains/verification/` is empty.** Only contact-identifier verification exists | **Entire capability absent.** ADR 0024 designed, not built | **Yes** |
| **Blocking** | User block list | `ProfileBlock` + `Trust::BlockPolicy` with relationship cleanup | Semantics differ (profile vs user) | **Yes** |
| **Reporting** | Profile + message reports | `Report` with polymorphic target + `evidence` jsonb (ADR 0018) | Reason taxonomy mapping | **Yes** |
| **Moderation** | Admin flags, photo review, suspend/ban | `/api/v1/admin/*` report queue, photo moderation, suspend/ban/reinstate, all audited | Legacy admin surface must map to HQ before retirement | **Yes** |
| **Admin** | Legacy Date9ja admin backend | D8N HQ — 18 endpoints, RBAC, MFA, Member 360 | **Read-only. No member editing.** No cross-brand search | **Yes** |
| **Analytics** | Signup/profile/verification/match/conversation metrics, UTM attribution | `AnalyticsEvent` model with **exactly 2 event types** (`member.registered`, `profile.published`) | Almost entirely absent; no attribution capture | No (matrix: not a cutover blocker) |

### Capabilities with no D8N home at all (FACT)

`domains/verification/` and `domains/billing/` are empty. There is no Community
domain, no Dating Hub, no AI/Aunty Phobie, no careers, no feedback, no support-chat,
no trust ledger (ADR 0025 is Proposed), no entitlements (ADR 0026 is Proposed), and
no realtime. Per `CAPABILITY-PARITY.md`'s scope rule — *"Every shipped/reachable
Date9ja user-facing capability is inside the parity bar unless the product owner
explicitly retires it"* — these are all in scope today.

### Migration program state (FACT, from `STATUS.md` @ 2026-09-05)

Verified as **genuinely rehearsed with operator evidence**:
- bcrypt compatibility — VERIFIED against a real production-format hash
- sanitized snapshot + schema-signature v2 — VERIFIED (independent review)
- identity/membership/non-sensitive-profile importer — VERIFIED, operator rehearsal, idempotent
- photo pass 1 preflight + pass 2 byte transfer — VERIFIED (Codex FINAL VERDICT ACCEPT)
- video pass 1 preflight — VERIFIED, 35/35, idempotent
- auth transition + recovery/reactivation — self-verified, awaiting review

Explicitly **not** achieved, in the program's own words:
> **NOT PARITY_ACCEPTED, NOT production-ready, NOT cutover-ready. L3 NOT YET READY.**

### Readiness verdict

> **NOT READY.** 1 of 95 capabilities at parity. Verification, billing, community,
> AI, and realtime have no implementation. The migration *tooling* is genuinely
> mature and rehearsed with real operator evidence; the *platform capabilities the
> tooling would migrate into* mostly do not exist yet.

**INFERENCE:** the program's own documentation is accurate and appropriately
pessimistic. The risk here is **not** that the team is overstating readiness — it is
the opposite: enormous verification rigour is being applied to migration mechanics
while ~40 destination capabilities remain unbuilt. The bottleneck is capability
construction, not migration engineering.

---

## 15. Duplication / architectural drift

| # | Duplication | Locations | Classification |
|---:|---|---|---|
| 1 | **Admin/HQ base controllers are near-identical** — `authenticate_admin!`, `require_admin_mfa!`, `authorize_admin_capability!`, `render_admin_*`, `disable_admin_http_caching`, and `requires_admin_capability` are duplicated verbatim | `app/controllers/api/v1/admin/base_controller.rb` and `.../hq/base_controller.rb` | **Architectural debt.** Two copies of a security boundary is the worst place to have a copy — a hardening fix applied to one silently misses the other. Extract a shared concern. |
| 2 | **Three signed-cursor implementations** | `Hq::Cursor` (45 L), `Hq::MemberDirectoryCursor` (66 L), `Hq::TrustSafety::EnforcementCursor` (48 L) — each with its own `Invalid`, `PURPOSE`, `encode`, `apply` | **Architectural debt.** Same pattern, three times; each binds slightly different context. One parameterised cursor would do. |
| 3 | **Two enforcement-history services** | `Hq::EnforcementHistory` (member-scoped, 51 L) and `Hq::TrustSafety::EnforcementHistory` (brand-wide, 67 L) | **Legitimate separation** — different scopes and capabilities, but they should share a serializer/query core. |
| 4 | **Two demo-seed systems** | `Profiles::DemoSeed` (141 L) + `Profiles::DateZADemoSeed` (128 L), plus `lib/tasks/hookus_demo.rake` and `dateza_demo.rake` | **Architectural debt.** Per-brand copies of dev tooling; will be copied a third time for Date9ja. |
| 5 | **Three brand profile catalogues** | `Profiles::{Hookus,Dateza,Date9ja}ProfileCatalog` | **Legitimate separation** — brand data, not brand logic, and ADR 0030 has now given them a shared `FieldCatalog` to validate against. |
| 6 | **Three brand installers** | `Brands::{Hookus,Dateza,Date9ja}Installer` + `Brands::Provisioner` | **Legitimate separation**, but overlaps #5; brand identity is expressed in two places. |
| 7 | **Brand knowledge is still multi-sourced** | `D8n::Platform::Brands::*`, `Profiles::*ProfileCatalog`, `Brand#auth_methods`, `Matching::StrategyRegistry`, `Matching::Find::PolicyRegistry`, `Media::{Photo,Video}Policy`, `Notifications::EmailPresenters::*`, R2 storage config | **Architectural debt — the largest one.** The 2026-08-24 audit named this; `D8n::Platform::Catalog` has materially improved it, but adding a brand still means editing ~8 places. This is the concrete gap between "shared platform" and "new brand is configuration-only". |
| 8 | **Two report entry points** | `POST /reports` (generic, ADR 0018) and `POST /profiles/:id/report` (legacy) | **Temporary migration state — deliberate and documented.** |
| 9 | **`languages` and `languages_spoken`** | `profiles` table + serializers | **Temporary migration state.** ADR 0017 deprecates `languages_spoken`; both remain live. |
| 10 | Four overlapping agent-workflow documents | `AGENTS.md`, `AGENT_RULES.md`, `docs/engineering/AGENT-WORKFLOW.md`, `docs/architecture/agent-workflow.md` | **Documentation debt** — §18. |

**No dangerous divergence was found.** There is no second auth system, no second
member representation, no second messaging implementation, and no second admin
system. Every duplication above is either deliberate brand data, a documented
transitional state, or ordinary refactorable debt.

---

## 16. Dead / abandoned / half-built work

**Nothing below was removed. Evidence only, as instructed.**

| # | Item | Evidence | Assessment |
|---:|---|---|---|
| 1 | **`Media::ProfilePhotoProcessingSweeper` and `Media::ProfileVideoProcessingSweeper`** | Implemented, tested, referenced by no scheduler, task, or production caller | **Half-built with production consequence — P1-2** |
| 2 | `domains/verification/` | Contains only `.keep`. ADR 0024 (shared verification evidence) is designed | **Planned only** |
| 3 | `domains/billing/` | Contains only `.keep`. ADR 0026 (entitlement preservation) is designed | **Planned only** |
| 4 | `domains/analytics/` | `EventTypes::DEFINITIONS` has exactly 2 entries; 2 call sites | **Scaffolded** |
| 5 | `profiles.languages_spoken` | Column + `jsonb default: []` live; deprecated by ADR 0017 | **Legacy field** |
| 6 | Capabilities granting no endpoint | `Admin::Capabilities` defines `SYSTEM_READ`, `BRAND_OPERATIONS`, `ENFORCEMENTS_OVERRIDE` — no route consumes them | **Intentional forward declaration** — the module says so in its own comment. Not dead, but currently inert. |
| 7 | Kamal hooks | All nine remain `.sample` | **Unused scaffolding** |
| 8 | Redis service in CI | Commented out in `.github/workflows/ci.yml` | **Stale config** |
| 9 | `config/environments/development.rb:64` | Commented `action_cable.disable_request_forgery_protection` | **Rails default residue** |
| 10 | `test/lib/load_testing/` + `script/load_test` | Present; not in CI | **Unused tooling** |
| 11 | `docs/FOUNDER-HQ/idea.md` | **0 bytes**, tracked | **Empty file** |
| 12 | Root binaries: `ChatGPT Image Aug 25...png` (1.5 MB), `admin-ui.png` (1.7 MB) | Tracked at repository root | **Stray artifacts** — 3.2 MB in git for no build purpose |
| 13 | `docs/user-images/` | ~140 tracked JPEG/PNG files used by demo seeds | **In use**, but heavy for a git repository |
| 14 | `spike/rodauth-phone-otp` branch | Remote branch; Rodauth is used only as a password library | **Abandoned spike** |
| 15 | 12 open Dependabot branches | `rails 8.1.3.1`, `brakeman`, `bootsnap`, `solid_queue` ×2, `thruster` ×3, `rodauth-rails`, `actions/checkout` | **Unmerged dependency updates** |

**FACT: zero `TODO`, `FIXME`, `HACK`, or `XXX` markers exist anywhere in `app/`,
`domains/`, `lib/`, `config/`, or `test/`.** Incomplete work is tracked in the
`TODO/` directory and `STATUS.md` rather than scattered through the code. That is
genuinely unusual discipline and worth preserving.

---

## 17. Risk register

### P0 — Critical

**None.**

No security vulnerability, no cross-tenant data leakage, no data-corruption path, and
no production-breaking architectural fault was identified. Brakeman, bundle-audit,
the tenant sweep, the secret-history scan, and the migration null-safety review were
all clean.

---

### P1 — High

#### P1-1 · Admin MFA step-up never expires

- **Evidence:** `app/models/session.rb:45-50` (`admin_mfa_verified_at.present?` with
  no age comparison); `Session::DEFAULT_TTL = 30.days` (`session.rb:3`);
  `admin_mfa_verified_at` cleared only by `Admin::Mfa::{Reset,OfflineReset}`.
- **Affected:** all 18 HQ endpoints, all 9 admin endpoints.
- **Consequence:** a single TOTP entry grants MFA-verified control-plane access —
  member PII, security history, enforcement, operator management — for up to 30 days
  from any device holding the session token. The MFA control provides far less
  assurance than ADR 0021 implies.
- **Remediation:** add a step-up freshness window to `admin_mfa_verified_for?`;
  re-challenge for privileged writes; consider a shorter TTL for admin-stepped
  sessions. Update ADR 0021 to state the freshness policy explicitly.
- **Blocks future phases:** yes — blocks HQ operational completeness.

#### P1-2 · Media processing sweepers are built, tested, and never scheduled

- **Evidence:** `domains/media/profile_photo_processing_sweeper.rb`,
  `domains/media/profile_video_processing_sweeper.rb`; absent from
  `config/recurring.yml`; repository-wide search finds no production call site;
  tests exist at `test/domains/media/profile_photo_processing_sweeper_test.rb` and
  `test/domains/media/process_profile_video_job_claim_test.rb:117`.
- **Consequence:** any media processing job killed mid-flight (deploy, restart, OOM)
  leaves the photo or video in `processing` **permanently**. The claim-token and
  stale-reclaim machinery added in migrations `20260903130000` /
  `20260904120000` exists to make recovery safe, and nothing triggers it.
- **Remediation:** add both sweepers to `config/recurring.yml`. Small, low-risk.
- **Blocks future phases:** yes — blocks Date9ja media migration at production scale,
  where processing failures are certain.

#### P1-3 · Mainline CI is red and work has continued

- **Evidence:** `bin/rails test` → 1 failure at
  `test/jobs/notifications/deliver_product_notification_job_test.rb:41`; the
  assertion is unsatisfiable given
  `Notifications::DeepLink::DATEZA_DEFAULT_BASE_URL`; verified present on `dev`;
  `.github/workflows/ci.yml` runs `test` on push to `dev`.
- **Consequence:** a red baseline destroys the signal value of the whole suite. Every
  future failure must be triaged against "is this the known one?" — and
  `docs/engineering/QUALITY-GATES.md` is not being enforced.
- **Remediation:** decide whether the CTA is intended (it is — the template and
  `DeepLink` were changed together in `0537f74`), fix the assertion, restore green,
  and treat mainline red as a stop-the-line condition.
- **Blocks future phases:** yes — every phase's acceptance criteria depend on a
  trustworthy suite.

#### P1-4 · HQ has no member write path

- **Evidence:** no `POST`/`PATCH`/`PUT` under `hq/members` in `config/routes.rb`;
  `Hq::Member360::Load` is read-only by design.
- **Consequence:** staff can see everything and correct nothing. A member with a
  wrong gender or wrong `interested_in` — which directly determines discovery
  eligibility — can only be fixed by asking the member to fix it themselves, or by a
  console operation with no audit trail. For Date9ja migration, where imported data
  *will* need correction, this is a functional blocker.
- **Remediation:** design an audited, capability-gated, field-allowlisted member
  correction endpoint. It must reuse `Profiles::FieldPolicy` (not bypass it), write
  through `Profiles::Publication` re-gating, and emit a `SecurityEvent` recording
  before/after — the pattern `Admin::OperatorManagement.audit!` already establishes.
- **Blocks future phases:** yes — blocks HQ operational completeness and Date9ja
  migration support.

---

### P2 — Medium

| ID | Risk | Evidence | Consequence | Remediation | Blocks? |
|---|---|---|---|---|---|
| P2-1 | No general audit browser | `SecurityEvent` readable only member-scoped or severity-filtered | "What did operator X do this week?" is unanswerable | Brand-scoped, filterable, cursor-paginated `SecurityEvent` read behind a new capability | HQ completeness |
| P2-2 | No error tracking / APM | No such gem in `Gemfile.lock` | Incidents are diagnosed by grepping STDOUT | Add one error tracker; keep it cheap | No |
| P2-3 | No standing guard against unscoped tenant reads | §7 sweep is point-in-time; DB FKs catch writes, not reads | A future forgotten `brand:` on a read is caught only by review | Add a tenancy isolation test suite and/or a custom RuboCop cop | Platform foundation |
| P2-4 | Brand knowledge multi-sourced across ~8 registries | §15 #7 | Adding a brand is not configuration-only | Continue consolidating behind `D8n::Platform::Catalog` | Platform foundation |
| P2-5 | Security-boundary code duplicated across two base controllers | §15 #1 | A hardening fix can silently miss one namespace | Extract a shared concern | Platform foundation |
| P2-6 | No retention enforcement | `security_events`, `auth_attempts`, `analytics_events`, `discovery_allocations`, `find_profile_exposures` unpruned; `docs/operations/data-retention.md` documents intent only | Unbounded growth; privacy exposure widens over time | Add recurring pruning jobs matching the documented policy | No |
| P2-7 | Migrations run on container boot; no pre-deploy gate | `bin/docker-entrypoint`; all Kamal hooks `.sample` | A bad migration is discovered during boot, mid-deploy | Move to a pre-deploy step with a verification hook | Production readiness |
| P2-8 | Single production host runs both roles | `config/deploy.production.yml` | Host failure is total outage | Separate job host, or accept and document | No |
| P2-9 | `profiles.gender` has no DB-level constraint | `db/schema.rb:928` — plain nullable string | Bad values possible; combined with P1-4, uncorrectable | Constrain at the catalogue and consider a check constraint | Date9ja parity |
| P2-10 | No API versioning/deprecation strategy | Only the `v1` path segment | Date9ja clients need a compatibility surface with a sunset path | Define a deprecation policy before cutover | Date9ja migration |
| P2-11 | Analytics is a 2-event scaffold | `domains/analytics/event_types.rb` | Funnel/product intelligence returns `unavailable` for most stages | Instrument the onboarding and interaction funnel | HQ completeness |
| P2-12 | No realtime capability | No `app/channels` | Date9ja has Action Cable messaging, typing, presence, toasts | Decide build vs. retire before parity acceptance | Date9ja parity |

---

### P3 — Low

| ID | Risk | Evidence |
|---|---|---|
| P3-1 | RuboCop red — 4 autocorrectable `Layout/TrailingWhitespace` | `domains/notifications/email_presenters/dateza.rb:170-173` |
| P3-2 | Test duplicate-key warnings; will error under json 3.0 | `test/domains/profiles/field_catalog_derivation_test.rb:58`, `serializer_fail_closed_test.rb:37` |
| P3-3 | `security_alerts#index` lacks cursor pagination | `app/controllers/api/v1/hq/security_alerts_controller.rb` |
| P3-4 | Some consumer mutations unthrottled | blocks, unmatch, conversation create, read-all |
| P3-5 | 3.2 MB of stray PNGs tracked at repository root | `ChatGPT Image Aug 25...png`, `admin-ui.png` |
| P3-6 | `docs/FOUNDER-HQ/idea.md` is 0 bytes and tracked | — |
| P3-7 | Kamal hooks all `.sample`; Redis service commented out in CI | `.kamal/hooks/`, `.github/workflows/ci.yml` |
| P3-8 | 12 open Dependabot branches, incl. a Rails patch | `git branch -a` |
| P3-9 | Three near-identical signed-cursor classes | §15 #2 |
| P3-10 | Two demo-seed systems; will become three | §15 #4 |
| P3-11 | `languages_spoken` legacy column live | ADR 0017 |
| P3-12 | Load-test tooling exists but never runs | `test/lib/load_testing/`, `script/load_test` |

---

## 18. Documentation health

**FACT.** ~118 markdown documents, roughly 1.1 MB, plus 30 ADRs (0001–0030) and a
7-file `TODO/` tracker.

### Genuine strengths

1. **`docs/engineering/DOCUMENTATION-POLICY.md` exists and defines an explicit
   authority map** — one concern, one source of truth. Very few codebases have this.
2. **`docs/FOUNDER-HQ/D8N-HQ/CURRENT-STATE.md` is accurate.** It was spot-checked
   against implementation across identity, brands, RBAC, and trust & safety and every
   claim held. It explicitly marks unverifiable items `PARTIAL`/`MISSING` "even if a
   plausible-sounding class exists" — and does so honestly.
3. **`CAPABILITY-PARITY.md` is honest and pessimistic.** 1/95 PARITY with a delta log.
4. **`STATUS.md` distinguishes IMPLEMENTED / SELF_VERIFIED / VERIFIED / PARITY_ACCEPTED**
   and refuses to claim the higher grades. Operator rehearsal evidence is recorded
   with dates and counts.
5. **The ADR set is real** — 30 ADRs, correctly marked Accepted vs Proposed, and code
   references them by number in comments.

### Health assessment

| Category | Documents |
|---|---|
| **Authoritative / current** | `docs/adr/0001-0030`, `docs/architecture/*`, `CAPABILITY-PARITY.md`, `STATUS.md`, `MASTER-PLAN.md`, `docs/api/openapi.yaml` (test-enforced), `docs/FOUNDER-HQ/D8N-HQ/CURRENT-STATE.md`, `docs/engineering/*` |
| **Useful but incomplete** | `docs/operations/*` (documents intent that no job enforces — §13), `docs/FOUNDER-HQ/D8N-HQ/METRICS.md` |
| **Historical** | `docs/audits/D8N_PLATFORM_ARCHITECTURE_REUSE_AUDIT.md` (2026-08-24 — its four drift findings are now remediated), `docs/audits/DATEZA_EMPTY_DISCOVERY_INVESTIGATION_2026-08-25.md`, `docs/performance/staging-capacity-2026-08-14.md` |
| **Superseded** | `docs/architecture/agent-workflow.md` (redirects to `docs/engineering/AGENT-WORKFLOW.md`), Phase-0 "legacy-only can wait" framing in `AUDIT.md` / `MIGRATION-MATRIX.md` (self-labelled superseded) |
| **Duplicated** | **`AGENTS.md` (5 KB) vs `AGENT_RULES.md` (16 KB) vs `docs/engineering/AGENT-WORKFLOW.md` (3.7 KB)** — three live agent-instruction documents; **`docs/MVP_PLAN.md` (27 KB) vs `docs/HOLISTIC_PLAN.md` (31 KB) vs `PLAN_OF_ACTION.md` (52 KB)** — three planning documents, only the last named in the authority map |
| **Contradictory** | `TODO/README.md` documents its own supersession ("the strict milestones-in-order gate has in practice been superseded by beta-loop-first prioritization") but the milestone files remain as-written. Overlapping "where are we" claims across `TODO/`, `D8N_NOW_NEXT_LATER.md`, `D8N_FOUNDER_STATE.md`, `D8N-HQ/ROADMAP.md`, and `STATUS.md` |
| **Speculative** | ADR 0025 (trust ledger) and ADR 0026 (entitlements) are Proposed with no implementation; ADR 0028 is a design checkpoint with open decisions |
| **Unclear** | `docs/FOUNDER-HQ/idea.md` (0 bytes) |

### Documentation risks

1. **The authority map does not cover the whole repository.** It covers the Date9ja
   program and engineering process well; it is silent on `docs/MVP_PLAN.md`,
   `docs/HOLISTIC_PLAN.md`, `README.md` (29 KB), the entire `docs/FOUNDER-HQ/D8N-HQ/`
   set (12 documents, 190 KB), and `TODO/`.
2. **Five documents plausibly answer "where are we".** `STATUS.md`,
   `D8N_NOW_NEXT_LATER.md`, `D8N_FOUNDER_STATE.md`, `D8N-HQ/ROADMAP.md`, `TODO/`.
   A new contributor cannot tell which wins.
3. **Volume is becoming a hazard.** `STATUS.md` is 107 KB and `MEDIA-TRANSFER.md`
   is 96 KB. Documents that long are appended to, not read.

### Recommendations (not executed — this audit deletes and consolidates nothing)

| Should become canonical | Should eventually be archived |
|---|---|
| `docs/engineering/DOCUMENTATION-POLICY.md` — extend its authority map to cover HQ, planning, and `TODO/` | `docs/MVP_PLAN.md`, `docs/HOLISTIC_PLAN.md` → `docs/archive/` once superseded by `PLAN_OF_ACTION.md` |
| `docs/FOUNDER-HQ/D8N-HQ/CURRENT-STATE.md` — the single HQ status truth | `docs/FOUNDER-HQ/D8N-HQ/PHASE-1-IMPLEMENTATION.md`, `PHASE-2-IMPLEMENTATION.md` once their phases close |
| `CAPABILITY-PARITY.md` — the single parity truth | `docs/audits/D8N_PLATFORM_ARCHITECTURE_REUSE_AUDIT.md` → mark **historical**, with a pointer to this document recording its remediations |
| `AGENT_RULES.md` — pick **one** agent-instruction document | The other two agent documents become pointers |
| `docs/FOUNDER-HQ/D8N_NOW_NEXT_LATER.md` — the single NOW/NEXT/LATER view | `TODO/` milestone files, once folded into it |
| Split `STATUS.md` into a short current-state head + a dated evidence appendix | `docs/FOUNDER-HQ/idea.md` (0 bytes) — delete |

---

## 19. Actual current phase

### Evidence

| Signal | Reading |
|---|---|
| Shared platform foundation | **Built.** Tenancy DB-enforced, capability catalogue landed, prior drift findings remediated |
| Consumer product loop | **Live on two brands** — HookUs and DateZA on production hosts with real R2 buckets and providers |
| HQ vertical slice | **Read side complete, write side absent** |
| Verification / billing / analytics / realtime / community | **Absent or scaffolded** |
| Date9ja parity | **1 / 95** |
| Date9ja migration tooling | **Rehearsed with real operator evidence** through photo pass 2 and video pass 1 |
| Quality gates | **Defined, structurally strong, and currently red on mainline** |
| Production hardening | **Partial** — no APM, no retention enforcement, single host, unscheduled recovery jobs |

### Determination

> **D8N is at the completion of shared-platform foundation and the beginning of HQ
> operational build-out, running a live two-brand consumer product, with the Date9ja
> migration in evidence-gathering and rehearsal — not execution.**

In the vocabulary requested: **early shared-platform implementation, with an HQ
vertical slice half-delivered, and parity preparation only just started.**
Explicitly **not migration ready**.

### Why, without optimism

The platform is further along than the parity number suggests, and less far along
than the migration document volume suggests. Both distortions matter.

- The **foundation is genuinely good**. Database-enforced tenancy, a single auth
  mechanism, a real capability catalogue, an enforced API contract, 2003 tests, zero
  Brakeman warnings, no committed secrets, and zero TODO markers is a stronger base
  than most products at this stage. The 2026-08-24 audit's drift findings were
  actually fixed rather than documented and forgotten.

- The **HQ slice stops at read**. Member 360 is excellent and answers "what is
  happening to this member" completely. It cannot answer "and now fix it". An
  operations tool that can only observe is half a tool, and it is the half that does
  not close tickets.

- The **migration program is inverted**. Extraordinary rigour — synthetic corpora,
  byte-level integrity verification, claim tokens, independent Codex review, operator
  rehearsals with counts — is being applied to *moving* data into capabilities that
  do not exist. Verification, billing, community, AI, realtime, trust ledger,
  entitlements: 40 MISSING rows. The constraint on cutover is not migration
  engineering. It is that roughly 40 destination capabilities have not been built.

- The **discipline signal is mixed**. Zero TODO markers, an enforced OpenAPI contract,
  tested Kamal configuration, and honest status documents indicate a high-discipline
  team. A red mainline test, a red lint gate, and two tested-but-never-scheduled
  recovery jobs indicate that the *last mile* — wiring things up and keeping the gate
  green — is where attention is being lost. The three findings are small individually
  and diagnostic collectively.

---

## 20. Recommended phased roadmap

Sequenced against repository evidence rather than the generic template. Two
deviations from the suggested order, both evidence-driven:

- **Phase 1 is deliberately small.** There is no P0. The critical-correctness phase is
  four contained items, not a hardening programme — inflating it would contradict the
  project's own "not a bank" proportionality principle (`TODO/README.md`).
- **Phase 4 (capability construction) is separated from Phase 5 (parity acceptance)**
  because the evidence shows the bottleneck is *building the 40 MISSING
  capabilities*, not migration engineering. Bundling them hides the real work.

**Nothing below has been started. This is a recommendation awaiting approval.**

---

### Phase 1 — Restore the baseline

**Objective:** make the quality signal trustworthy and close the four
correctness/security gaps that are small, contained, and currently costing real
safety.

**Scope**
1. Fix `deliver_product_notification_job_test.rb:41` so the assertion matches the
   intended CTA behaviour; restore green mainline. **(P1-3)**
2. Add both media processing sweepers to `config/recurring.yml`. **(P1-2)**
3. Add an MFA step-up freshness window to `Session#admin_mfa_verified_for?`;
   re-challenge for privileged writes; update ADR 0021. **(P1-1)**
4. `bin/rubocop -a` on the 4 trailing-whitespace offenses; fix the two duplicate-key
   test hashes. **(P3-1, P3-2)**

**Dependencies:** none.

**Acceptance criteria**
- `bin/rails test` exits 0; `bin/rubocop` exits 0; Brakeman and bundle-audit stay clean.
- A photo and a video artificially stranded in `processing` are recovered by the
  scheduled sweeper within one interval.
- An admin session older than the freshness window is refused at an HQ endpoint until
  it re-challenges.

**Verification:** full local suite + CI green on the branch; a staging sweeper
rehearsal on a deliberately stranded row; an MFA freshness request test.

**Explicit non-goals:** no refactoring, no new endpoints, no schema changes, no
observability work.

---

### Phase 2 — Platform foundation gaps

**Objective:** make the tenancy invariant self-defending and make adding a brand
closer to configuration-only.

**Scope**
1. A dedicated tenancy-isolation test suite: for each brand-bearing resource, prove a
   brand-A session cannot read or write a brand-B row through any route. **(P2-3)**
2. Extract the shared admin/HQ authorization concern from the two duplicated base
   controllers. **(P2-5)**
3. Consolidate the three signed-cursor classes into one parameterised implementation.
   **(P3-9)**
4. Continue consolidating brand knowledge behind `D8n::Platform::Catalog`; produce a
   written "what it takes to add a brand" checklist enumerating every remaining
   touch point. **(P2-4)**
5. Add error tracking. **(P2-2)**
6. Add retention/pruning jobs matching `docs/operations/data-retention.md`. **(P2-6)**

**Dependencies:** Phase 1 (a green baseline is required to trust refactors).

**Acceptance criteria**
- The isolation suite fails if `brand:` is removed from any audited read.
- One authorization implementation serves both `admin` and `hq` namespaces.
- The brand checklist is ≤ 5 touch points, or the remaining count is documented with
  rationale.
- Unbounded tables have an enforced retention job.

**Verification:** the isolation suite; a `bin/rails brands:provision` dry run against
the checklist.

**Explicit non-goals:** no new product capability, no HQ writes, no Date9ja work.

---

### Phase 3 — HQ operational completeness

**Objective:** make HQ an operations tool that can resolve an incident, not only
observe one.

**Scope**
1. **Audited member correction endpoint. (P1-4)** Capability-gated, field-allowlisted
   via `Profiles::FieldPolicy`, writing through `Profiles::Publication` re-gating,
   emitting a before/after `SecurityEvent` in the same transaction. Gender and
   `interested_in` are the first fields, because they gate discovery eligibility.
2. **General audit browser. (P2-1)** Brand-scoped, filterable, cursor-paginated
   `SecurityEvent` read behind a new capability.
3. **Analytics instrumentation. (P2-11)** Expand `Analytics::EventTypes` to cover the
   onboarding and interaction funnel so `ProductIntelligence::Funnel` stops returning
   `unavailable_stage`.
4. Cursor-paginate `security_alerts#index`. **(P3-3)**
5. **Audit the HQ frontend repository** — the MOCK-vs-REAL question this audit could
   not answer (§11).

**Dependencies:** Phase 1 (MFA freshness must land before broadening write powers);
Phase 2 (shared authorization concern).

**Acceptance criteria**
- A support operator can correct a member's gender, and the change is audited, brand
  scoped, and immediately reflected in `discovery_diagnostic`.
- "What did operator X do between two timestamps" is answerable via API.
- The funnel returns real values for every stage or an explicit, justified
  unavailability.

**Verification:** an end-to-end HQ journey test (lookup → 360 → correct → diagnostic
→ audit read) run against staging.

**Explicit non-goals:** no bulk operations, no cross-brand member search, no
case-management system, no marketing/growth surfaces.

---

### Phase 4 — Date9ja capability construction

**Objective:** build the destination capabilities. This is the actual bottleneck and
the largest phase by far.

**Scope** — driven by `CAPABILITY-PARITY.md` and ordered by `PARITY-BUILD-PLAN.md`:
1. **Verification** (ADR 0024) — `domains/verification/` is empty and 5 parity rows
   depend on it. Highest priority.
2. Resolve the 1 NEEDS PRODUCT DECISION row (genotype) and the sensitive-field
   storage decisions still `:pending` in `Profiles::FieldCatalog`.
3. Close the 42 PARTIAL rows — the cheapest parity progress available.
4. Product decisions on the large MISSING clusters: Community, Dating Hub, Aunty
   Phobie/AI, Careers, Feedback, support chat. **Build or explicitly retire** —
   `CAPABILITY-PARITY.md`'s scope rule requires an owner decision, not silence.
5. Realtime (**P2-12**) and entitlements/billing (ADR 0026) — build-or-retire
   decisions.
6. API versioning and deprecation policy for legacy clients. **(P2-10)**

**Dependencies:** Phases 1–3. HQ correction (P1-4) is a hard dependency — imported
data will need staff correction.

**Acceptance criteria**
- Every one of the 95 rows is PARITY, DIFFERENT SEMANTICS with an accepted contract,
  or **explicitly retired by the product owner and recorded in `DECISIONS.md`**.
- `domains/verification/` and `domains/billing/` are either implemented or formally
  descoped.

**Verification:** `FEATURE-PARITY-ACCEPTANCE.md` journeys executed per capability.

**Explicit non-goals:** no data migration execution, no cutover, no production host
mapping for Date9ja.

---

### Phase 5 — Migration readiness

**Objective:** prove the whole migration end to end at production scale.

**Scope**
1. Complete video pass 2 and resolve ADR 0028's open decisions.
2. Full-corpus rehearsal against a production-scale sanitized snapshot — every entity
   class, not per-capability rehearsals.
3. Full reconciliation per `RECONCILIATION.md`, balanced across every entity.
4. Auth transition validated end to end for migrated accounts, including recovery and
   reactivation.
5. Rollback rehearsal — prove reversibility, not only forward progress.
6. `CUTOVER-RUNBOOK.md` dry run with an operator.
7. Production hardening for cutover load: separate job host (**P2-8**), pre-deploy
   migration gate (**P2-7**), load test executed rather than merely present
   (**P3-12**).

**Dependencies:** Phase 4 complete. Migration into missing capabilities is not
possible.

**Acceptance criteria**
- `STATUS.md` reaches **PARITY_ACCEPTED**.
- Reconciliation balances at full scale.
- Rollback demonstrated.
- Capacity headroom evidenced under load test.

**Verification:** operator-executed rehearsal with recorded counts, matching the
evidence standard the program already applies to photo pass 2.

**Explicit non-goals:** no production cutover.

---

### Phase 6 — Migration execution

**Objective:** cut Date9ja over to D8N.

**Scope:** execute `CUTOVER-RUNBOOK.md`; map `DATE9JA_API_HOST`; run the import; run
reconciliation; monitor; retire the legacy backend only after HQ demonstrably covers
every operational dependency in `CAPABILITY-PARITY.md`'s operational register.

**Dependencies:** Phase 5, plus explicit product-owner cutover approval.

**Acceptance criteria:** all users migrated; reconciliation balanced in production;
error rates within threshold; rollback available until the legacy backend is retired.

**Verification:** production reconciliation report; HQ Member 360 spot checks against
migrated accounts.

**Explicit non-goals:** no legacy backend retirement in the same change as cutover.

---

## Appendix A — Commands executed

All read-only or test-scoped. No production or destructive command was run.

```
git log / branch / ls-files / show          repository and secret history inspection
find / grep / sed / awk                     static inspection
bin/rails db:test:prepare                   PASS
bin/rails test                              FAIL (1 of 2003) — see §12
bin/rubocop --format simple                 FAIL (4 autocorrectable offenses)
bin/brakeman --no-pager -q -f plain         PASS (0 warnings)
bundle exec bundle-audit check --update     PASS (0 vulnerabilities)
bin/rails routes                            route inventory
```

## Appendix B — Changes made by this audit

| Area | Change |
|---|---|
| Documentation | **Created** `docs/audits/D8N_BASELINE_AUDIT_2026-09.md` (this file) |
| Production code | **NONE** |
| Configuration | **NONE** |
| Database / schema / migrations | **NONE** |
| Tests | **NONE** |
| Production environment | **NONE** |
| Files deleted, renamed, or consolidated | **NONE** |
