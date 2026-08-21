# DateZA MVP Build Plan

**Status:** Ready for sequencing after founder/CTO decisions

**Companion:** [`HOLISTIC_PLAN.md`](HOLISTIC_PLAN.md)

**Product source:** [`dateza/README.md`](dateza/README.md)
**Planning baseline:** D8N `dev` at `279cd5b`, audited 2026-08-21

**Foundation status (2026-08-21):** B1 tenant provisioning and the critical B2
DateZA/HookUs isolation proof, profile onboarding, DateZA Find, and deterministic
compatibility v1 are implemented. DateZA Discovery remains deliberately unavailable.

## 1. MVP Definition

The DateZA MVP is a private-beta-quality web and mobile dating product that lets a
South African adult:

1. Create and recover an account.
2. Complete and publish a DateZA-only profile with moderated photos.
3. Receive up to 10 explainable daily Discovery recommendations.
4. Explore up to 10 free Find profiles under an explicit allowance rule.
5. Like or pass, form a mutual match, and exchange reliable text messages.
6. Unmatch, block, report, and leave DateZA.
7. Complete the approved minimum RealMe flow and understand its claim.
8. See an approved, non-sensitive basic trust standing.
9. Receive essential in-app/push notifications.
10. Be protected by an operable DateZA moderation queue and suspension workflow.

This MVP excludes subscriptions, conversational AI, voice/video messages, events,
travel mode, public social features, and complex gamification. Image chat may be
deferred if its moderation and retention gates would delay a safe beta.

## 2. What Can Start Immediately

Frontend work can start against current D8N for:

- Auth method discovery, phone/email password registration and login.
- Identifier verification, password change/recovery, logout and account closure.
- Resumable profile onboarding using server configuration and completion.
- Typed profile details, controlled options, preferences, prompts and languages.
- Private location replacement/deletion.
- Photo upload/attach/list/delete in an R2-enabled environment.
- Existing discovery integration patterns, profile detail, like/pass and matches.
- Match-gated text conversations and paginated message history.
- Block list/block/unblock and profile/content reports.

Do not hardcode HookUs option codes or use HookUs as the DateZA tenant. DateZA's
minimal catalog is callable now; use that server configuration for foundation
screens. Use contract fixtures only for unbuilt DateZA-specific capabilities, and
replace—not ship—them as each backend contract becomes callable.

Backend work that can start immediately:

- Fix API capability/status documentation to match executable code.
- Configure an approved production DateZA domain/deployment later; none is assumed.
- Extend the implemented foundation catalog only after product/privacy decisions.
- Write the remaining DateZA daily Discovery lifecycle ADR.
- Add unmatch and client message idempotency.

Human work that must start in parallel:

- Choose production domains while preserving the canonical `DateZA`/`dateza` naming.
- Review compatibility v1 outcomes with product data before changing its versioned policy.
- Decide the precise meaning of the daily allowances.
- Choose RealMe/media moderation providers and policies.
- Complete the initial POPIA, location, message retention and moderator-access
  decisions.

## 3. MVP Scope Matrix

| MVP capability | Current D8N | Backend needed | Web/mobile needed |
| --- | --- | --- | --- |
| DateZA tenant | Foundation available | Production domain/deployment config remains an explicit later decision | Fixed brand origin and brand assertions |
| Register/login/logout | Reusable | DateZA enablement; optional session list later | Complete auth UX and secure token/session handling |
| Password recovery | Reusable | Provider configuration and status-doc correction | Request, code verify, reset and neutral error UX |
| Identifier verification | Reusable | Provider configuration | Separate phone/email verified presentation from RealMe |
| Onboarding/profile | DateZA v1 required/optional catalog, render metadata, completion and server-owned next step are available | Add only approved partner-dealbreaker capabilities | Progressive, resumable forms rendered from config |
| Photos | Partial | Reorder/primary endpoint; moderation provider/policy; production validation | Upload progress/retry/order/delete/review states |
| Daily Discovery 10 | Missing | Stable daily batches, DateZA ranker, allowance metadata | Default home, cards, “why,” empty/exhausted/refresh states |
| Find 10 | Implemented in D8N | Future paid entitlement policy only | Browse/swipe, filters and allowance states remain frontend work |
| Compatibility | `dateza_v1` implemented on eligible Find cards | Product validation and a new explicit version for rule changes | Score and reason sheet; no invented explanations |
| Like/pass/match | Reusable | Allowance integration and match event | Optimistic-safe actions and match celebration |
| Incoming likes | Missing | Defer or add if founder makes it MVP | Do not build until backend/entitlement contract exists |
| Text chat | Partial | Idempotency, unread/read/delivery policy, notification event, unmatch | Reliable retry/offline chat and lifecycle states |
| Block/report | Reusable | DateZA taxonomy/copy mapping and policy confirmation | Free, prominent, neutral-success flows |
| RealMe | Missing | Verification model/provider/webhooks/review/public claims | Consent, capture/redirect, status and badge explanation |
| Trust standing | Missing | Public standing policy and serializer | Approved labels/detail; no raw score |
| Notifications | Missing for dating | Events/outbox, preferences, push tokens/delivery/deep links | Permission timing, inbox/badges, push routing |
| Admin/moderation | Partial | Stronger auth/RBAC plan, media/verification review and operational gaps | Separate secure admin surface, not consumer navigation |
| Analytics | Missing | Event ingestion/retention contract or approved provider path | Shared typed events with minimal properties |
| DateZA+ | Missing | Out of MVP | Upsell placeholders must not imply purchasable features |

## 4. Proposed MVP API Work

Exact paths must be approved in the ADR and added to OpenAPI. The capabilities
below are the required contract, not permission to invent undocumented routes in
clients.

### Existing operations to reuse

```text
GET    /api/v1/auth/methods
POST   /api/v1/auth/password/register
POST   /api/v1/auth/password/login
PATCH  /api/v1/auth/password
POST   /api/v1/auth/password/recovery
POST   /api/v1/auth/password/recovery/verify
POST   /api/v1/auth/password/recovery/reset
POST   /api/v1/auth/verification
PATCH  /api/v1/auth/verification
DELETE /api/v1/auth/session

GET    /api/v1/me
DELETE /api/v1/me
GET    /api/v1/profile/configuration
GET    /api/v1/profile
PATCH  /api/v1/profile
GET    /api/v1/profile/preferences
PATCH  /api/v1/profile/preferences
PATCH  /api/v1/profile/options
GET    /api/v1/profile/prompts
PUT    /api/v1/profile/prompts
PUT    /api/v1/profile/location
DELETE /api/v1/profile/location
POST   /api/v1/profile/publication
DELETE /api/v1/profile/publication
GET/POST/DELETE profile photo operations

GET    /api/v1/profiles/:profile_id
POST   /api/v1/profiles/:profile_id/likes
POST   /api/v1/profiles/:profile_id/pass
GET    /api/v1/matches
GET    /api/v1/conversations
POST   /api/v1/matches/:match_id/conversation
GET    /api/v1/conversations/:conversation_id/messages
POST   /api/v1/conversations/:conversation_id/messages
GET/POST/DELETE block operations
POST   /api/v1/reports
POST   /api/v1/profiles/:profile_id/report
```

### New or extended contracts required

- DateZA daily Discovery operation returning:
  - batch date/timezone and refresh time;
  - up to 10 stable candidates;
  - interaction state;
  - the implemented compatibility score, confidence and bounded reason codes;
  - remaining/unavailable state without leaking candidate supply.
- DateZA Find operation returning:
  - approved basic filters;
  - signed cursor;
  - allowance limit/used/remaining/reset time;
  - safe candidate cards.
- Photo order/primary update.
- Explicit unmatch with defined conversation-history result.
- Message create extension with `client_token`/idempotency key.
- Conversation/message extensions for unread/read/delivery state if retained in
  the MVP definition.
- RealMe attempt, status and public assertion operations.
- Public trust-standing field or focused operation.
- Notification list/preferences/device registration/read operations.
- DateZA analytics ingestion, unless an approved privacy-safe external SDK is used
  directly by both clients.

## 5. Backend Vertical Slices

Each slice must update implementation, OpenAPI, integration guidance, request
tests, contract tests, and operational status together.

### B0 — Contract truth and DateZA decisions

Deliver:

- Reconcile root/API README/OpenAPI capability status with current routes.
- Record canonical DateZA naming.
- ADR for DateZA Discovery versus Find, allowances, compatibility and privacy.
- Decision record for MVP RealMe and trust policies.

Acceptance:

- A frontend engineer can tell what is available without reading Rails code.
- No DateZA UI contract depends on an unapproved product rule.

### B1 — DateZA tenant bootstrap (implemented foundation)

Deliver:

- Idempotent `dateza` brand/domain installer.
- DateZA auth methods and profile completion requirements.
- `Profiles::DatezaProfileCatalog` using shared capabilities.
- DateZA demo seed with realistic, synthetic South African profiles.
- DateZA host/CORS/deployment environment configuration.

Acceptance:

- Fresh setup provisions DateZA reproducibly.
- The DateZA configuration endpoint contains no HookUs `intents`, `vibes`, Hook,
  or Hook Tonight assumptions unless DateZA explicitly chooses a shared semantic
  capability.
- HookUs and DateZA can coexist in one database.

### B2 — Tenant proof (implemented foundation)

Deliver integration tests for one D8N identity participating separately in
HookUs and DateZA.

Acceptance:

- Brand-bound tokens cannot cross hosts.
- Profiles, photos, preferences, discovery, likes, matches, conversations,
  messages, blocks, reports and closures remain isolated.
- Closing DateZA does not remove or expose the HookUs presence.
- Cross-brand public UUIDs and cursors produce neutral errors.

### B3 — DateZA profile and photo readiness (profile contract implemented)

Deliver:

- Approved typed fields/options/preferences and completion rules.
- Photo reorder/primary operation.
- Production media processing/moderation policy and provider integration required
  for other-member delivery.
- Approved location freshness, city/province and distance-display policy.

Acceptance:

- A complete DateZA profile can publish; removing required data auto-unpublishes.
- Public profiles expose derived age and approximate location only.
- Originals, metadata, coordinates and storage identifiers never appear publicly.
- Rejected/pending/deleted photos follow documented UI and purge states.

### B4 — Find (implemented backend)

Implemented:

- DateZA Find strategy/query using shared eligibility.
- Basic filters: age, distance/location, gender/preference and relationship intent.
- Server-owned free allowance and reset semantics.
- Signed cursor bound to brand, filters and allowance context.
- Durable unique exposure ledger keyed by membership, candidate and Johannesburg day.

Acceptance:

- Find cannot bypass bilateral eligibility, block, suspension or publication.
- Concurrent requests cannot consume or exceed the allowance incorrectly.
- The response tells clients what state to render without exposing raw internal
  counters or another member's private preferences.

### B5 — Compatibility v1 (implemented backend)

Deliver:

- Approved DateZA compatibility dimensions, hard conflicts and missing-data rules.
- Deterministic score, confidence and bounded reason codes.
- Pair-aware tests covering asymmetric preferences and every explanation.
- Safe caching/precomputation only if measured performance requires it.

Acceptance:

- Same inputs always give the same result/version.
- Reasons are true for the pair and disclose no private values.
- Low-confidence pairs are labelled or omit a percentage according to policy.
- Popularity/likes never increase trust or compatibility.

### B6 — Daily Discovery 10

Deliver:

- Stable member/day recommendation batch and batch items.
- DateZA ranker using compatibility plus approved quality/activity/trust/RealMe
  signals.
- Idempotent generation, refresh and exclusion handling.
- Allowance and timezone policy.

Acceptance:

- Refreshing returns the same valid daily set/order unless safety removes a member.
- A block/suspension/closure removes an item immediately even from an existing
  batch.
- Fewer than 10 eligible people produces an honest bounded result.
- Batch creation is concurrency-safe and observable.

### B7 — Match and chat reliability

Deliver:

- Explicit unmatch.
- Message client idempotency.
- Conversation unread/read/delivery behavior approved for MVP.
- Product notification event hooks.
- Chat/report/block lifecycle tests.

Acceptance:

- Retried sends do not duplicate messages.
- Block and unmatch behavior matches documented history/access policy.
- New messages update conversation order and unread state consistently.
- Private text is absent from ordinary logs and analytics.

### B8 — RealMe MVP

Deliver:

- Minimal approved verification ladder and assertion model.
- Provider integration, attempt state machine, idempotent signed webhooks, expiry
  and retry policy.
- Public claim serializer and moderator review path.
- Consent, retention, deletion and audit behavior.

Acceptance:

- Badge wording corresponds exactly to a valid assertion.
- Phone/email auth verification cannot masquerade as RealMe.
- Evidence is minimised and never exposed in profile/admin responses beyond
  approved review access.
- Cross-brand assertion reuse is impossible unless explicitly consented and
  policy-approved.

### B9 — Trust and moderation MVP

Deliver:

- Public standing taxonomy and conservative derivation policy.
- DateZA report categories mapped to stable backend codes; add codes only when
  semantic gaps are real.
- Media/RealMe review, urgent escalation, role permissions and audits.
- Initial scam link/financial-solicitation safeguards.

Acceptance:

- Standing never derives from attractiveness or like count.
- Raw risk values and signal details remain private.
- DateZA moderators cannot access HookUs cases.
- Every sensitive view/action is authorised and audited.

### B10 — Product notifications and analytics

Deliver:

- Brand-scoped notification events, preferences, device tokens, delivery jobs,
  deduplication and deep-link payloads.
- Privacy-minimised analytics event contract and ingestion path.

Acceptance:

- Match/message/verification/moderation pushes reach only the correct brand user.
- Revoked device tokens are retired safely.
- Preferences and quiet hours are enforced.
- No precise coordinates, credentials, private messages, provider evidence or raw
  trust signals enter analytics.

## 6. Frontend Vertical Slices

### F0 — Workspace and design foundation

Deliver:

- Separate DateZA repository with web/mobile/apps and shared packages.
- OpenAPI generation pinned to a backend commit and a CI drift check.
- DateZA design tokens, typography, icon/asset approach and accessibility baseline.
- Environment validation that permits only approved DateZA API origins.
- Test fixtures for success, empty, loading, expired-session, rate-limit, network
  failure and validation states.

Acceptance:

- Both apps build in CI.
- No secrets or production tokens are bundled.
- No client accepts a user-controlled API/brand host.

### F1 — Authentication and session lifecycle

Web:

- Same-origin server session gateway, register/login/recovery/verification/logout.
- HttpOnly secure cookie, CSRF protection for session mutations, safe redirects.

Mobile:

- Direct D8N transport, OS secure token storage, foreground bootstrap, logout and
  expired-token handling.

Shared acceptance:

- Auth method UI comes from `/auth/methods`.
- Generic recovery errors do not reveal whether an account exists.
- No bearer token appears in URL, logs, analytics or browser local storage.

### F2 — Resumable onboarding

Deliver:

- Progressive steps driven by DateZA configuration and `onboarding.next_step`.
- Typed local drafts only for unsaved UI state; the server remains authoritative.
- Date, age, option, location-consent and validation UX.
- Resume after restart/login on another client.

Acceptance:

- Web can start and mobile can resume the same profile, and vice versa.
- No frontend-only completion rule exists.
- Underage/invalid profile input fails safely with useful field errors.

### F3 — Photos and profile

Deliver:

- Upload intent/direct upload/attach pipeline with progress and retry.
- Order, primary, delete and moderation state once backend contracts exist.
- Owner profile, public profile, edit sections, prompts, interests and languages.

Acceptance:

- Expired signed URLs refresh through API state, not cached permanent paths.
- A deleted/rejected photo disappears according to policy.
- Exact location and private owner fields never appear on a public screen.

### F4 — Find and interactions

Deliver:

- Find browse/swipe, basic filters, public profile detail, like/pass and allowance
  exhausted/reset states.
- Idempotent UI handling: disable duplicate gestures while preserving retry.

Acceptance:

- A card cannot be acted on after the backend says it is unavailable.
- Clients use opaque cursors unchanged.
- The UI never tries to bypass the server allowance.

### F5 — Daily Discovery and compatibility

Deliver:

- Default authenticated home showing “Your 10 for today.”
- Compatibility score/confidence presentation and “Why this match?” sheet.
- Like/pass/profile actions and next-refresh/empty states.

Acceptance:

- Explanation copy maps only documented reason codes.
- Discovery remains distinct from Find in navigation, copy and analytics.
- No “AI” claim is shown unless the shipped ranking justifies the approved claim.

### F6 — Matches and chat

Deliver:

- Match celebration, match/conversation list, text transcript, retry-safe composer,
  pagination, unread state, block/report/unmatch.
- Polling and app-resume sync first; add realtime only when backend and reliability
  tests support it.

Acceptance:

- Failed/offline sends reconcile without duplication.
- A block immediately removes composer access and follows history policy.
- Reporting a message uses its public ID and returns neutral confirmation.

### F7 — RealMe, trust and safety

Deliver:

- RealMe entry, consent, provider capture/redirect, pending/failure/retry/success.
- Badge details that identify the verified evidence scope.
- Approved trust standing and contextual scam safety prompts.
- Safety centre, block list, reporting and account closure.

Acceptance:

- Verification never implies personal safety or good character.
- Raw scores, provider data and moderation outcomes never appear.
- Safety controls work without subscription.

### F8 — Notifications, settings and launch polish

Deliver:

- Push permission requested after value is understood, device registration,
  notification routing and preferences.
- Privacy/location controls, password/identifier settings and account closure.
- Accessibility, low-bandwidth images, crash/error reporting, deep links, store
  metadata and end-to-end smoke tests.

Acceptance:

- Notification taps open only authorised current-brand resources.
- Denying push or location does not trap the member without a documented product
  reason.
- Destructive actions require explicit confirmation and explain their scope.

## 7. Recommended Build Sequence

The work is dependency-driven, not a promise of calendar duration.

| Wave | Backend | Web | Mobile | Exit result |
| --- | --- | --- | --- | --- |
| 0 | B0 decisions/status truth | F0 workspace/design | F0 workspace/design | Stable vocabulary and contract workflow |
| 1 | B1 tenant + B2 isolation | F1 auth | F1 auth | Both clients authenticate only to DateZA |
| 2 | B3 profile/media | F2/F3 onboarding/profile | F2/F3 onboarding/profile | Cross-device published DateZA profile |
| 3 | B4 Find | F4 Find | F4 Find | Standard browse/like/pass vertical works |
| 4 | B5/B6 compatibility + Discovery | F5 Discovery | F5 Discovery | “10 we choose; 10 you choose” works |
| 5 | B7 chat reliability | F6 matches/chat | F6 matches/chat | Reliable safe text loop works |
| 6 | B8/B9 RealMe + trust/moderation | F7 verification/safety | F7 verification/safety | DateZA promise is truthful and operable |
| 7 | B10 notifications/analytics | F8 launch polish | F8 launch polish | Private beta release candidate |

Web should prove each new API slice first because feedback is faster, but mobile
should follow within the same contract wave rather than waiting for a completely
finished web product. This exposes assumptions that fail on mobile—secure storage,
offline retry, permissions, push and deep linking—before launch.

## 8. First 20 Executable Work Items

1. Founder approves the launch market/cities and MVP definition; DateZA naming is fixed.
2. CTO approves DateZA frontend repo shape and web session approach.
3. Reconcile API status documentation with current implementation.
4. Write/approve the remaining daily Discovery lifecycle ADR.
5. **Done:** create idempotent DateZA brand/domain/auth installer.
6. **Done for foundation:** implement the minimal `Profiles::DatezaProfileCatalog`.
7. **Done for foundation:** add synthetic registration/configuration proof and catalog tests.
8. **Done:** add DateZA/HookUs isolation integration tests for the touched resources.
9. Scaffold the DateZA frontend repository and CI.
10. Generate the first API client and establish contract drift checking.
11. Implement secure auth bootstrap on web and mobile.
12. Implement resumable onboarding and owner profile editing.
13. Complete photo order/primary and production moderation backend slice.
14. Implement photo/profile screens on both clients.
15. **Done:** implement the locked Find exposure rule and backend allowance.
16. Implement Find/profile/like/pass on both clients.
17. **Done:** implement approved `dateza_v1` inputs, weights, confidence and reasons.
18. Implement stable daily Discovery batches and both Discovery screens.
19. Add unmatch, message idempotency and chat lifecycle behavior.
20. Complete RealMe/trust/notifications/moderation slices before inviting the
    external private-beta cohort.

## 9. Test Strategy

### Backend

- Model/database invariants for all new tenant-owned tables.
- Service tests for allowances, scoring, batch generation, verification state and
  notification deduplication.
- Concurrency tests for daily batches, allowance consumption, reciprocal likes,
  message idempotency and provider webhooks.
- Request tests for every endpoint/error/lifecycle state.
- Cross-brand tests for DateZA against HookUs.
- OpenAPI contract, full Rails tests, RuboCop, Brakeman and dependency audit.

### Frontend

- Unit tests for error/reason/event mappings and form validation.
- Contract-fixture tests generated from the canonical schemas.
- Component tests for loading/empty/error/moderation/allowance states.
- Web end-to-end flows in a real browser.
- Mobile device/simulator end-to-end smoke flows.
- One shared black-box journey against staging:

```text
register -> verify identifier -> onboard -> publish -> Discovery/Find
-> like reciprocally -> match -> chat -> report/block/unmatch -> close account
```

### Manual safety and privacy review

- Screen recording/log inspection contains no token, private message, coordinate,
  original media key or provider evidence.
- Accessibility review for auth, onboarding, cards, chat and safety actions.
- Slow network, expired signed URL, offline send, permission denial, provider
  failure and account suspension exercises.
- Moderator drill for an underage, scam, threat and impersonation report.

## 10. Private Beta Release Gate

Do not invite external beta members until all are true:

- DateZA and HookUs isolation tests pass.
- DateZA web and mobile complete the standard loop against staging.
- Daily Discovery and Find limits are server-enforced and understood.
- Compatibility explanations are deterministic, reviewed and privacy-safe.
- RealMe claims are truthful, auditable and have a supported failure/review path.
- Trust labels and moderation policy are approved.
- Block, report, unmatch, suspension and account closure work end to end.
- Media moderation and purge behavior are operational.
- Message retention/evidence/access behavior is approved.
- Essential notifications and moderator alerts work.
- POPIA/privacy/terms/age/location consent have human/legal approval.
- Production backup/restore, monitoring, provider secrets, incident ownership and
  moderation staffing are in place.
- Full backend tests, lint and security checks pass; web/mobile CI and release
  smoke tests pass.

## 11. Explicit MVP Deferrals

- DateZA+ and payments.
- See-who-likes-you unless founder promotes it and backend entitlement exists.
- Advanced filters beyond the approved basic set.
- Conversational AI Matchmaker.
- Voice notes, video, livestreams, stories, social feed and public comments.
- Events, concierge introductions, travel mode and diaspora-specific discovery.
- Background location tracking.
- Mandatory government-ID verification unless the approved RealMe policy requires
  it for a narrowly defined risk case.
- Microservices, dedicated recommendation infrastructure or realtime systems
  without measured need.

## 12. Decisions Needed Before B1–B6 Are Final

The founder/product owner should answer these first:

1. Which production domains, app identifiers and deep-link scheme should DateZA use?
2. Which cities/provinces are in the first private beta?
3. Is email/password, phone/password, or both offered at launch?
4. Which fields are required to publish versus progressively requested?
5. Which preferences are hard dealbreakers versus compatibility signals?
6. **Resolved:** Find consumes allowance on first unique exposure, never Like/Pass.
7. What timezone and expiry define a DateZA day?
8. Does RealMe gate publication, Discovery eligibility, messaging, or only a badge?
9. What minimum verification creates “RealMe Verified”?
10. Which public trust labels are approved and appealable?
11. Is read state required for MVP, and what is the post-unmatch history policy?
12. Can the first internal alpha use polling and no push while the private-beta
    release still requires push?
