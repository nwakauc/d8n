# DateZA Holistic Product and Platform Plan

**Status:** Proposed plan for founder/product/engineering review

**Audit date:** 2026-08-21

**Backend baseline:** D8N `dev` at `279cd5b`
**Product source:** [`dateza/README.md`](dateza/README.md)

**Foundation status (2026-08-21):** DateZA is provisionable as the canonical
`DateZA`/`dateza` tenant with host-resolved phone/email password authentication,
a v1 shared-capability profile/onboarding catalog, Find with its Johannesburg-day
allowance, and deterministic compatibility v1. Cross-brand isolation is covered
against HookUs. DateZA daily Discovery and the remaining differentiating features
remain future work.

## 1. Outcome

DateZA should become the first clean demonstration that D8N can launch a new,
distinct dating product without copying HookUs or forking the backend.

The product promise is:

> Real people. Better matches. Date for real.

The core daily loop is:

1. **Discovery:** up to 10 compatibility-led people DateZA chooses for the member.
2. **Find:** up to 10 profiles the member chooses to explore on the free plan.
3. **Like or pass:** a mutual like creates a match.
4. **Chat:** matched members can talk safely.
5. **Meet:** the product helps genuine, compatible people reach a real-world date.

The long-term product is web and mobile, powered by the same brand-scoped D8N
API. DateZA owns its experience, language, design, marketing, and South African
product configuration. D8N owns reusable identity, profiles, matching, media,
verification, trust, messaging, moderation, notifications, billing, and analytics.

## 2. Decisions This Plan Makes

This plan proposes the following direction:

- Keep D8N as the only dating backend. Do not create DateZA backend models or
  business rules in a frontend repository.
- Create one separate DateZA frontend repository containing `apps/web`,
  `apps/mobile`, and small shared packages for the generated API client, domain
  types, validation, analytics names, design tokens, and test fixtures.
- Use Next.js for web and React Native with Expo for mobile, subject to founder/CTO
  approval. Share contracts and behavior, but do not force all UI into one
  cross-platform component abstraction.
- Build the standard dating loop first, but do not call the public product-ready
  MVP complete until the DateZA promise—RealMe, basic trust standing, and
  explainable compatibility—is honestly present.
- Use web as the fastest API integration and operational proving surface. Build
  mobile against the same stable contracts as each vertical slice passes on web.
- Keep Discovery and Find visibly and contractually distinct while reusing D8N's
  shared eligibility engine underneath.
- Treat DateZA as a tenant-isolation test: the same D8N identity may join DateZA
  and HookUs, but profiles, preferences, likes, matches, chats, reports,
  subscriptions, and notifications may never leak between them.

## 3. Product Interpretation

DateZA is not HookUs with different colours. It is a serious-relationship-oriented
South African dating product whose differentiation is confidence:

- **Identity:** evidence that a profile belongs to a real person.
- **Trust:** understandable standing based on account and behaviour signals.
- **Compatibility:** pair-specific scoring with useful, bounded explanations.
- **Choice:** curated Discovery and user-directed Find solve different needs.

The product remains recognisable dating software. AI ranks and explains eligible
people; it does not invent compatibility, relax safety rules, expose private data,
or become a chatbot placed between two members.

South African identity should come from the membership, locations, languages,
copy, imagery, safety guidance, payments, and local operations. DateZA must not
infer race, culture, religion, sexuality, or ethnicity.

## 4. Backend Audit Summary

The audit distinguishes implementation from aspiration. Routes, domain code,
schema constraints, request tests, and the OpenAPI contract were treated as the
primary evidence. The broad company blueprint and phase plan remain direction,
not proof that a capability is available.

### 4.1 Reusable now

| Capability | What exists in D8N | DateZA use |
| --- | --- | --- |
| Brand tenancy | Host-resolved `Brand`/`BrandDomain`, brand-owned records, composite tenant foreign keys | DateZA uses the canonical `dateza` brand and environment-provided host mappings |
| Platform identity | `User`, identifiers, credentials, memberships | One identity can explicitly join DateZA without copying another brand profile |
| Authentication | Phone/email + password registration/login, brand-bound bearer sessions, logout, password change/recovery, phone/email identifier verification | DateZA account entry and recovery |
| Onboarding state | Server-owned resumable `onboarding.next_step` and profile completion | Web and mobile resume the same flow correctly |
| Brand profiles | Separate profiles, preferences, controlled options, prompts, languages, completion, publication | Compose a DateZA catalog instead of adding DateZA conditionals |
| Location | Brand-owned write-only precise location and coarse city/country profile fields | Eligibility and distance without exposing coordinates |
| Media foundation | Private R2 upload intents, attachment, safe display derivative, signed retrieval, soft delete and purge | DateZA profile photos after moderation policy is completed |
| Shared matching | Tenant-safe bilateral eligibility, exclusions, deterministic ranking contract, signed cursors | Reuse eligibility for both Discovery and Find |
| Dating actions | Like, pass, atomic mutual match, match list | Standard DateZA core loop |
| Messaging | Match-gated text messages, history pagination, conversation previews | MVP text chat, with follow-up work listed below |
| Safety actions | Directional blocks; profile, message, photo, and hook reporting | DateZA block/report surfaces |
| Moderation foundation | Brand-scoped report queue, report transitions, suspension/reinstatement, security-event audits | Initial DateZA moderator workflow |
| Abuse protection | Auth-specific throttles and product action rate limits | Baseline protection for auth, discovery, interactions, messaging, reports, and uploads |
| Account closure | Brand-level closure, anonymisation, session revocation, relationship termination, media purge job | “Leave DateZA” workflow |
| API contract | Versioned routes, OpenAPI, Swagger, stable error codes, contract test | Generate frontend types and verify integrations |

### 4.2 Partially reusable, but not DateZA-ready

| Capability | Present limitation | Required outcome |
| --- | --- | --- |
| Brand configuration | DateZA tenant, development host, auth policy, minimal catalog and non-production strategy contract are implemented | Production domain/deployment configuration and later product strategies require explicit approval |
| Profile vocabulary | DateZA v1 required/optional fields, controlled options, prompts, language choices, completion, and next step are implemented; partner preferences remain limited to gender interest, age, and distance | Add explicit dealbreaker preferences only with an approved typed/privacy-reviewed contract |
| Compatibility | DateZA `dateza_v1` pair scoring, confidence threshold and bounded explanations are implemented for eligible Find pairs | Validate product outcomes; introduce a new explicit version for future rule changes |
| Discovery and Find | HookUs `for_you`/`new_here` Discovery exists; DateZA Find now has filter-led deterministic paging and a durable Johannesburg-day allowance | Curated DateZA daily Discovery remains separate and unimplemented |
| Photos | Safe derivatives exist, but provider moderation and complete production policy remain gated | Public delivery only after approved processing/moderation and retention behavior |
| Messaging | Plain text exists; no delivery/read state, client-send idempotency, push, realtime, image messages, unmatch endpoint, or chat safety classifier | Reliable mobile/web chat with safety and lifecycle behavior |
| Trust/moderation | Reports and suspensions exist; no public standing model, complete scam engine, appeals, differentiated RBAC, or hardened admin auth | Basic DateZA trust presentation plus an operable human safety process |
| Notifications | Brand-scoped event/outbox, inbox/read API, V1 preferences, encrypted device registrations, delivery attempts, and DateZA welcome email are implemented | Approve a production push provider/device enrollment API; add new event policies only with product/privacy review |
| Account management | Current session and logout exist; no session/device list or revoke-other-session API | Account security screen, or explicitly defer it from closed beta |
| Account deletion | Brand closure exists; platform-wide legal erasure/export is a separate unresolved workflow | Clear “leave DateZA” versus “delete D8N identity” language and approved POPIA process |

### 4.3 Not built

- Add only approved partner-dealbreaker preferences; do not infer dealbreakers from compatibility inputs.
- Daily curated recommendation batches and the 10-per-day Discovery allowance.
- Subscription entitlement checks and any paid Find allowance policy.
- Incoming likes (“who likes you”).
- RealMe selfie, liveness, photo, video, or ID verification assertions.
- User-facing trust standing and the policy that derives it.
- AI Matchmaker beyond deterministic scoring/ranking.
- Production push provider/device enrollment, matching/message notification
  policies, preference-management API, deep links, and quiet hours.
- Billing, products, subscriptions, entitlements, webhooks, and DateZA+.
- Product analytics event ingestion and funnel reporting.
- Full admin product (user search, media/verification review, appeals, metrics,
  granular roles, stronger admin authentication).
- Image messages, read receipts, delivery receipts, typing/presence, and realtime
  delivery.
- DateZA web or mobile application; no frontend project exists in this repository.

### 4.4 Audit risks that must be corrected early

- The tenant-foundation ticket reconciled `docs/api/README.md`, the API root
  service status, and the OpenAPI summary with the executable implementation.
  Future slices must keep those three status surfaces synchronized.
- DateZA / `dateza` is the sole active South African brand name. Its
  implementation uses the approved display name `DateZA` and slug `dateza`;
  production domains, app identifiers, deep-link scheme, and analytics prefix
  remain to be chosen explicitly.
- The current admin authenticates through an ordinary consumer session and any
  active assigned role grants moderation. That is a useful foundation, not the
  final stronger admin-auth/RBAC posture required for public launch.
- Message sends are at-least-once and can duplicate when a client retries. Mobile
  clients need a client-generated idempotency key before unreliable-network beta.
- RealMe and public trust standing are central DateZA promises but are currently
  absent. UI must never show fabricated verification or trust badges.

## 5. Target System Shape

```text
DateZA web browser
      |
      | same-origin HTTPS + secure HttpOnly web session
      v
DateZA Next.js web/session gateway ---- fixed host ----+
                                                       |
DateZA iOS/Android app -- bearer in OS secure storage -+--> D8N API
                                                            (dateza brand host)
                                                                   |
                          +----------------------------------------+
                          | D8N modular Rails monolith              |
                          | Identity / Profiles / Matching / Chat  |
                          | Media / Verify / Trust / Notifications |
                          | Billing / Analytics / Admin            |
                          +----------------------------------------+
                                     | PostgreSQL / jobs / private R2
```

For web, a thin same-origin session gateway is recommended so the D8N bearer is
kept in a secure, HttpOnly, SameSite cookie rather than browser local storage.
The gateway must use one server-configured DateZA API origin and may proxy only
explicit API routes; it must not become a second dating backend. Mobile calls the
same D8N contract directly and stores the bearer in iOS Keychain/Android Keystore.

Both clients bootstrap by checking authentication, fetching
`/profile/configuration`, and following server-owned onboarding state. Neither
client decides tenant, completion, eligibility, compatibility, entitlement, or
trust state locally.

## 6. Repository and Frontend Architecture

Proposed separate repository:

```text
dateza/
  apps/
    web/                 Next.js marketing + authenticated web product
    mobile/              Expo React Native iOS/Android product
  packages/
    api-client/          generated OpenAPI types + reviewed transport wrappers
    domain/              UI-safe mappings and shared state/query keys
    analytics/           stable event names and typed properties
    design-tokens/       colours, type, spacing, radii, motion, icon references
    test-fixtures/       contract-safe response fixtures
```

Share the following:

- OpenAPI-generated request/response types.
- Error-code mappings, date/age presentation, compatibility-reason copy, report
  reason copy, feature flags, analytics names, and test fixtures.
- Design tokens and asset sources.

Do not require sharing:

- Navigation, accessibility primitives, forms, image components, animation, or
  platform-specific interaction patterns.
- Web session-gateway code with the mobile transport.
- Device permissions, push registration, deep linking, or secure storage.

## 7. Domain Plan

### 7.1 Brands and Identity

Backend work:

- Add an idempotent DateZA brand installer, domain provisioning, supported auth
  methods, profile requirements, and deployment/CORS configuration.
- Add DateZA-specific integration fixtures and prove a HookUs token fails on the
  DateZA host and vice versa.
- Decide whether an existing D8N user gets an explicit “Join DateZA” flow in the
  MVP. Current registration does not silently attach an existing identity to a
  new brand; preserve that invariant.
- Add session/device management later or before public beta if required by the
  security policy.

Frontend work:

- Registration, login, identifier verification, forgot/reset password, logout,
  auth expiry recovery, and destructive account closure.
- Explain phone/email verification accurately. It proves control of an identifier;
  it is not RealMe verification.
- Keep DateZA and platform identity language understandable; never reveal another
  brand's membership.

### 7.2 Profiles and Onboarding

DateZA v1 onboarding should stay progressive:

1. Identity basics: display name, birthdate, gender, who the member wants to meet.
2. Location and dating range: city/country, private device location consent,
   preferred age and distance.
3. Intent and compatibility essentials: relationship goal, children, smoking,
   drinking, religion importance, lifestyle/meeting pace.
4. Profile expression: bio, photos, interests, languages, prompts.
5. RealMe invitation/requirement according to approved policy.
6. Review and publish.

Backend work:

- Implement `Profiles::DatezaProfileCatalog` by composing shared capabilities.
- Add only missing semantic capabilities after reviewing privacy, public
  visibility, filterability, and matching use. Avoid stuffing match-critical
  answers into `metadata`.
- Add a versioned compatibility questionnaire only if v1 questions cannot be
  represented by typed fields/options. Questionnaire answers need stable codes,
  versioning, history policy, and explicit serializers.
- Decide which partner preferences are hard eligibility/dealbreakers versus soft
  ranking inputs. Preference data should be typed and brand-scoped.
- Keep exact coordinates write-only. Present city, province, or coarse distance
  according to an approved DateZA location policy.

Frontend work:

- Render available fields and options from server configuration.
- Use server completion and `next_step`; save each step so onboarding resumes on
  another device.
- Request location only with clear consent and a usable city/manual fallback.
- Support photo upload progress, retry, reorder, delete, primary selection, and
  moderation states. Reordering/primary-photo backend APIs must be added first.

### 7.3 Discovery and Find

Both products reuse shared eligibility:

- Same brand only.
- Active identity, membership, and published profile.
- Adult age policy.
- Reciprocal gender, age, and distance rules.
- No self, blocks, closed/suspended accounts, previous active exclusions, or
  other safety removals.

Discovery adds:

- A server-created daily recommendation batch in the member's DateZA timezone.
- Up to 10 stable recommendations for that day.
- DateZA compatibility ranking, trust/verification eligibility or ranking policy,
  activity, freshness, and profile quality.
- A score, confidence, and safe explanation codes based on facts known to D8N.
- Idempotent retrieval: refreshing does not silently replace the day's people.

Find adds:

- User-controlled basic filters over the same eligible population.
- A separate daily free allowance.
- Deterministic cursor pagination and server-owned entitlement enforcement.
- No compatibility claim unless the score has sufficient inputs/confidence.

Recommended backend boundary:

- Shared `Matching::EligibilityScope` remains the base.
- The DateZA `dateza_v1` strategy produces pair-specific score/confidence/reasons.
- A focused recommendation-batch service owns daily Discovery selection.
- A focused product-allowance/entitlement policy owns limits; do not infer limits
  from generic HTTP rate limiting.
- Expose distinct DateZA API operations (for example, daily Discovery and Find)
  even if both call shared internals. Their quotas and refresh semantics differ.

Product decisions required:

- Does “10 Find profiles/swipes” count a profile exposure, a like/pass decision,
  or both? The backend cannot enforce an ambiguous allowance safely.
- Do unacted Discovery recommendations remain after midnight or expire?
- Can a passed profile return, and after what cooling period?
- Is DateZA timezone based on member location, configured market timezone, or UTC?
- What happens when fewer than 10 eligible people exist?
- Are unverified members allowed in Discovery, down-ranked, or excluded?

### 7.4 Compatibility and AI Matchmaker

Compatibility v1 should be deterministic and explainable before it becomes “AI.”

Proposed v1 dimensions:

- Hard gate: reciprocal dating eligibility and declared dealbreakers.
- High weight: relationship intention and children/family plans.
- Medium weight: smoking, drinking, faith importance, lifestyle and meeting pace.
- Supporting weight: interests, languages, communication and social style.
- Confidence: how much meaningful comparable data exists.

The implemented v1 weights and fit matrices are fixed under `dateza_v1` and
test-covered; product changes require a new explicit version.
Every explanation must come from bounded codes such as
`shared_long_term_intent`, `compatible_family_plans`, or `shared_interests`; no
private answer, inferred sensitive trait, raw risk score, or precise location may
be exposed.

The later AI Matchmaker may improve ranking and natural-language query planning,
but it must output authorised structured criteria and explanations. It cannot
query outside eligibility, invent facts, or use conversation content without a
separate consent/privacy decision.

### 7.5 RealMe Verification

RealMe must be a dedicated Verification domain, separate from authentication,
profile photos, and Trust.

Required backend sequence:

1. Define verification assertion types and levels.
2. Define public claim wording and expiry/reverification policy.
3. Select providers and data region.
4. Model attempts, derived assertions, provider references, review states, and
   audit events without storing unnecessary biometric evidence.
5. Add provider orchestration and signed/idempotent webhooks.
6. Add manual review and appeal workflows.
7. Add public badge serializer that states what is verified, not that the person
   is safe or trustworthy.
8. Define consent and portability if assertions may be reused across D8N brands.

The frontend must display “Phone verified” separately from “RealMe Verified” and
provide a plain-language badge detail sheet. No placeholder badge should ship.

### 7.6 Trust, Safety, and Moderation

Trust is account behaviour, not popularity and not compatibility.

Backend work:

- Define a policy-owned public standing taxonomy: for example `new_member`,
  `building_trust`, `good_standing`, and `strong_standing`.
- Keep detailed risk signals and thresholds private; serialize only approved
  public standing and non-sensitive badge claims.
- Add scam/abuse signals incrementally: suspicious links, financial solicitation,
  copy/paste or mass messaging, report outcomes, ban-evasion indicators, and
  abnormal auth/device behaviour.
- Expand moderator roles, sensitive-read audits, media/verification review,
  appeals, user search, case linkage, and urgent escalation.
- Retain immutable minimum evidence for a report while applying approved message
  and media retention policies.

Frontend work:

- Block, report, unmatch, and safety education must always be free and easy to
  reach.
- Show contextual warnings without claiming certainty or exposing detection
  logic.
- Use the backend report taxonomy; map codes to South African English copy and
  allow a bounded optional explanation.
- Give the member neutral success responses so target existence/moderation
  outcomes are not leaked.

### 7.7 Matches and Messaging

Backend work before robust mobile beta:

- Add an explicit unmatch operation with audited, brand-scoped lifecycle rules.
- Add client-generated message idempotency keys.
- Define and implement delivery/read state and unread counts.
- Add push-notification handoff and a polling-first sync contract; realtime can
  follow measured need.
- Add image messages only after message-media moderation, access, reporting,
  retention, and purge behavior is approved.
- Define post-unmatch, suspension, block, deletion, and legal-erasure transcript
  visibility.
- Add suspicious URL/financial-solicitation safety hooks without logging normal
  private message contents.

Frontend work:

- Optimistic messages must reconcile by client idempotency key and show pending,
  failed, sent, delivered, and read states only when the API supports them.
- Poll on first beta if necessary; do not fake realtime.
- Reporting a message should preserve enough local context for confirmation but
  submit only the documented target and optional details.

### 7.8 Notifications

Build one brand-scoped notification event/outbox path for:

- New like, match, and message.
- RealMe and moderation updates.
- Security/account events.
- Subscription events later.

Add user preferences, device push tokens, provider delivery records, deep-link
payloads, retries, deduplication, and quiet-hour policy. Keep SMS for auth or
exceptional safety/security needs; it is costly and intrusive.

### 7.9 Billing and DateZA+

Billing follows product validation, not the first standard-loop beta.

When implemented:

- Products, prices, subscriptions, and entitlements are brand-owned.
- Provider webhooks are signature-verified and idempotent.
- The server, never the client, decides the Find allowance and access to incoming
  likes/advanced filters.
- Basic messaging, RealMe baseline verification, block/report, and safety controls
  remain free.
- South African pricing, tax, cancellation, app-store, and web-payment obligations
  require human/legal review.

### 7.10 Analytics and Experimentation

Define a small, privacy-minimised event contract before UI implementation so web
and mobile remain comparable:

- Registration and onboarding step completed.
- Profile published and verification started/completed.
- Discovery batch viewed, recommendation viewed, explanation opened, like/pass.
- Find session/filter applied/profile viewed/allowance exhausted.
- Match created, conversation started, first reply, meaningful-depth milestone.
- Block/report and moderation outcome at aggregate level.
- Retention and subscription events later.

Measure recommendation quality against ordinary Find: match rate, reply rate,
conversation depth, report/block rate, and retention. Do not optimise merely for
swipes or time spent.

## 8. Delivery Phases

### Phase 0 — Decisions and contract honesty

- Preserve the approved `DateZA` display name and `dateza` slug; approve production domains separately.
- Resolve stale API status documentation.
- Approve MVP auth, minimum age, location, profile, verification, moderation,
  message retention, and Discovery/Find allowance policies.
- Create a DateZA architecture decision record for the two-surface discovery
  product and compatibility boundary.

Exit: frontend developers can identify every callable endpoint and every planned
endpoint without guessing.

### Phase 1 — DateZA tenant and standard loop

- Provision DateZA and its catalog.
- Add demo members and cross-brand isolation tests.
- Build web and mobile foundations, auth, resumable onboarding, profiles/photos,
  basic Find, likes, matches, text chat, block/report, settings, and closure.
- Add missing message idempotency and unmatch contracts.

Exit: internal users can complete the loop on both clients using DateZA-only data.

### Phase 2 — DateZA differentiation

- Ship daily Discovery batches using the implemented compatibility v1 boundary.
- Ship RealMe minimum viable verification and public claim presentation.
- Ship public trust standing backed by approved signals.
- Ship product notifications and the initial moderator workflow.

Exit: the private beta truthfully delivers “real people, better matches.”

### Phase 3 — Private beta hardening

- Push, read/delivery state, reliability/offline handling, media moderation,
  stronger admin authentication/RBAC, observability and analytics dashboards.
- Complete POPIA, retention, erasure/export, incident, support and moderation
  readiness.
- Run capacity and abuse tests using DateZA traffic shapes.

Exit: controlled South African private beta with staffed safety operations.

### Phase 4 — Monetisation and growth

- Incoming likes, advanced filters, DateZA+, subscriptions, entitlements and
  payment operations.
- Improve recommendation quality from real outcomes, not vanity signals.
- Expand localisation, provinces/cities and diaspora behavior where usage supports
  it.

Exit: validated paid value without paywalling safety.

### Phase 5 — Earned intelligence

- Conversational Matchmaker, richer media, date planning/check-ins, events, travel
  and diaspora modes only after evidence supports them.
- Extract infrastructure only when measured scale/reliability/team ownership
  justifies it.

## 9. Quality and Security Gates

Every backend API change must update the route, OpenAPI contract, integration
guide, request test, and OpenAPI contract test in the same change.

Required automated coverage includes:

- Same identity with separate HookUs and DateZA memberships/profiles.
- Token replay against another brand host fails.
- Cross-brand IDs and cursors return neutral failures.
- DateZA Discovery and Find never relax shared eligibility.
- Daily allocations are idempotent and concurrency-safe.
- Compatibility reasons disclose no private or sensitive inputs.
- Blocks immediately stop discovery, interactions, and message access.
- Report/admin reads and actions are brand-scoped and audited.
- Media originals and storage keys never reach public responses.
- Account closure removes DateZA participation without silently deleting another
  brand membership.

Frontend quality gates include generated contract drift checks, accessibility,
slow/offline/retry behavior, deep links, secure token handling, device permission
denial, visual regression for critical states, and end-to-end tests against a
DateZA seed dataset.

## 10. Human and Operational Gates

Before public beta, humans must decide or provide:

- POPIA/legal review, terms, privacy notice, consent and age policy.
- Exact location collection, freshness, withdrawal, access and retention policy.
- RealMe provider, evidence minimisation, data region, cost and public wording.
- Media moderation provider/policy, recovery window, retention and appeals.
- Message retention/export/erasure and moderator evidence access.
- Public trust taxonomy, signal governance and appeals.
- Moderation staffing, escalation, response targets and law-enforcement process.
- Production domains, email/SMS/push providers, secrets and cost budgets.
- Admin access list, MFA/step-up policy and incident ownership.
- App Store/Play Store accounts, policies, privacy declarations and age rating.

## 11. Measures of Success

The primary product measures are:

- Onboarding-to-published-profile conversion.
- RealMe completion and its effect on match/reply quality.
- Discovery versus Find recommendation-to-like, match, reply, meaningful
  conversation, block and report rates.
- Time to first good match and time to first reply.
- Conversations reaching meaningful depth without safety incidents.
- Week-one and month-one retention by city and member cohort.
- Dating-market health, including balanced eligible supply and unanswered-like
  distribution, without using popularity as trust.

The platform measure is equally important: DateZA ships and evolves without
cross-brand leakage, a backend fork, or HookUs-specific rules escaping their
strategy/catalog boundaries.

## 12. Founder/CTO Decision Log to Complete

1. Choose production domains, app identifiers and deep-link scheme while preserving
   the approved `DateZA` display name and `dateza` slug.
2. Approve the proposed frontend repository shape and web/mobile technologies.
3. Approve web's same-origin session gateway versus direct browser bearer storage.
4. Choose DateZA's launch cities and whether the first beta is South Africa only.
5. **Resolved for free v1:** the first unique Find exposure per membership,
   candidate, and Johannesburg day consumes allowance; replay/detail/Like/Pass do not.
6. Approve Discovery batch refresh/expiry and timezone rules.
7. **Resolved for compatibility v1:** profile inputs and versioned weights/reasons.
   Explicit partner dealbreakers remain a separate product/privacy decision.
8. Approve whether RealMe is required to publish, required to appear in Discovery,
   or encouraged after publication.
9. Approve public trust labels and the minimum evidence for each.
10. Decide whether the first internal alpha may run without product notifications,
    while public beta may not.
11. Approve post-unmatch and post-suspension chat-history behavior.
12. Approve the private-beta launch gate and who owns each human dependency.
