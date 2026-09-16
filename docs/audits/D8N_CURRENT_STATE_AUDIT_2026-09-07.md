# D8N Current-State Audit — 2026-09-07

**Audit date:** 2026-09-07  
**Repository:** `d8n`  
**Branch:** `date9ja-parity`  
**Commit audited:** `7b74920` (`feat(date9ja): Enhance user profile and preference import functionality`)  
**Baseline:** `origin/date9ja-parity`  
**Initial working tree:** clean  
**Audit mode:** evidence gathering only; no product code, schema, configuration, tests, or existing documentation changed

## 1. Executive conclusion

D8N is a substantial Rails API-only modular monolith, not a scaffold. Its strongest implemented areas are identity/session security, brand-scoped profiles, the configurable profile catalogue, discovery eligibility, likes-to-match, match-gated messaging, private media, notifications, trust/safety, and a backend HQ API. The core identity/profile split and most dating-graph tables have explicit brand ownership and strong database constraints.

Date9ja is **not yet an operational D8N brand**. This is deliberate in the current code: the Date9ja contract does not expose discovery, matching, or chat capabilities, and its matching strategy reports that it is not production-ready. Independently, the importer cannot produce a publishable native-equivalent member: it omits first/last name, rejects all observed source country values because they are names rather than ISO-2 codes, does not create the required `ProfileLocation`, has incomplete age and required option coverage, and imports every profile as draft and hidden. Its photo/video work has strong synthetic evidence but no demonstrated production source-to-R2 run.

There is no member or HQ frontend in this repository. Consequently, all user-facing and operator-facing end-to-end claims depend on external clients that were not available to this audit. The OpenAPI contract is mechanically aligned with the Rails routes, but the checked-in Date9ja API compatibility narrative has drifted from both.

The full Rails suite executes 2,099 tests. One pre-existing DateZA welcome-email assertion fails; the critical Date9ja, matching, messaging, OpenAPI, and HQ subset passes 496/496. Zeitwerk, Brakeman, and dependency auditing pass. RuboCop fails on four trailing-whitespace offences in the same DateZA email presenter involved in the baseline test mismatch. A local libvips/HEIF dynamic-library warning is an environment defect.

## 2. Evidence rules and confidence

This audit ranks evidence in this order:

1. Current application code, schema/migrations, routes, and executable tests.
2. Results from executing the repository's quality gates.
3. Current Git state/history.
4. Documentation and checked-in migration evidence.

No Date9ja source database, production object store, deployed host, or external frontend was accessed. Counts reported from migration rehearsals are therefore labelled **checked-in evidence**, not independently reproduced facts.

Classification vocabulary:

- **VERIFIED** — implemented and directly supported by code plus meaningful tests or executable inspection.
- **PARTIAL** — useful implementation exists, but a required path, consumer, operational proof, or correctness condition is absent.
- **SCAFFOLD ONLY** — boundary or placeholder exists without working capability.
- **MISSING** — no material implementation found.
- **LEGACY** — retained compatibility or superseded representation remains in active code/schema.
- **DEAD/UNUSED** — no production caller or effective route was found.
- **UNCLEAR** — repository evidence is insufficient to determine operational use.

## 3. Phase 0 — repository orientation

### Repository map

| Area | Actual state | Evidence |
|---|---|---|
| Application | One Rails 8.1 API-only application | `Gemfile`, `config/application.rb`, `config/routes.rb` |
| Backend | Controllers/models/jobs in `app/`; business workflows in `domains/` | `app/`, `domains/` |
| Frontend(s) | None found: no `package.json`, Next/Vite config, JSX/TSX application, or SPA package | repository file inventory; `app/views/` contains mailer templates only |
| Domain modules | Abuse protection, Admin, Analytics, Brands, Discovery, Geography, Hooks, HQ, Identity, Matching, Media, Migration, Notifications, Profiles, Trust | `domains/` |
| Empty domain boundaries | Billing and standalone Verification | `domains/billing/.keep`, `domains/verification/.keep` |
| Persistence | PostgreSQL; 56 schema tables, 150 foreign keys, 32 check constraints | `db/schema.rb` |
| Migrations | 75 migration files; all reported `up` in the local development database | `db/migrate/`; `bin/rails db:migrate:status` |
| Background work | Solid Queue plus 13 application/domain job classes | `config/queue.yml`, `app/jobs/`, `domains/media/process_profile_video_job.rb` |
| Scheduling | Cleanup, unattached-media purge, rate-counter purge, and notification recovery only | `config/recurring.yml` |
| Tests | 271 test files; full suite has 2,099 test cases | `test/` and executed suite |
| Tasks/scripts | Brand provisioning/demo, geography, load, and Date9ja import tasks | `lib/tasks/*.rake`, `script/` |
| Deployment | Kamal, Puma, Docker, CI, Solid Queue | `config/deploy.yml`, `Dockerfile`, `.github/workflows/` |
| API contract | OpenAPI YAML, runtime JSON endpoint, Swagger UI | `docs/api/openapi.yaml`, `docs/api/README.md`, `config/routes.rb` |
| Documentation | Architecture, ADRs, API, engineering, HQ, founder, migration, audit, and runbook material | `README.md`, `PLAN_OF_ACTION.md`, `AGENT_RULES.md`, `docs/` |

The prescribed `docs/HUMAN_TODO.md` path does not exist. The current file is `docs/FOUNDER-HQ/HUMAN/HUMAN_TODO.md`; references in repository instructions have drifted.

### Git state

- Branch: `date9ja-parity`
- Tracking: `origin/date9ja-parity`
- Initial status: clean and aligned with the tracked branch
- Audit head: `7b74920`
- Relevant recent history: current profile/preference import enhancement, source-census SQL, canonical brand-aware field catalogue, and earlier Date9ja auth/media/video import work
- The only intended post-audit working-tree change is this report.

## 4. Phase 1 — backend architecture and capability inventory

| Capability | Class | Implementation and boundary | API/persistence/tests | Brand/reuse assessment |
|---|---|---|---|---|
| Identity/auth | VERIFIED | Global `User`; identifiers, credentials, password hashes, OTP, sessions, closures/reactivation in `domains/identity/` | Auth controllers under `app/controllers/api/v1/auth/`; `users`, `identity_identifiers`, `credentials`, `sessions`, `otp_challenges`, `auth_attempts`; extensive model/controller/domain tests | Correctly shared. Sessions are resolved and bound to a brand; membership is separate from identity. Rodauth supplies password primitives, not the product boundary. |
| Profiles | VERIFIED | `Profile` is a per-brand dating presence; completion/publication services in `domains/profiles/` | `/api/v1/profile`, public profile, publication and config endpoints; profiles table and composite tenant FKs; model/controller/contract tests | Shared and explicitly brand-aware. |
| Profile preferences | VERIFIED | One per profile; interested-in, age, distance and relationship fields; update service/policy | `/profile/preferences`; `profile_preferences`; matching and controller tests | Shared. Some scalar fields overlap the option catalogue and are transitional. |
| Options/catalogue | VERIFIED | `Profiles::FieldCatalog`, `FieldPolicy`, capability catalogue, option groups/options/selections | Profile config/options endpoints and catalogue/selection tests | Strong reusable boundary. Brand contracts enable/configure canonical fields instead of forking models. |
| Publication/completion | VERIFIED | Completion computes brand requirements; Publication is the only activation path and hides incomplete active profiles | `/profile/publication`; profile status/visibility and tests | Shared and fail-closed. Date9ja inputs are incomplete, so the capability is not migration-ready. |
| Discovery | VERIFIED for enabled brands; PARTIAL platform-wide | Shared visibility, bilateral eligibility, exclusions, allocation, ranking strategies | `/discovery`, `/find`; discovery allocations/exposures; extensive scope/controller/strategy tests | Reusable strategy boundary. HookUs and DateZA are configured; Date9ja is explicitly disabled. |
| Matching eligibility | VERIFIED | `Matching::VisibilityScope`, `EligibilityScope`, `ExclusionsScope`, strategy registry | Exercised by discovery/likes/matching tests | Shared, bilateral, brand-scoped. Exact free-form gender tokens remain a semantic risk. |
| Likes/passes | VERIFIED | Like/pass services validate eligible profiles and block states under lock | `/likes`, `/profile_passes`; likes/passes and controller tests | Shared. `Like.kind = hook` appears legacy because HookUs uses the separate `hooks` table/service. |
| Matches | VERIFIED | Canonical member pair, active state, reverse-like creation | `/matches`; `matches`; service/model/controller tests | Shared and brand-scoped. |
| Conversations/messages | VERIFIED core; PARTIAL parity | Match-gated conversation creation/read, participant authorization, text/replies/image/video attachments, block enforcement | `/conversations`, `/messages`, attachment endpoints; conversation/message/authorization tests | Shared. No realtime, reactions, message edit/delete, client idempotency, or explicit read-marker endpoint. |
| Media/photos | VERIFIED core; PARTIAL operations | Private Active Storage direct uploads, attach/reorder/moderate/purge and processing | Photo/video/upload/admin endpoints; Active Storage plus profile media tables; extensive tests | Shared. Profile-video tenant integrity is weaker at DB level; processing sweepers exist but are not scheduled. |
| Notifications | VERIFIED | Event, fan-out/delivery, preferences, email and device registrations, recovery | Notification/preference/device endpoints; notification tables and tests | Shared with brand presenters/templates. One DateZA expectation currently fails. No realtime push proof was established. |
| Contact verification | VERIFIED | Email/phone verification and change workflows within Identity | Auth verification endpoints, credentials/OTP tables, tests | Shared identity concern. |
| Dating/identity verification | SCAFFOLD ONLY | Empty domain boundary and proposed ADR material | No verification records, review workflow, badge, or public API | Missing operational verification capability. |
| Trust/safety | VERIFIED core | Bidirectional blocks, typed reports/evidence, photo review, suspensions/bans, enforcement | Member and admin endpoints; block/report/enforcement/security tables; tests | Shared and brand-scoped. |
| Moderation | PARTIAL | Report/photo review and suspension/ban/reinstate API exists | `/api/v1/admin/*` plus HQ read surfaces | No operator UI; no verification moderation; broader queues/tools absent. |
| Billing/payments/entitlements | MISSING | Empty billing directory only | No models, tables, controllers, jobs, or tests | Planned shared boundary, not implemented. |
| Security/audit history | VERIFIED core | Append-only `SecurityEvent`, auth/enforcement/MFA/operator and sensitive-read events | HQ security/member endpoints; tests | Shared and brand-aware. Not a general-purpose audit explorer. |
| Analytics/insights | PARTIAL | Allowlisted/idempotent `AnalyticsEvent`; HQ operational snapshots/funnels/trends | Analytics event table and HQ endpoints/tests | Sparse product instrumentation; revenue and some latency/liquidity measures unavailable. |
| Brand provisioning/config | VERIFIED | Host-only resolver, registry, contracts, capability catalogue, provisioning tasks | Brands/domains/memberships plus config endpoints and tests | Correct shared ownership. No scattered backend fork was found. |
| HQ/admin | VERIFIED API; PARTIAL product | Session auth, encrypted TOTP MFA, immutable RBAC capability map, Member 360, security, analytics, command centre, trust/safety, operators | `/api/v1/hq/*`; admin tables/security events; strong request/domain tests | Backend-only; important member correction and operational surfaces are missing. |
| Background jobs | VERIFIED core; PARTIAL scheduling | Solid Queue jobs for media, notifications, purge, abuse and smoke | Job tests; recurring config | Photo/video processing sweepers are implemented/tested but no recurring/invocation path was found. |
| Date9ja migration | PARTIAL | Source census, adapters, identity/profile/preference/auth/media import and reconciliation primitives | `domains/migration/date9ja/`, `lib/tasks/date9ja_import.rake`, `test/domains/date9ja/` | Appropriately adapter-owned, but not a complete graph import or production cutover system. |
| Live/realtime | MISSING | No product Action Cable/channel layer | No channel/client/realtime tests | Future shared capability only. |

### Implemented but materially undocumented or under-emphasised

- Bilateral distance enforcement and the special nil-distance behaviour are more precise in `Matching::EligibilityScope` than in high-level product documentation.
- Direct public-profile visibility is intentionally less restrictive than discovery compatibility.
- A substantial HQ backend exists even though no operator frontend exists here.
- Database-level composite tenant constraints cover most of the dating graph and are a significant architecture feature.
- Processing sweeper classes exist without a production schedule; this operational distinction is not prominent in system diagrams.

## 5. Phase 2 — data model and database audit

### Principal relationships

```text
User (platform identity)
  └─ BrandMembership (user joins one Brand)
       └─ Profile (brand-specific dating presence)
            ├─ ProfilePreference
            ├─ ProfileLocation → Place
            ├─ ProfilePhoto / ProfileVideo → private Active Storage
            ├─ ProfileOptionSelection → ProfileOption → ProfileOptionGroup
            ├─ ProfilePromptAnswer → ProfilePrompt
            ├─ Like / ProfilePass / Hook / ProfileBlock / Report
            └─ Match
                 └─ Conversation → Participants → Messages → Attachments

Brand
  ├─ BrandDomain
  ├─ BrandMembership/Profile graph
  ├─ AdminAssignment → AdminRole/AdminUser
  ├─ Notification/Event/Delivery graph
  ├─ AccountEnforcement / SecurityEvent / AnalyticsEvent
  └─ Discovery allocations/exposures
```

### Schema findings

**Strong invariants verified**

- `users` are global; `brand_memberships` and `profiles` carry the brand boundary.
- The profile-to-membership relationship and most dependent records use composite unique keys/foreign keys involving `brand_id`, not controller convention alone.
- Likes, matches, conversations/participants/messages/replies, blocks/reports, notifications, discovery allocations, preferences, options, photos, and locations have tenant-aware integrity constraints.
- Canonical unordered pair constraints/indexes prevent duplicate matches and symmetric duplicate blocks.
- Operational lifecycle fields (`deleted_at`, status/visibility/enforcement state) are used broadly; erasure is represented separately by closure/anonymisation workflows.
- Important enum/status checks and uniqueness constraints are present in the schema.

**Duplicated or transitional concepts**

- `profiles.languages_spoken` is a legacy free-text representation alongside canonical structured `languages`.
- `profile_preferences.relationship_intent` coexists with the controlled `relationship_intent` option group. Active DateZA/Date9ja contracts use the option group; the scalar is disabled there.
- `profiles.city`/`country_code` coexist with `profile_locations`/`places`. These represent display and precise/chosen location needs, but migration currently populates only the scalar city.
- `likes.kind = hook` remains although production HookUs behaviour uses `hooks`.

**Integrity and orphan risks**

- `profile_videos` has simple FKs to profile/user/brand and application validations, but lacks the composite owner/tenant FK pattern used by profile photos. Validation-bypassing writes can create a cross-brand or wrong-owner row.
- `account_closures` and `account_enforcements` rely more heavily on service/model validation than composite database ownership constraints. In particular, closure tenant consistency is not DB-enforced.
- `analytics_events` uses simple optional FKs plus application brand-scope validation; cross-entity consistency is not DB-enforced.
- `brands.owner_type/owner_id`, Active Storage attachment ownership, and legacy-reference destinations are intentionally polymorphic and cannot use ordinary FKs; their services remain the integrity boundary.
- Processing state can stall because media sweepers are not scheduled, even though purge/recovery jobs are.

**Nullability/default observations**

- `users.first_name` and `last_name` are nullable by schema because global identity can predate a completed brand profile. Date9ja makes them completion requirements at the brand policy layer.
- Discovery-critical profile preference fields are nullable so onboarding can be incomplete; eligibility correctly excludes incomplete participants.
- This audit found no evidence that nullable onboarding fields themselves leak incomplete profiles; publication and visibility scopes fail closed.

**Migration hazards**

- Current imports are deliberately non-overwriting, so an incorrect early mapping can persist unless remediation is explicit.
- Profile publication is not a column-copy operation: it depends on current brand contract requirements and collection records.
- Name, country, location, age-range, and required-option gaps must be reconciled before bulk activation.
- Media metadata import and byte transfer are separate phases; a row count alone does not prove retrievable media.

## 6. Phase 3 — Date9ja migration readiness

### End-to-end trace

| Step | State | Evidence | Blocking detail |
|---|---|---|---|
| Source census/extraction | PARTIAL | `Date9jaCensusSql`, selected-column and deny-list contracts, checked-in census/status docs | Rehearsal evidence exists, but no source DB was available to rerun. |
| Snapshot contract | VERIFIED design; PARTIAL operation | Explicit selected columns and sensitive deny-list in `domains/migration/date9ja/` | No independently verified production snapshot in this audit. |
| Mapping | PARTIAL | Field/preference mapping classes and exhaustive unit tests | Several source values/fields are unmapped; country names are rejected. |
| Identity import | VERIFIED core | User/identifier/credential/membership/legacy-reference importer and reconciliation tests | First/last name are not sourced; collision handling fails closed. |
| Profile import | PARTIAL | Display name, birthdate, gender, city, bio and ideal-partner text | Every profile is draft/hidden; country and required location are absent. |
| Preference import | PARTIAL | Interested-in, complete age pair, limited options | Most observed age pairs are incomplete; several required option codes are absent/unmapped. |
| Photos | PARTIAL | Metadata/preflight/transfer code and L1/L2 synthetic evidence | Production signed source transport and real R2 L3 evidence are absent. |
| Video | PARTIAL | Phase code and synthetic L2 tests/evidence | No real production transfer evidence. |
| Completion | VERIFIED engine; RED imported result | `Profiles::Completion` and Date9ja contract | Imported profiles do not satisfy current requirements. |
| Publication | VERIFIED engine; RED migration policy | `Profiles::Publication`; importer writes draft/hidden | Legacy `profile_hidden` and bulk publication policy are unresolved. |
| Discovery eligibility | VERIFIED engine; RED brand | Matching scopes plus Date9ja brand contract | Date9ja strategy is not production-ready and the capability is disabled. |
| Matching/likes | VERIFIED shared engine; RED brand | Like/match services and tests | Disabled for Date9ja; migrated user tests manually publish fixtures to isolate mapping. |
| Conversation/chat | VERIFIED shared core; RED brand | Match-gated messaging services/tests | Disabled for Date9ja and external client parity is incomplete. |

### Date9ja field-by-field result

| Field/capability | Current handling | Result |
|---|---|---|
| Gender | Source enum `0 → man`, `1 → woman` | VERIFIED for observed binary source values. Exact string semantics remain important. |
| `looking_for` / `interested_in` | `0 → [man]`, `1 → [woman]`; same-sex intent is preserved | VERIFIED for binary single-choice values; no observed open/multiple source mapping. |
| Preferred age | Copied only when both bounds form a valid complete range; partial/invalid becomes entirely nil | PARTIAL. Checked-in census evidence says most imported members lack a complete pair. |
| Preferred distance | No imported source value; current Date9ja policy makes it optional | DIFFERENT/NOT IMPORTED, not a completion blocker. |
| Relationship intention | Maps marriage, serious/long-term, and friendship; other/null codes remain absent | PARTIAL; required option selection is a blocker for affected members. |
| Commitment timeline/meeting pace | No Date9ja import mapping; meeting pace was relaxed to optional | MISSING migration; not currently a completion requirement. |
| Children / wants children | Child count maps to yes/no; wants-children maps yes/no, but open/null remains absent | PARTIAL; both are current required option groups. |
| Marital status | No target import mapping found | MISSING. |
| Education | Catalogue exists; source not selected/mapped by current importer | MISSING migration. |
| Smoking / drinking | Enabled fields exist; importer does not select/map source values | MISSING migration. |
| Fitness | Enabled catalogue field exists; no import mapping | MISSING migration. |
| Height / body type | Supported by shared profile catalogue; no current source import | MISSING migration. |
| Family involvement | No active Date9ja import mapping | MISSING. |
| Relocation | No active Date9ja import mapping | MISSING. |
| Languages | Legacy/free-text and structured target concepts exist; no Date9ja import mapping | MISSING and conceptually transitional. |
| Countries | Source profile country is selected, but mapper accepts ISO-2 only. Checked-in census says all 288 values are name-like and none ISO-2. Preferred countries are not imported. | RED: `country_code` becomes nil for the observed source population. |
| Interests | Shared catalogue capability exists; no Date9ja import | MISSING migration. |
| Relationship values | No current import | MISSING. |
| Dealbreakers | No current import | MISSING. |
| Profile completion | Shared computation works against current contract | RED for migrated profiles because required data/collections are absent. |
| `profile_hidden` | Selected in source context but ignored; importer always creates hidden draft | OPEN POLICY DECISION. |
| Photos | Metadata and synthetic transfer path implemented | PARTIAL; no L3 production evidence. |
| First/last name | Source `full_name` is not selected; `User.create!` receives neither | RED: both are Date9ja completion requirements. |
| Country → canonical code | Only already-canonical ISO-2 accepted | RED: deterministic source-name mapping is absent. |
| Location | Scalar city may be copied, but no `ProfileLocation` importer was found | RED: Date9ja completion requires a location collection item. |

### What prevents native-equivalent behaviour

1. Imported records cannot pass the current Date9ja completion contract.
2. Import always creates draft/hidden profiles and does not translate legacy publication/hidden semantics.
3. Date9ja discovery, matching, and chat capabilities are disabled; its strategy is deliberately non-production.
4. Media is not proven through a real source-to-production-object-store run.
5. No complete graph importer exists for legacy likes, matches, conversations/messages, blocks/reports, notification state, trust/verification, premium/entitlements, or historical analytics.
6. There is no in-repository Date9ja client to validate onboarding, remediation, discovery, like, match, and chat against this API.
7. There is no single cutover orchestrator proving ordered import, delta/freeze handling, full reconciliation, rollback, and activation.

Checked-in operator evidence reports 288 source identities, 280 imported, eight intentionally skipped, and zero failed in a rehearsal. That evidence is useful but was not reproduced here.

## 7. Phase 4 — discovery and matching correctness

### Eligibility path

```text
brand-resolved authenticated session
  → brand capability + production-ready matching strategy
  → Matching::VisibilityScope
       same brand; active + visible + kept profile
       active user + active membership
       adult birthdate and usable preference
       exclude either-direction blocks
  → Matching::EligibilityScope
       bilateral gender interest
       bilateral age ranges
       bilateral distance limits
  → Matching::ExclusionsScope
       outgoing likes, passes, active matches, surface-specific exclusions
  → brand strategy ranking/allocation/cursor
```

Important implementation paths: `domains/matching/visibility_scope.rb`, `eligibility_scope.rb`, `exclusions_scope.rb`, `like_profile.rb`, strategy contracts under `domains/d8n/platform/brands/`, and discovery controllers/services under `app/controllers/api/v1/` and `domains/discovery/`.

### Rule findings

- **Who is visible:** only same-brand, kept, active and visible profiles backed by active users and active memberships; self and bidirectional blocks are excluded.
- **Gender compatibility:** candidate gender must be in viewer `interested_in`, and viewer gender must be in candidate `interested_in`.
- **Age compatibility:** each person's age must satisfy the other's complete range.
- **Distance compatibility:** limits are mutual. If a viewer sets a distance without a location, no candidates are eligible. A viewer with no limit only sees candidates who also have no limit unless the branch has coordinates to prove the candidate's limit.
- **Publication:** incomplete profiles cannot remain actively published; discovery also independently requires active/visible state.
- **Suspended/banned/closed:** inactive user/membership/profile state removes participation.
- **Existing graph state:** outgoing likes, passes, and active matches are excluded from the viewer's feed.
- **Brand boundary:** enforced by service scopes and, for most records, composite DB constraints.
- **Daily limits:** DateZA allocation and HookUs product policies implement surface limits; Date9ja has no enabled surface.
- **Ranking:** HookUs uses a scored cursor strategy; DateZA uses curated stable daily selection; Date9ja returns zero scores and `production_ready? == false`.

### Pair reasoning

| Pair | Eligible when |
|---|---|
| man → woman | Man includes `woman`, woman includes `man`, and bilateral age/distance/status rules pass. |
| woman → man | Same reciprocal rule; no directional shortcut. |
| man → man | Both include `man` and all other bilateral rules pass. |
| woman → woman | Both include `woman` and all other bilateral rules pass. |
| multi/open | Arrays structurally support multiple exact values, but there is no controlled global gender vocabulary or wildcard semantic. Synonyms/unrecognised values silently fail equality. |

Full dating eligibility is symmetric at one state snapshot. Intentional asymmetries remain:

- A direct public-profile link can be visible without mutual dating compatibility.
- A's outgoing like/pass hides B from A, but does not hide A from B before B acts.
- Per-viewer daily allocation, quota, rank, and cursor state produce different feeds.
- Time/location/state changes between requests can change the result.

The Date9ja preference-import test manually publishes prepared profiles to isolate mapping/match logic. It does **not** prove that an actually imported member can pass completion/publication or call the Date9ja discovery API.

## 8. Phase 5 — HQ/admin audit

There is no HQ frontend here. Every implemented HQ feature is therefore **working API but missing UI**, not an end-to-end operator product.

| HQ function | Backend | Frontend | Finding/evidence |
|---|---|---|---|
| Authentication | VERIFIED | MISSING | Uses normal brand-bound sessions plus admin assignment. |
| MFA | VERIFIED core | MISSING | Encrypted TOTP credential, setup/confirm/disable, throttling and tests. Step-up timestamp has no freshness window and can last the session lifetime. |
| RBAC | VERIFIED | MISSING | Immutable role/capability map and exactly one active brand assignment context. |
| Member search | VERIFIED | MISSING | Member directory API and request/domain tests. |
| Member 360 | VERIFIED read-only | MISSING | Six-section aggregate, security and discovery diagnostic endpoints. |
| Gender correction | MISSING | MISSING | No HQ mutation found. |
| Looking-for/preference correction | MISSING | MISSING | No HQ mutation found. |
| Visibility/publication correction | MISSING | MISSING | No HQ mutation found. |
| Reports/photo moderation | VERIFIED API | MISSING | Separate admin report/photo queues and action endpoints. |
| Suspension/ban/reinstate | VERIFIED API | MISSING | Brand-scoped enforcement services and audit events. |
| Blocks/reports inspection | VERIFIED read surfaces | MISSING | Member/trust-safety summaries. |
| Enforcement history | VERIFIED | MISSING | HQ trust/safety and member views. |
| Security history | VERIFIED | MISSING | Auth/security event history. |
| Audit history | PARTIAL | MISSING | Sensitive reads and mutations are recorded, but no general audit browser/export. |
| Errors/APM | MISSING | MISSING | Command centre is DB-derived health, not exception/APM tooling. |
| Brand comparison | VERIFIED API | MISSING | Cross-brand comparison constrained by operator assignments. |
| Analytics/funnels/trends | PARTIAL API | MISSING | Operational metrics work; sparse event coverage, revenue and some time/liquidity metrics absent. |
| Service/provider management | MISSING | MISSING | No implementation found. |
| Marketing/growth/spend | MISSING | MISSING | No implementation found. |
| Targets | MISSING | MISSING | No implementation found. |

RBAC semantic concern: `Api::V1::Hq::CommandCentreController` requires `ANALYTICS_READ`, including health. Engineering has system-read semantics but not necessarily analytics access, while analytics roles gain system-health access. This may be intentional, but should be reviewed as a role/capability mismatch rather than assumed correct.

## 9. Phase 6 — frontend and brand architecture

No frontend application is present. The only rendered templates are transactional emails. Therefore onboarding, profile editing, discovery, likes, chat, settings, blocking/reporting, notifications, theming, auth persistence, and HQ cannot be verified end to end here.

Backend brand resolution is reusable and coherent:

- Hostname resolves through `BrandDomain`/`Brands::Resolver`; callers do not choose arbitrary tenant IDs.
- Sessions are brand-bound.
- Brand contracts under `domains/d8n/platform/brands/` define capability/policy/catalogue behaviour.
- Profile fields/options are enabled through canonical shared catalogues.
- Matching differences live behind small strategies rather than brand-named controller forks.
- Notification content has brand-specific presenters/templates, which is genuine presentation ownership.
- Date9ja-specific extraction/mapping belongs in a migration adapter, not the shared runtime domain.

Because no two frontend implementations are present, recommending a shared component system now would be speculative. A shared API client/schema-generated types and session/error conventions become justified when at least two actual clients are in scope; no code in this repository can yet prove duplication.

## 10. Phase 7 — API contract audit

- `config/routes.rb` exposes identity, self/profile/config/options/publication/location/media, discovery/find/public profiles, interactions, trust/safety, matches/messaging, notifications, admin moderation, and HQ.
- `docs/api/openapi.yaml` is validated against the Rails route set by `test/contracts/openapi_contract_test.rb`; the focused suite passed.
- Runtime JSON and Swagger endpoints are routed.
- No in-repository consumer exists, so “currently consumed”, unused, and frontend-only expectations cannot be established from primary code.
- Capability gates correctly protect interpersonal Date9ja routes; calling disabled matching surfaces fails closed.
- Capability-gate declarations are not uniformly applied to every profiles/trust/notification controller. Some services enforce policy internally, but the platform lacks one obvious route-level contract for all optional capabilities.
- The Date9ja API compatibility document is stale: it says profile video is absent although video routes exist, and describes message edit/delete/reaction/read-marker capabilities not present in current routes.
- The OpenAPI contract is the trustworthy current backend interface; migration compatibility prose and external legacy clients require revalidation against it.

Likely Date9ja breakpoints are authentication/session envelope differences, profile field shape/controlled option codes, completion/publication rules, missing location creation, disabled discovery/chat capabilities, and legacy messaging/media endpoint differences.

## 11. Phase 8 — test and quality audit

### Executed commands

| Command | Result |
|---|---|
| `RAILS_ENV=test /usr/local/bin/rbenv exec ruby bin/rails test` | **FAIL:** 2,099 runs, 24,775 assertions, 1 failure, 0 errors, 0 skips |
| Focused OpenAPI + Date9ja + matching + discovery + likes + conversations/messages + HQ suite | **PASS:** 496 runs, 4,383 assertions, 0 failures/errors/skips |
| `RAILS_ENV=test /usr/local/bin/rbenv exec ruby bin/rails zeitwerk:check` | PASS: “All is good!” |
| `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache /usr/local/bin/rbenv exec ruby bin/rubocop --no-server` | **FAIL:** 839 files inspected, four correctable trailing-whitespace offences |
| `/usr/local/bin/rbenv exec ruby bin/brakeman --no-pager` | PASS: 0 errors, 0 security warnings; 79 checks |
| `/usr/local/bin/rbenv exec ruby -S bundle exec bundle-audit check` | PASS: no vulnerable gems reported |
| `/usr/local/bin/rbenv exec ruby bin/rails db:migrate:status` | PASS: all 75 migrations `up` in local development DB |
| `git diff --check` before report | PASS |

### Failure classification

| Class | Evidence | Likely cause | Release/migration impact |
|---|---|---|---|
| A — current regression | No newly introduced branch-only product-test regression was isolated. RuboCop currently fails on four whitespace lines. | DateZA email presenter formatting. | CI/release hygiene blocker; not Date9ja-specific. |
| B — pre-existing baseline | `Notifications::DeliverProductNotificationJobTest#test_welcome_email_uses_the_DateZA_template_and_a_brand_sender_exactly_once` expects no `href`, but presenter now emits a profile CTA. The prior 2026-09-05 baseline audit records the same failure. | Product expectation and test diverged in earlier commits. | Full CI is red. Does not directly invalidate Date9ja migration logic. |
| C — environment/infrastructure | Sandboxed run could not access local PostgreSQL; approved local execution resolved it. Configured `/private/tmp/d8n_bundle` lacked gems. libvips cannot load `vips-heif.dylib` because the expected x265 ABI is missing. | Local sandbox/bundle/native-library state. | HEIF/native media support must be repaired or explicitly declared unsupported before production media verification. |
| D — unknown/unavailable | No external frontend suite, Date9ja source DB, production R2 transfer, production host, or cutover rehearsal was available. | Evidence outside this repository/session. | Blocks an end-to-end launch claim. |

### Coverage strengths

- Brand isolation, profile completion/publication, matching eligibility, likes-to-match, chat authorization, trust/safety, HQ RBAC/MFA/audit, OpenAPI routes, and Date9ja adapters have meaningful tests.
- Critical focused tests are green independently of the DateZA notification mismatch.

### Material coverage gaps

- One test does not prove the complete Date9ja path from imported row through completion/publication to API discovery; publication is manually forced in mapping tests.
- There is no real source snapshot/object-store L3 test, delta cutover test, rollback rehearsal, or full migration-graph reconciliation test.
- No browser/client tests exist for member or HQ workflows.
- Realtime, billing/entitlements, dating verification, and their authorization cannot be tested because they are absent.
- Unsheduled media processing recovery is tested at class level, not proven operationally.

## 12. Phase 9 — security and multi-tenancy

### Verified controls

- Host-derived brand resolution; no client-selected tenant context.
- Brand-bound sessions and active membership checks.
- Explicit service/controller scoping and extensive composite tenant FKs across core dating data.
- Bilateral block enforcement and match/participant authorization for messaging.
- Private Active Storage media with attach ownership checks and moderation states.
- Explicit strong parameters; no `permit!` or obvious dynamic mass-assignment bypass found.
- DB-backed rate limiting on high-risk product writes plus dedicated identity/MFA throttles.
- Sensitive parameter filtering includes credentials, tokens, OTPs, names, coordinates, and message bodies.
- HQ requires assignment, RBAC capability, and TOTP; sensitive reads and mutations emit security/audit events.
- Static Brakeman and dependency audit are clean.
- Date9ja selected-column allowlist and sensitive deny-list keep religion, tribe, ethnicity, genotype and related preference data out of the current import.

### Risks requiring action/review

| Risk | Severity/readiness | Evidence |
|---|---|---|
| Profile-video owner/tenant consistency is not a composite DB invariant | P0 before production media import | `db/schema.rb`, `app/models/profile_video.rb`; compare profile photo constraints |
| HQ MFA step-up has no freshness interval | P0 before privileged production operation | session/admin MFA authorization code and tests |
| Closure/enforcement/analytics entity ownership is partly application-only | P1 hardening | relevant schema and models |
| Exact free-form gender tokens can silently break compatibility | P1 correctness/data-governance | `Matching::EligibilityScope`, profile/preferences validation/catalogue |
| Optional platform capability gating is inconsistent at controller declarations | P1 authorization/contract consistency | controller inventory and capability concerns |
| Media processing sweepers are not scheduled | P1 availability/data processing | job classes vs `config/recurring.yml` |
| No HQ UI means operators may be driven to direct API/database workarounds | P1 operational safety | repository frontend absence and missing correction endpoints |
| Generic rate limiter fails open on storage errors | P2 availability/security trade-off | `domains/abuse_protection/rate_limiter.rb` |
| Documentation contains images with unclear provenance/privacy status | P2 repository hygiene | `docs/user-images/` inventory; no assertion that the files contain PII was made |

No offensive exploitation was performed. Static/controller-flow inspection found no obvious cross-brand IDOR in the audited critical paths.

## 13. Phase 10 — documentation audit

| Document/group | Classification | Finding |
|---|---|---|
| `README.md` | PARTIALLY CURRENT | Useful product/company blueprint; describes target platform as well as shipped code. |
| `PLAN_OF_ACTION.md` | PARTIALLY CURRENT / STALE STATUS | Architecture direction remains sound; implementation-status portions lag current messaging, MFA, and media work. |
| `AGENT_RULES.md` | CURRENT with path drift | Engineering/security rules align with code; `docs/HUMAN_TODO.md` reference is stale. |
| Accepted ADRs 0001–0030 | MOSTLY CURRENT | Core modular-monolith, identity/profile, tenancy, media, matching and HQ decisions align. Proposed verification/trust/entitlement ADRs describe unimplemented work and must not be read as delivery. |
| `docs/architecture/profile-field-matrix.md` | CURRENT HISTORICAL | Correctly declares itself historical and points to `FieldCatalog` as runtime authority. |
| `docs/architecture/agent-workflow.md` | OBSOLETE/SUPERSEDED | Explicitly superseded by `docs/engineering/AGENT-WORKFLOW.md`. |
| `docs/engineering/*` | CURRENT | Good authority policy, workflow and quality-gate guidance. |
| `docs/api/openapi.yaml` | CURRENT | Mechanically route-validated and the canonical backend contract. |
| `docs/api/README.md` | CURRENT/PARTIAL | Accurate contract authority; cannot prove external client adoption. |
| `docs/SCALING_GUIDE.md` | CURRENT AS GUIDANCE | Architectural constraints, not production-scale evidence. |
| `docs/ARCHITECTURE_DIAGRAMS.md` | PARTIALLY CURRENT | Useful target/system shape; diagrams can imply frontend/live capabilities that are not in this repository. |
| `docs/FOUNDER-HQ/HUMAN/HUMAN_TODO.md` | CURRENT DECISION LOG / PATH DRIFT | Actual location differs from prescribed path. |
| Date9ja `MASTER-PLAN.md` | CURRENT PLAN | Canonical intended program, not proof of delivery. |
| Date9ja `CAPABILITY-PARITY.md` | PARTIALLY CURRENT | Best capability inventory, but status rows lag some recent video work. |
| Date9ja `STATUS.md` | CONTRADICTORY / STALE IN PARTS | Contains old claims that gender remains `0/1` and that media phases are not built alongside later sections documenting their implementation. |
| Date9ja `PROFILE-VALUE-MAPPING.md` | CONTRADICTORY IN PART | Older section claims incompatible gender output; current mapper/tests use canonical strings. |
| Date9ja `API-COMPATIBILITY.md` | STALE | Video and messaging endpoint claims contradict current routes. |
| Date9ja `RECONCILIATION.md` | CURRENT AS CHECKED-IN EVIDENCE | Useful run evidence, but not independently reproduced here. |
| Date9ja audit/status/matrix/build-plan cluster | DUPLICATE/PARTLY STALE | Same facts are repeated with different timestamps and conclusions. |
| Previous `D8N_CURRENT_STATE_AUDIT_2026-09-05.md` | HISTORICAL/SUPERSEDED | Valuable baseline at `931bb04`, not current-head truth. |
| DateZA/HQ/MVP/HOLISTIC plans | PLAN/HISTORICAL | Product intent, not evidence of a frontend or shipped end-to-end system. |

### Recommended future document authorities (no cleanup performed)

- Keep `docs/api/openapi.yaml` canonical for runtime API.
- Keep architecture/accepted ADRs canonical for durable platform rules.
- Keep `CAPABILITY-PARITY.md` as the single Date9ja capability inventory.
- Reduce `STATUS.md` to current execution truth and links, removing repeated historical narratives.
- Keep `DECISIONS.md` for open/closed product decisions and `RECONCILIATION.md` for immutable run evidence.
- Archive, do not silently rewrite, historical audits/handoffs/completed status narratives after the current program is reconciled.

## 14. Phase 11 — technical debt, dead code, and abandoned paths

| Finding | Classification | Consequence |
|---|---|---|
| `Like.kind = hook` while HookUs uses `Hook` | LEGACY/LIKELY UNUSED | Two representations invite incorrect queries and migration assumptions. |
| `profiles.languages_spoken` plus structured `languages` | LEGACY | Ambiguous source of truth. |
| Scalar relationship intent plus option selection | LEGACY/TRANSITIONAL | Import/API clients can write semantically different representations. |
| Billing and Verification `.keep` domains | SCAFFOLD ONLY | Documentation/ADRs may be mistaken for implementation. |
| Media processing sweepers without schedule/caller | PARTIAL/OPERATIONALLY UNUSED | Processing can stall without manual/job-specific intervention. |
| Date9ja status/API/value-mapping obsolete sections | OBSOLETE DOCUMENTATION | Agents/operators can regress corrected mappings or plan against nonexistent endpoints. |
| Legacy-reference polymorphic bridge | ACTIVE COMPATIBILITY SHIM | Necessary for reconciliation now; should have an explicit retirement condition after cutover. |
| Multiple Date9ja phase plans/audits/handoffs | DUPLICATE | Current truth is costly to re-establish and contradictions accumulate. |
| No production caller found for a separate message read/edit/delete/reaction flow | MISSING, not dead | Legacy-client parity remains incomplete. |

No active service was labelled dead merely because repository-wide static call search found only tests; Rails jobs, serializers, autoloading, and task entry points can be indirect. The media sweeper scheduling conclusion is stronger because recurring configuration was inspected directly.

## 15. Phase 12 — end-to-end readiness matrix

Legend: **GREEN** operational in repository scope; **YELLOW** partial; **RED** missing/blocking; **GREY** not started/not applicable.

| Capability | Backend | Frontend | Tests | Multi-brand | Date9ja-ready | Evidence | Blocking issue |
|---|---|---|---|---|---|---|---|
| Identity | GREEN | RED | GREEN | GREEN | YELLOW | Identity models/services/controllers/tests | Names and external client/cutover gaps |
| Profiles | GREEN | RED | GREEN | GREEN | RED | Profile/catalogue/completion code | Imported required data absent |
| Preferences | GREEN | RED | GREEN | GREEN | YELLOW | Preferences + importer tests | Age/options incomplete |
| Options/catalogue | GREEN | RED | GREEN | GREEN | YELLOW | Field/option catalogues | Many source mappings absent |
| Publication | GREEN | RED | GREEN | GREEN | RED | Completion/publication tests | All imports draft/hidden; policy unresolved |
| Discovery | GREEN | RED | GREEN | GREEN | RED | Scopes/strategies/controllers | Date9ja disabled/non-production |
| Matching | GREEN | RED | GREEN | GREEN | RED | Eligibility/strategy tests | Date9ja disabled |
| Likes | GREEN | RED | GREEN | GREEN | RED | LikeProfile/controller tests | Date9ja disabled; no graph import |
| Matches | GREEN | RED | GREEN | GREEN | RED | Match models/services/tests | Date9ja disabled; no graph import |
| Chat | YELLOW | RED | GREEN | GREEN | RED | Conversation/message tests | Date9ja disabled; parity/realtime missing |
| Media | YELLOW | RED | GREEN | GREEN | YELLOW | Media services/jobs/import tests | No L3 production proof; DB/scheduler gaps |
| Notifications | YELLOW | RED | YELLOW | GREEN | YELLOW | Notification pipeline/tests | Baseline failure; external delivery/client proof |
| Trust/safety | GREEN | RED | GREEN | GREEN | YELLOW | Blocks/reports/enforcement | Historical migration/operator UI absent |
| Verification | RED | RED | GREY | GREY | RED | Empty verification domain | Dating verification absent |
| Moderation | YELLOW | RED | GREEN | GREEN | YELLOW | Admin APIs/HQ reads | No UI; limited queues/domains |
| HQ | YELLOW | RED | GREEN | GREEN | YELLOW | HQ controllers/services/tests | No UI/corrections; MFA freshness |
| Audit | YELLOW | RED | GREEN | GREEN | YELLOW | Security events/HQ reads | No general browser/export; consistency gaps |
| Analytics | YELLOW | RED | YELLOW | GREEN | YELLOW | Analytics events/HQ metrics | Sparse instrumentation and missing commercial metrics |
| Brand configuration | GREEN | RED | GREEN | GREEN | YELLOW | Resolver/registry/contracts | Date9ja operational capabilities deliberately off |
| Billing/entitlements | RED | RED | GREY | GREY | RED | Empty billing domain | Entire capability absent |
| Migration | YELLOW | GREY | GREEN synthetic | DATE9JA-SPECIFIC ADAPTER | RED | Import/reconciliation code/tests | Publishability, graph, L3, cutover |
| Live/realtime | RED | RED | GREY | GREY | RED | No implementation | Needed for full modern chat experience |

## 16. Phase 13 — critical path to “Date9ja operates completely on D8N”

### P0 — blocks migration, correctness, or production security

#### P0.1 — Make the Date9ja imported profile contract satisfiable

- **Problem:** the current import cannot create complete/publishable members.
- **Evidence:** missing first/last name; all observed country values rejected; no `ProfileLocation`; incomplete age and required relationship/children options; importer always draft/hidden.
- **Why it blocks:** publication correctly fails closed, so the matching graph cannot legally admit these members.
- **Architectural owner:** Date9ja migration adapter for source interpretation; shared Profiles/Geography domains remain canonical validators and publication authority.
- **Dependencies:** human decisions D-4 (names), D-8 (publication/hidden semantics), D-12 (age remediation), and a closed mapping for required option values.
- **Backend work:** deterministic source mapping/remediation, location creation, completion reconciliation, idempotent reruns, and reason-coded exceptions. Do not weaken shared completion rules to fit legacy data.
- **Frontend work:** remediation/onboarding flow for data that cannot be safely inferred.
- **Tests required:** source-value contract tests, nil/unknown cases, rerun/no-overwrite tests, completion/publication integration, tenant isolation, and reconciliation totals.
- **Definition of Done:** every imported member is either (a) complete and intentionally publishable, (b) intentionally hidden/draft, or (c) quarantined with one explicit remediation reason; counts reconcile to source and no inferred sensitive value crosses policy.

#### P0.2 — Enable Date9ja dating interactions through a production strategy

- **Problem:** Date9ja has no discovery surfaces and omits discovery/match/chat capabilities; strategy is explicitly non-production.
- **Evidence:** Date9ja brand contract and matching strategy; capability-gated controller tests.
- **Why it blocks:** even a manually completed/published member cannot use the Date9ja API for the core dating loop.
- **Architectural owner:** shared Matching/Discovery/Interaction domains with a small Date9ja contract/strategy policy.
- **Dependencies:** P0.1, agreed Date9ja product rules/limits/order, frontend API contract.
- **Backend work:** configure production-ready surfaces, limits/ranking and capability flags using existing shared scopes; retain bilateral eligibility and brand boundaries.
- **Frontend work:** discovery, profile, like/pass, match and chat integration against canonical API/error codes.
- **Tests required:** all four gender pair cases, multiple interests, bilateral age/distance, lifecycle/blocks, existing graph exclusions, daily allocation, likes-to-match, chat authorization, and end-to-end Date9ja contract tests.
- **Definition of Done:** a native and a migrated Date9ja member can mutually discover, like, match, create/read a conversation, and message under the same tested shared rules without cross-brand visibility.

#### P0.3 — Prove production migration/cutover, not only row adapters

- **Problem:** no complete graph/cutover proof exists; media evidence is synthetic and many legacy capabilities are not imported.
- **Evidence:** task/importer inventory, capability parity matrix, no live source/R2 result in this audit.
- **Why it blocks:** identity/profile rows alone do not preserve an operational dating service, and unproven media/cutover risks member data loss or a split brain.
- **Architectural owner:** Migration domain and operator runbooks; each shared domain owns its import invariant.
- **Dependencies:** explicit parity/retirement decisions for likes/messages/trust/premium/history, production transport credentials handled outside Git, freeze/delta plan.
- **Backend work:** ordered manifest/orchestrator, missing graph adapters selected by parity decisions, signed media transport, checkpoints, full reconciliation, rollback and activation gate.
- **Frontend work:** forced recovery/remediation states, compatibility/cutover release, observability for user-visible failures.
- **Tests required:** representative sanitized snapshot, idempotent restart, collision/quarantine, delta/freeze, media checksum/readback, referential/tenant reconciliation, rollback rehearsal, and smoke journey.
- **Definition of Done:** a signed run report accounts for every in-scope source record/object, production media is readable, deltas are closed, rollback is rehearsed, and launch smoke tests pass on the production-shaped environment.

#### P0.4 — Close privileged/media tenant security gaps before launch

- **Problem:** HQ MFA step-up can remain valid for the full session, and profile-video tenant/owner identity is not DB-enforced like photos.
- **Evidence:** HQ authorization/session code; `profile_videos` schema/model versus `profile_photos` composite constraints.
- **Why it blocks:** production migration and moderation require privileged access and large media writes; validation bypass or stale privileged sessions have high impact.
- **Architectural owner:** Admin security and Media/data-integrity domains.
- **Dependencies:** approved MFA freshness policy; safe migration/backfill plan for video constraints.
- **Backend work:** freshness-enforced step-up for privileged actions and composite video ownership constraint after validating existing rows.
- **Frontend work:** re-prompt flow for expired step-up; actionable authorization error handling.
- **Tests required:** time-bound MFA tests, revocation, wrong-brand/wrong-owner video inserts, migration validation, media attach/import regression.
- **Definition of Done:** privileged requests require a policy-fresh MFA assertion, and the database rejects every cross-brand/wrong-owner video relationship.

### P1 — required for operational completeness

- Deliver actual member and HQ clients or bring their repositories into the release evidence loop.
- Add safe HQ member corrections for migration exceptions with capability checks and immutable audit records.
- Complete agreed legacy graph parity (messages/history, trust state, preferences/devices) or explicitly approve retirement/member communication.
- Operationalise media processor recovery scheduling and delivery-provider monitoring.
- Resolve the existing DateZA notification baseline failure so the shared release gate is green.
- Implement dating verification and entitlements/payment flows if “complete” includes current Date9ja premium/verification behaviour.
- Revalidate and update the external client compatibility matrix against OpenAPI.

### P2 — important hardening

- Add DB tenant-consistency constraints for closure/enforcement/analytics relationships where feasible.
- Establish a controlled gender vocabulary and explicit open/multiple semantics without excluding existing supported same-gender pairs.
- Standardise optional capability gating at route/service boundaries.
- Expand audit browsing/export, product instrumentation, liquidity/time metrics, and provider health.
- Repair/pin the native media toolchain and state the accepted production MIME/codec contract.
- Reconcile duplicated schema concepts and define compatibility-shim retirement conditions.
- Consolidate contradictory Date9ja status documentation after current decisions are closed.

### P3 — future platform capability

- Live/realtime delivery, advanced ranking/experimentation, external operator/franchise access, broader commercial analytics, service/provider administration, and multi-client shared UI packages when real reuse exists.

## 17. Phase 14 — recommended next implementation slice

### One slice: canonical Date9ja country-name → ISO-2 import mapping

This is the best next bounded slice because the checked-in census says it affects the entire 288-row source population, `country_code` is a current completion requirement, the source values are a closed observable set, and the present importer deterministically drops them all. It requires no weakening of shared profile rules and no premature platform framework.

Scope the change to the Date9ja source adapter, backed by the shared canonical country-code validation already used by Profiles/Geography:

1. Produce an explicit reviewed mapping for the 23 observed country strings, including whitespace/case aliases and an unknown-value quarantine path.
2. Map only to valid canonical ISO-2 values; never infer nationality, preferred countries, ethnicity, or other sensitive concepts.
3. Preserve non-overwrite/idempotent semantics and add reason-coded reconciliation for unknown/invalid values.
4. Test all observed values, nil/blank/unknown inputs, reruns, and completion impact.
5. Rerun the focused Date9ja/profile/publication contract suite, full Rails suite, lint, Zeitwerk, Brakeman, and dependency audit.

**Definition of Done:** every observed source country value either maps to a reviewed valid ISO-2 code or appears in a zero-ambiguity quarantine report; reruns do not overwrite operator/native data; reconciliation totals equal source totals; no sensitive field is inferred.

This slice does not make Date9ja launch-ready by itself. Names, location, age/options, publication policy, capability enablement, media L3, and cutover remain explicit follow-ons.

### Proposed Claude/Codex execution order

1. **Claude:** implement the bounded adapter mapping, observed-value contract tests, and reconciliation output without altering shared completion semantics.
2. **Codex:** independently review source-to-target evidence, unknown-value/security behaviour, idempotency, tenant scope, and run focused/full quality gates.
3. **Claude:** address concrete review findings only.
4. **Codex:** final acceptance against the Definition of Done and record the evidence in the canonical Date9ja status/reconciliation documents.

## 18. Evidence index

Primary evidence consulted includes:

- `config/routes.rb`, `config/recurring.yml`, `config/deploy.yml`
- `db/schema.rb`, `db/migrate/`
- `app/models/`, `app/controllers/api/v1/`, `app/jobs/`
- `domains/d8n/platform/brands/`, `domains/identity/`, `domains/profiles/`, `domains/matching/`, `domains/discovery/`, `domains/media/`, `domains/notifications/`, `domains/trust/`, `domains/hq/`, `domains/admin/`, `domains/analytics/`, `domains/migration/date9ja/`
- `lib/tasks/date9ja_import.rake`, brand/geography/provisioning tasks
- `test/contracts/openapi_contract_test.rb`, `test/domains/date9ja/`, matching/discovery/likes/conversation/message/HQ/model/controller/job tests
- `docs/api/openapi.yaml`
- `README.md`, `PLAN_OF_ACTION.md`, `AGENT_RULES.md`, architecture docs, ADRs, scaling guide, diagrams, founder decision log
- Date9ja master plan, status, parity, value mapping, reconciliation, compatibility, cutover and acceptance documents
- Git status, log, and blame for the baseline notification/lint defect

## 19. Open questions requiring human decisions

1. **D-4 names:** May a legacy `full_name` be parsed, must members remediate first/last name, or is another authoritative source available?
2. **D-8 publication:** How do legacy active/hidden/onboarding states map to D8N draft/active and hidden/visible, and who approves bulk activation?
3. **D-12 age preference:** Should missing/partial source age bounds be remediated, defaulted under an approved policy, or keep members undiscoverable?
4. Which unmapped relationship-intent and wants-children source codes have canonical meanings, and which must be member-confirmed?
5. Is precise/chosen location recoverable and consented for migration, or must every member select a new `ProfileLocation`?
6. Which legacy likes, matches, conversations/messages, blocks/reports, notification state, verification, premium/entitlement, and analytics records are legally/product-required to migrate versus explicitly retire?
7. What Date9ja discovery ranking, daily limits, location freshness, and product surfaces are approved for launch?
8. What MFA freshness interval and which HQ actions require a new step-up?
9. Where are the Date9ja member and HQ frontend repositories, owners, supported versions, and release suites?
10. What production source-media transport is approved, and what constitutes accepted L3 proof/checksum/readback?
11. Is dating verification and paid entitlement parity a launch requirement or a post-cutover milestone?
12. Are the files under `docs/user-images/` approved for repository retention and external sharing with documented provenance/privacy review?

## Final audit position

D8N has the correct broad shared-platform shape and a meaningful amount of tested production-oriented backend code. Date9ja migration work is real, not nominal, but it currently proves adapter mechanics and synthetic media paths rather than an operational migrated brand. The shortest safe path is to close publishability inputs, enable the shared dating loop through a real Date9ja contract, prove full production cutover/reconciliation, and close the identified high-impact security constraints. No implementation should begin until the human decisions above are assigned or explicitly deferred.
