# DateZA Backend Production Audit

Read-only, evidence-based audit of the D8N backend as it serves the DateZA brand.
No product code was changed. Working tree left clean.

---

## 1. Scope honesty statement

| Item | Detail |
|---|---|
| Commit audited | `ce5947ff43cac69b4fb5074a5596a700eca2a6f5` (branch `dev`) |
| Working tree | Clean before and after (`git status --porcelain` empty, `git diff --check` clean) |
| Environment exercised | Local `RAILS_ENV=test` against Postgres `d8n_test` on this machine |
| Rails / Ruby | Rails 8.1.3.1 / Ruby 3.3.12 |
| What was run live | Full `bin/rails test` (1069 runs), `rubocop`, `brakeman`, `bundler-audit`, `zeitwerk:check` (test env), OpenAPI contract tests |
| What was source-reviewed only | All routes, controllers, `domains/*` services, serializers, `db/schema.rb`, brand contract, CORS/session config |
| What was NOT tested | Staging (`staging-api.d8n.tech`), production (no production destination exists yet), live browser cookie behaviour (Safari/iOS), real R2 media delivery, real email/SMS/push delivery, load/perf profiling under volume |
| Production eager-load | `zeitwerk:check` in `RAILS_ENV=production` aborts before autoload because `D8N_AR_ENCRYPTION_PRIMARY_KEY` is unset locally (expected — keys are Kamal secrets). Test-env eager load passes ("All is good!"). |
| Limitations | Single reviewer, static + test-suite evidence. Browser-specific session conclusions are **NOT VERIFIED** and flagged as such. No access to staging seed data to confirm the "non-face primary photo" observation directly. |

Evidence tags used below: **SOURCE VERIFIED** (read in code), **TEST VERIFIED** (a test exercises it and passed here), **NOT VERIFIED** (needs live/staging).

---

## 2. Executive summary

### Scores (backend only, for the DateZA brand, today)

| Dimension | Score /100 | Basis |
|---|---:|---|
| Overall backend production readiness | **58** | Core loops (auth, profile, photos, find, openers, chat, blocking, reporting) are real and well-built; two of the four primary nav destinations (Likes, most of Notifications) have no backend contract; Safari cross-site session is architecturally unsound as currently deployed |
| Architecture / code quality | **86** | Clean modular-monolith domain separation, shared capabilities not per-brand forks, strong transactional discipline, row locks, idempotency via partial unique indexes, enumeration-resistant error shapes. Rubocop clean, Brakeman 0 warnings |
| Product-capability completeness | **48** | Likes list (both directions) absent; notifications taxonomy is a single `dateza.welcome` type; no data export; no unmatch; Discover facet filters are parsed but not applied on the daily surface |
| Security / safety | **72** | Auth hardening is genuinely strong; blocking is enforced cross-surface everywhere a surface exists; message-level reporting exists. Gaps: no automated photo content moderation, no appeal lifecycle, immediate photo visibility before review |
| Privacy / POPIA readiness | **55** | Coordinates never exposed publicly, distance bucketed, location hard-deleted on closure, audit events are content-free. Gaps: no data export, no platform-level identity erasure, closure retains messages/reports (defensible), no DSAR tooling |
| Operational readiness | **62** | Good indexing, cursor pagination everywhere, async media/notification jobs, idempotent job keys. Gaps: distance filter does a full haversine per row with no bounding box in Find; daily-batch pool scan bounded at 500; no production destination configured yet |

### Top strengths

1. **Identity/auth is production-grade** — enumeration-resistant registration and recovery, advisory locks, timing-attack bcrypt burns, layered OTP throttle (cooldown + identifier window + IP window), encrypted OTP ciphertext so plaintext never reaches job args/logs.
2. **Cross-surface block enforcement is real** — `Trust::BlockPolicy` is applied in discovery, Find, matches list, conversation list, message read/write, profile detail, and opener eligibility. Blocking also ends matches and deletes likes both directions in one locked transaction.
3. **Data-integrity invariants are enforced at the database** — partial unique indexes on active like pair, active match pair, active block pair, one open report per (reporter, target); `RecordNotUnique` rescues make concurrent double-submits idempotent.
4. **Shared abstractions, not brand forks** — one discovery engine, one messaging system (openers promote into the same `Conversation`), one reporting entry point (`Trust::FileReport`) with per-target resolvers.

### Top risks

1. **Likes is a primary nav destination with zero backend contract.** `Like` data and indexes exist; there is no endpoint to read incoming ("Liked you") or outgoing ("You liked") likes. The frontend cannot build the tab.
2. **Notifications taxonomy is a single type.** Only `dateza.welcome` exists, fired only by `membership_registered`. No notification for like, match, opener, opener reply, message, verification, or safety. The Likes/Matches/Messages/Activity filter tabs have nothing to query.
3. **Safari / cross-site session.** Staging serves the SPA from `dateza.vercel.app` and the API from `staging-api.d8n.tech` — different registrable domains. The session cookie is `SameSite=None; Secure` (correct) but is a **third-party cookie** in that topology, which Safari (desktop + iOS) blocks by default. Login will not persist on Safari as currently deployed. **NOT VERIFIED** live, but the architecture guarantees it.
4. **No automated photo content moderation.** File-safety checks are excellent; there is no NSFW/face/quality check. DateZA photos are `visible` immediately on attach (`PhotoPolicy::IMMEDIATE`), moderated only later and only by a human admin. The "non-face screenshot as primary photo" observation is consistent with this being a real policy gap, not just bad seed data.
5. **No "Download my data" capability of any kind** — no export service, job, or endpoint anywhere in the codebase.

### Launch blockers (must fix before inviting real users)

- **B1.** Likes list endpoints (incoming + outgoing) — the tab is dead without them.
- **B2.** Deploy the API first-party to the SPA (same site) OR ship a documented Bearer-token auth path for browsers, so sessions persist on Safari/iOS.
- **B3.** Decide and enforce a photo gate: either flip DateZA to `moderate_first`, or add an automated safety check before `visible`.
- **B4.** Minimum honest notification taxonomy (at least: match, new message, opener received) OR hide the non-functional notification filter tabs for V1.
- **B5.** POPIA: a data-export path and a documented deletion/retention position before real personal data is collected at scale.

---

## 3. Capability matrix

| Area | Status | Evidence |
|---|---|---|
| Auth (email/phone + password) | **READY** | `Identity::PasswordRegistration/PasswordLogin/AccountReactivation`, `SessionAuthenticator`, `PasswordThrottle`, `OtpThrottle`. Enumeration-resistant, throttled, advisory-locked. TEST VERIFIED (identity domain tests pass) |
| Onboarding | **READY** | `Profiles::OnboardingStatus`, `Configuration`, `RichCompletion`; `GET /profile/configuration` drives a brand-config-driven form |
| Profile (read/write) | **READY** | `GET/PATCH /profile`, `FieldPolicy` allowlist per brand, `OwnerSerializer`, mass-assignment safe (`params.permit(*writable_profile_fields)`) |
| Photos (pipeline) | **PARTIAL** | Upload/attach/reorder/delete all real; magic-byte sniffing, size bound, EXIF strip, re-encode, decompression-bomb guard, async processing, fail-closed delivery. **No content moderation automation**; `IMMEDIATE` visibility |
| Location | **PARTIAL** | `PUT /profile/location` (raw coords) and `PUT /profile/place` (server-resolved centroid) both work; persistent (no freshness expiry) for DateZA. **No GET endpoint**; device-GPS locations are not readable back (place selections are, via `GET /profile`) |
| Discover | **PARTIAL** | DateZA default surface is `discovery.curated_daily` — a stable daily batch of 10 via `StableDailySelection` + `DatezaV1`. Works. **Facet filters (`verified`, option groups, activity) are parsed/validated but never applied on the daily surface** — client-side filtering is the only option |
| Find | **READY** | `Matching::Find::Search`, per-day ledger `FindProfileExposure` (10/day, Africa/Johannesburg), separate from Discover's bucket, membership row-locked, repeat-safe, exclusion rules applied |
| Likes | **BROKEN** | `POST /profiles/:id/likes` creates likes + mutual match idempotently. **No endpoint to list incoming or outgoing likes.** `Profile#likes_received` association exists, unused |
| Matches | **READY** | `GET /matches`, cursor-paginated, excludes blocked/suspended/closed participants, `BlockPolicy.exclude_matches` |
| Openers (D8N Opener) | **READY** | `POST /profiles/:id/opener` (catalog key), `GET /openers`, reply/decline. One-per-pair unique index, expiry, reply creates the Match + Conversation atomically. State surfaced via `Hooks::OpenerStateDecorator` on discovery cards |
| Conversations | **READY** | `POST /matches/:id/conversation`, `GET /conversations`, participant auth via `MatchAccess`, block-aware, cursor-paginated, DISTINCT ON for last message |
| Messages | **PARTIAL** | Send/list/paginate real, body NFC-normalized + length-bounded, rate-limited (30/10s, 600/h). **No client idempotency key** (retry = duplicate, documented as beta-accepted). No mute/archive/leave/delete/unmatch/attachments/reactions/read-receipts/typing |
| Notifications | **PARTIAL** | Inbox, unread count, mark-read, mark-all-read, brand-scoped, presenter. **Only one type: `dateza.welcome`.** `NotificationPreference` model exists but **no endpoint** to read/write it |
| Blocking | **READY** | `POST/DELETE /profiles/:id/block`, `GET /blocks`. Enforced in every surface that exists; ends matches, deletes likes both ways, locked transaction |
| Reporting | **READY** | `POST /reports` generic (`profile` / `message` / `profile_media` / `hook` / `conversation` targets), legacy `POST /profiles/:id/report` preserved. Per-target server-side resolvers, content-free `SecurityEvent`, evidence snapshot, idempotent open report, optional atomic report-and-block |
| Verification (contact) | **READY** | OTP challenge with encrypted `delivery_code`, expiry/used/attempts-exhausted handling, throttled, async delivery. `verification_required` surfaced in `/me` and login payload |
| Account deactivation | **READY** | `POST /account/deactivation` (reversible), confirmation-gated, revokes sessions + devices; `POST /auth/password/reactivation` restores |
| Account deletion (brand closure) | **READY** | `DELETE /me` confirmation-gated, atomic: membership tombstoned, profile discarded+anonymized, matches ended, likes/passes discarded, location hard-deleted, async media purge job |
| Data export | **ABSENT** | No export service, job, endpoint, or reference anywhere |
| Admin / moderation | **PARTIAL** | `Admin::ReportQueue/ReportDetail/TransitionReport`, `SuspendProfile`, `ModerateProfilePhoto`, `AdminUser` + per-brand assignment auth. **No appeal/support lifecycle**; no admin UI in this repo |
| Brand isolation | **READY** | Host-resolved brand, `brand.profiles` / `where(brand:)` scoping throughout, brand-scoped sessions, `SessionAuthenticator` rejects wrong-brand tokens, `CapabilityKey` reserves the brand slug segment |
| Geocoding | **ABSENT (by design)** | No geocoding endpoint. `GET /places` navigates a DB `Place` catalog (ZA). If the SPA calls Nominatim directly, it is bypassing the intended catalog |

---

## 4. Frontend-finding validation

| Frontend finding | Verdict | Evidence |
|---|---|---|
| Mutual matches backed by a real endpoint | **CONFIRMED (correct)** | `GET /matches` → `Matching::MatchList`, cursor-paginated, availability + block filtered |
| No backend endpoint for incoming likes / "Liked you" | **CONFIRMED BACKEND GAP** | Routes have only `POST /profiles/:id/likes`. No list action on `LikesController`. `likes` table has `index_likes_on_liked_profile_id` ready |
| No backend endpoint for outgoing likes / "You liked" | **CONFIRMED BACKEND GAP** | Same — no read path; `index_likes_on_liker_profile_id` exists |
| Discover fetches a small curated daily set, filters client-side | **CONFIRMED (correct) + PARTIAL BACKEND SUPPORT** | DateZA default surface is `discovery.curated_daily`, a `:daily_batch` capped at 10. `Discovery#daily_selection_result` calls `FacetFilter.parse` (validation) but never `FacetFilter.apply`. Server-side filtering genuinely does not happen on this surface |
| Location-confirmation gating remembered in `localStorage` | **FRONTEND-ONLY ISSUE + PARTIAL BACKEND SUPPORT** | Backend has no "confirmed" concept anymore (persistent-location policy, `EligibilityPolicy::PERSISTENT_LOCATION`, no freshness). `OwnerSerializer#location_payload` returns `{configured: true/false}` and a place label when present — enough for a real gate, but there is no dedicated `GET /profile/location` |
| Saved dating location does not reliably read back into Edit Profile | **PARTIAL BACKEND SUPPORT** | Place selections DO read back (`GET /profile` → `location.place.name` / `display_path`). Raw device-GPS locations read back as `{configured: true}` only — **no coordinates or accuracy returned by any GET**. `GET /profile/configuration` returns the catalog, not the current selection |
| Suburb geocoding calls Nominatim directly from the browser | **CONTRACT EXISTS — FRONTEND NOT USING IT** | `GET /places?parent_id=` navigates the `Place` hierarchy (ZA), `PUT /profile/place` resolves the centroid server-side. A geocoding proxy would still be a privacy improvement but is not required |
| Notifications endpoint exists, only a limited type active | **CONFIRMED (correct)** | `Notifications::Types::DEFINITIONS` = `{ "dateza.welcome" => ... }`. One type |
| Likes/Matches/Messages/Activity notification filters have no backend taxonomy | **CONFIRMED BACKEND GAP** | No notification types or event publishers for any of these. `EventPublisher` has exactly one method: `membership_registered!` |
| Push and email preference control absent | **CONFIRMED BACKEND GAP** | `NotificationPreference` model exists and is read by `MaterializeEvent`, but there is **no route** to GET or PATCH it. Default (nil preference) = all channels allowed |
| Notification items lack destination metadata to navigate | **CONFIRMED (correct)** | `Presenter` emits `{id, type, title, body, payload, read_at, created_at}`. `payload` is `{}` for `dateza.welcome`. No actor/subject/target refs |
| Safety centre backend supports block/unblock/report/list blocks | **CONTRACT EXISTS — FRONTEND NOT USING IT** | All four endpoints exist and are correct. The broken entry point is frontend-only |
| Find is the strongest authenticated page | **CONFIRMED (correct)** | `Matching::Find::Search` is the most complete loop: durable daily ledger, row locks, exclusions, filters, exhaustion state, reset time |
| "Download my data" unavailable | **CONFIRMED BACKEND GAP** | No export capability exists |
| Safari / cross-site session issue | **CONFIRMED ARCHITECTURAL RISK / NOT VERIFIED live** | See §7 P0-1 |
| Message-level reporting | **FRONTEND AUDIT WAS INCORRECT (if it assumed absent)** | `POST /reports` with `target_type: "message"` is fully implemented (`Trust::ReportTargets::MessageTarget`), survives sender block/suspension, snapshots an evidence body |

---

## 5. API / contract gaps

| # | Endpoint / capability | Current state | Consumer | Why needed | Reusable D8N abstraction | Priority | Compat notes |
|---|---|---|---|---|---|---|---|
| G1 | `GET /api/v1/likes/incoming` (Liked you) | Absent | Likes tab | Primary nav destination | New action on `LikesController` + `Matching::IncomingLikes` service reusing `VisibilityScope` + `BlockPolicy` + `Matching::Cursor` | **P0** | Additive |
| G2 | `GET /api/v1/likes/outgoing` (You liked) | Absent | Likes tab | Same | Same service family; exclude where a Match now exists | **P0** | Additive |
| G3 | Notification event publishers + types for `match_created`, `message_received`, `opener_received`, `opener_reply` | Absent | Notifications tab, badges | Tab filters have nothing to query; no re-engagement signal | `Notifications::EventPublisher` + `Types::DEFINITIONS` + brand `NotificationConfiguration.event_plans`; payload must carry a navigable target ref | **P0/P1** | Additive; payload schema versioned via `allowed_payload_keys` |
| G4 | `GET/PATCH /api/v1/notifications/preferences` | Model exists, no route | Settings | Users cannot control email/push | `NotificationPreference` + a thin controller; `MaterializeEvent` already consumes it | **P1** | Additive |
| G5 | `GET /api/v1/profile/location` | Absent | Edit Profile | Read back saved dating location authoritatively (coords/accuracy/place/source) | Return the same shape `ProfileLocationsController#location_payload` builds, plus `place` | **P1** | Additive |
| G6 | Server-side Discover filtering on the daily surface | Parsed, not applied | Discover | Client-side filtering over 10 rows is a poor contract | Apply `FacetFilter` (and age/distance) at `rank_daily_selection` time, or expose a filterable browse surface for DateZA discovery | **P1** | Behaviour change — currently silent no-op |
| G7 | `POST /api/v1/matches/:id/unmatch` | Absent (only block ends a match) | Chats / Matches | Users expect to leave without "blocking" | New `Matching::Unmatch` transitioning Match→ended + closing conversation; capability `match.relationship.unmatch` is already catalogued as planned | **P1** | Additive |
| G8 | Message send idempotency (`client_token`) | Absent (documented) | Chat | Network retry creates duplicate messages | Add nullable `client_token` + partial unique index on `Message`; `SendMessage` upsert | **P2** | Additive column |
| G9 | Data export | Absent | Settings / POPIA | Legal | New `Accounts::ExportPersonalData` job → signed download; reuse media signed-URL pattern | **P1 (Product/Legal)** | Additive |
| G10 | Geocoding proxy `GET /api/v1/geocode?q=` | Absent | Location picker (if free-text suburb search is wanted) | Stop sending user suburb queries + IP to Nominatim | New `Geography::Geocode` with server-side provider call | **P2** | Additive; see §8 |

---

## 6. Data-integrity risks

| Risk | Assessment | Evidence |
|---|---|---|
| Duplicate likes | **Prevented** | `idx_likes_active_pair` unique partial (`deleted_at IS NULL`); `LikeProfile` locks both profiles, re-checks existing, `RecordNotUnique`-safe |
| Duplicate matches | **Prevented** | `idx_matches_active_pair` unique partial (`deleted_at IS NULL AND status = 0`); `Match.find_or_create_by!` on canonical pair under row locks |
| Duplicate openers | **Prevented** | Unique `(sender, recipient)` index; `SendHook` rescues `RecordNotUnique` → `already_hooked` |
| Duplicate open reports | **Prevented** | `Report.open_reports` unique constraint; `FileReport.find_or_file` rescue |
| Duplicate messages | **Possible (accepted for beta)** | `SendMessage` has no idempotency key; documented. G8 |
| Race: two concurrent opener replies both unlock | **Prevented** | `Hook.kept.lock.find_by(...)`, loser sees non-live hook |
| Race: like both directions simultaneously → two matches | **Prevented** | Canonical pair ordering + `Profile ... .order(:id).lock` |
| Orphan media | **Handled** | `Media::ProcessProfilePhotoJob` async; `Media::PurgeProfileMediaJob` on closure; `verify_uploaded_object!` reconciles blob truth; unattached blobs are Active Storage's normal purge concern |
| Inconsistent block state across surfaces | **Low** | `BlockPolicy` applied in discovery, Find, matches, conversations, messages, profile detail, openers. **Only gap: no Likes list surface to enforce on** (G1/G2 must include it from day one) |
| Stale candidate pool (daily batch) | **By design, may read as broken** | `StableDailySelection#deliver` re-filters the frozen 10 by current eligibility on every read and never tops up. After liking/passing/blocking, the Discover tab shrinks toward 0 until the JHB-midnight reset |
| Inconsistent location state | **Low** | One kept `ProfileLocation` per profile (`find_or_initialize_by(profile:)`); `CurrentPlace` and `CurrentLocation` write the same row under `profile.with_lock` |
| Notification orphaning (blocked/deleted actor) | **N/A today** | Only `dateza.welcome` exists, no actor. Becomes a real concern when G3 lands — payloads must tolerate a since-blocked/-deleted actor |
| Account-deletion residue | **Intentional** | Closure retains `User`/credentials/identifiers (cross-brand), and conversations/messages/blocks/reports/security events (safety). Location hard-deleted, profile anonymized. Platform-wide identity erasure is a documented future capability |

---

## 7. Safety / security findings

### P0

**P0-1 — Cross-site session cookie will not persist on Safari / iOS as deployed.**
*Evidence:* `config/initializers/cors.rb` default dev origins include `https://dateza.vercel.app`; `docs/FOUNDER-HQ/deploy-commands.txt` deploys the API to `staging-api.d8n.tech`. `Identity::BrowserSession.cookie_options` sets `same_site: :none, secure: true` in production, path `/api/v1`, HttpOnly. `dateza.vercel.app` and `d8n.tech` are different registrable domains, so the session cookie is a third-party cookie in the browser context that matters.
*Impact:* Safari desktop and iOS Safari block third-party cookies by default; login appears to succeed then every subsequent request is unauthenticated. Firefox Total Cookie Protection partitions it (also broken). Chrome currently works.
*Path to exploit / failure:* user logs in on iPhone Safari → navigates → "session expired" loop.
*Fix:* serve the API first-party to the SPA (`api.dateza.co.za` under `dateza.co.za`), or a first-party reverse proxy, or ship the already-supported Bearer-token mode for browsers (`session_mode` other than `browser` returns `{token, token_type: "Bearer"}`) with XSS-conscious storage.
*Status:* **SOURCE VERIFIED** architecture; browser behaviour **NOT VERIFIED** live — must be confirmed on real devices before launch.

**P0-2 — No automated photo content moderation + immediate visibility.**
*Evidence:* `Media::PhotoPolicy::IMMEDIATE = (status: :pending_review, visibility: :visible)` for DateZA (`brands/dateza.rb` → `initial_visibility: :immediate`). Moderation is only `Api::V1::Admin::ProfilePhotosController#update` (manual). `ImageProcessor` does file-safety only (magic bytes, dimensions, EXIF strip, re-encode) — no NSFW/face/quality classification.
*Impact:* any image (screenshot, non-face, explicit) is shown as a real dating photo — including as the primary — until a human happens to review it. The staging "voice-recorder screenshot as primary photo" is consistent with this being the actual policy, not seed noise.
*Fix (choose one for V1):* flip DateZA to `moderate_first`; or integrate an automated safety/face check gating the `visible` transition; or require primary-photo review before publication. B3.

### P1

**P1-1 — Client can submit raw coordinates via `PUT /profile/location`.**
*Evidence:* `ProfileLocationsController#location_params` permits `:latitude, :longitude, :accuracy_meters, :captured_at` directly. DateZA also enables `profile.location.place_selection`.
*Impact:* precision and provenance of the stored dating location are client-controlled on that path (the `place` path is server-resolved and safe). Not a disclosure bug — coords are never returned publicly — but it undermines the "chosen area, not precise pin" product intent and lets a client store a precise home coordinate.
*Fix:* for brands with `place_selection`, either disable the raw-coords path or snap/round server-side and stamp `source`.

**P1-2 — No rate limit on opener send beyond the rolling daily allowance; no generic limiter on `POST /profiles/:id/opener`.**
*Evidence:* `OpenersController` has no `enforce_rate_limit!`. `SendHook#enforce_rate_limit!` enforces only the 10/24h product allowance.
*Impact:* up to 10 openers/day is the only ceiling; combined with catalog-only text this is low-risk, but there is no burst guard.
*Fix:* add `enforce_rate_limit!(:hook_send)` (a burst rule) to the generic policy.

**P1-3 — No moderation appeal / support lifecycle.**
*Evidence:* `Admin::TransitionReport` and `SuspendProfile` exist; there is no user-facing appeal endpoint or state.
*Impact:* a suspended user has no in-product recourse path. Acceptable for a closed beta with a manual support inbox; must be a known Product gap.

### P2

- **P2-1** Find distance filter runs `EligibilityScope::DISTANCE_SQL <= ?` (full haversine) with **no bounding-box pre-filter** (`find/filter.rb#apply_distance`), unlike `EligibilityScope#within_viewer_distance` which does pre-filter. Fine at beta pool sizes; a scale risk. (Also §9.)
- **P2-2** `FacetFilter.online_user_ids` and `StatusFields` presence both read `Session.active` with a 10-minute `last_used_at` window — every authenticated request updates `last_used_at` (`SessionAuthenticator`), so "online" really means "made any API call in 10 min". Acceptable, but not true presence.
- **P2-3** `me#show` returns `Current.user.id` (integer, sequential) and `Current.session.id`. Internal sequential IDs in a payload; low value to an attacker (everything else is UUID `public_id`), but prefer not exposing them.

### Clean

- Brakeman: **0 warnings** (42 controllers, 48 models).
- bundler-audit: **no vulnerabilities** (advisory DB updated to 2026-08-23).
- SQL: all dynamic SQL uses parameter binding or squished constant fragments over trusted columns; no interpolation of user input found.
- Mass assignment: every controller uses `params.permit` with explicit allowlists; profile writes go through `FieldPolicy.writable_profile_fields`.
- IDOR: every resource is resolved by `public_id` (UUID) scoped to `brand` + the authenticated viewer; reporting/messaging/opener resolvers derive the responsible profile server-side and return a single neutral `*_unavailable` for unknown/cross-brand/forbidden.
- CSRF: `verify_browser_session_csrf!` for cookie-auth unsafe methods, HMAC token bound to session digest, constant-time compare.

---

## 8. Privacy findings

### Personal data inventory (DateZA)

Account identity (`User`, `IdentityIdentifier` email/phone — **cross-brand**), `Credential` (bcrypt), `OtpChallenge` (encrypted `delivery_code`), `Profile` (display name, bio, birthdate, gender, pronouns, occupation/employer/school, height, body type, children count, languages, smoking/drinking/fitness), `ProfilePreference` (age range, interested-in, distance, intent), `ProfileOptionSelection` / `PromptAnswer` (lifestyle + free-text answers), `ProfilePhoto` + R2 blobs, `ProfileLocation` (**precise lat/long, 7-dp**, accuracy, source, optional `place`), `Like`, `ProfilePass`, `Match`, `Hook`/`ProfileOpener`, `Conversation`/`Message` (plaintext bodies), `Report` (+ evidence snapshot incl. message body), `ProfileBlock`, `Session` (IP, user-agent, `last_used_at`), `SecurityEvent` / `PasswordAudit` (IP, user-agent, outcome — content-free), `NotificationDelivery` (recipient email/device), `DeviceRegistration`.

### Findings

| Finding | Assessment |
|---|---|
| Coordinates in public payloads | **Safe** — `PublicSerializer` emits only `{city, country_code, precision: "approximate"}`; `StatusFields` emits `distance_km` rounded and floored to `MIN_DISTANCE_KM`. No serializer exposes lat/long |
| Location on account closure | **Good** — `ProfileLocation.where(profile:).delete_all` (hard delete, not soft) in `CloseAccount` |
| Location freshness / multi-device | Persistent policy: one row, last write wins across devices; no history kept. Fine |
| Third-party geocoding | Backend does **not** call any geocoder. If the SPA calls Nominatim, user suburb text + IP go to OSM's servers with no D8N control. A proxy (G10) would fix this; **specify:** `GET /geocode?q=&country=za`, cache by normalized `(q, country)` for 30 days, per-user + per-IP rate limit, hard `country=za` filter, return only `{place_label, lat, lng, precision}` rounded to ~3 dp, never store the raw query against the user, never log the query with the IP |
| Data export | **Absent** — no DSAR support. B5 / G9 |
| Data correction | Partial — profile fields editable; no correction path for identifiers, audit records |
| Right to erasure | Brand-level closure is thorough and immediate; **platform-level erasure of `User`/identifiers is not implemented** (documented as future). For a single-brand launch this is close to sufficient; document the retention position |
| Message retention | Indefinite; retained through closure of one party (safety rationale). Needs a stated retention period for POPIA |
| Audit logs | `SecurityEvent` / `PasswordAudit` carry IP + user-agent + outcome, **content-free by design** (verified in `FileReport.record_event`, `RateLimitable.log_rate_limited`). Retention period undefined |
| Cross-border infrastructure | R2 buckets + `staging-api.d8n.tech`; region not asserted in config. Resend (email), Twilio (SMS) are US processors. Needs a processor register (Product/Legal, not backend) |
| Backups | Out of scope of the repo; must be covered operationally |

---

## 9. Performance findings (evidence-backed only)

| Finding | Evidence | Severity |
|---|---|---|
| Find distance filter: full haversine per candidate row, no bounding box | `matching/find/filter.rb#apply_distance` — `scope.where("#{DISTANCE_SQL} <= ?", km)` with no lat/long range pre-filter. `EligibilityScope` (discovery) does pre-filter. `profile_locations` has `idx_profile_locations_active_coordinates (brand_id, latitude, longitude)` but a functional haversine can't use it | Low now, scales poorly |
| Daily-batch candidate pool scan bounded at 500 | `DatezaV1::DAILY_SELECTION_POOL_LIMIT = 500` then in-Ruby scoring/sort of up to 500 profiles once per member per day, cached in `DiscoveryAllocation` | Acceptable — bounded, cached, off the hot path |
| Compatibility recomputed per Find card | `FindController#index` calls `compatibility.for_eligible_pair(candidate:).public_payload` per profile (max 10). `DatezaV1#values_for` reads option selections from the already-`includes`-loaded association | Fine at limit 10 |
| N+1 in list endpoints | Discovery / Find / Matches / Conversations all use `.includes` for `brand`, option selections + options + groups, and `profile_photos.display_image_attachment.blob`. `StatusFields` batches verification (1 query), presence (1), distances (1). `ConversationList` uses `DISTINCT ON` for last messages | Good |
| `Session.active` written on every authenticated request | `SessionAuthenticator#call` → `session.update!(last_used_at:)` — one write per request | Standard; watch under load |
| No unbounded result sets found | Every list action normalizes `limit` (≤50, Find ≤10) and is cursor-paginated. Notifications inbox hard-capped at 50 | Good |
| Async work correctly queued | Media processing/purge, notification delivery, OTP delivery all `perform_later` with idempotency keys; `MaterializeEvent` is lock + `processed_at` guarded with `last_error_code` capture | Good; no dead-letter/DLQ strategy visible for Solid Queue — confirm operationally |

No profiling was run under volume — these are static observations.

---

## 10. Backend "Coming Soon" inventory

| Capability | Classification | Recommendation for V1 |
|---|---|---|
| Likes list (incoming / outgoing) | Partially built (data + indexes, no read path) | **Build now** (B1) |
| Notification types beyond welcome | Genuinely absent | **Build minimum set now** (match, message, opener) or **hide the filter tabs** (B4) |
| Notification preferences API | Model exists, no endpoint | Build now if push/email ship; else defer + default-on |
| Data export | Genuinely absent | **Build now** for POPIA (B5) or gate launch to users who accept "no self-service export yet" |
| Unmatch | Genuinely absent (capability catalogued as planned) | Should build now — users will expect it; block is too heavy a hammer |
| Message idempotency key | Genuinely absent (documented beta trade-off) | Defer to early beta |
| Mute / archive / leave / delete conversation | Genuinely absent | Defer; not blocking a coherent core loop |
| Attachments / voice / video / reactions / read receipts / typing | Genuinely absent | Defer all |
| Server-side Discover filtering | Partially built (parse only) | Build now OR make the daily-set-only contract explicit to the frontend and accept client filtering for V1 |
| Geocoding proxy | Genuinely absent | Defer if the `Place` catalog UX is acceptable; build if free-text suburb search is required |
| Moderation appeal lifecycle | Genuinely absent | Defer with a manual support process; document |
| Platform-wide identity erasure | Genuinely absent (documented) | Defer; document retention |
| RealMe / identity verification | **Genuinely absent — do not claim it exists.** Only contact-OTP verification exists (`verify.contact.email/phone`). `me#show` deliberately badges only `verification: { contact: { verified } }` | Defer |

---

## 11. P0 / P1 / P2 work plan

### Backend — P0
1. **Likes list endpoints** (incoming + outgoing), block/visibility filtered, cursor-paginated. (G1, G2)
2. **Session topology fix** — decide first-party API domain or documented Bearer mode for browsers; whichever, verify on real Safari/iOS. (P0-1)
3. **Photo gate decision + enforcement** — `moderate_first` flip or automated pre-`visible` check. (P0-2)

### Backend — P1
4. Notification events + types for `match_created`, `message_received`, `opener_received`, `opener_reply`, each with a navigable target ref in `payload`. (G3)
5. `GET /profile/location` authoritative read-back (coords/accuracy/source/place). (G5)
6. Apply server-side filtering (facets + age + distance) to the DateZA daily Discover surface, or expose a filterable browse surface. (G6)
7. `POST /matches/:id/unmatch`. (G7)
8. Notification preferences endpoint. (G4)
9. Opener send burst rate limit. (P1-2)
10. Constrain / round the raw-coords location path for place-selection brands. (P1-1)

### Backend — P2
11. Message `client_token` idempotency. (G8)
12. Bounding-box pre-filter in Find distance. (P2-1)
13. Stop returning sequential `user_id` / `session_id` in `me#show`. (P2-3)

### Frontend — (not backend tickets)
- Wire the existing Safety centre endpoints (block/unblock/report/list) — contract already exists.
- Use `GET /places` + `PUT /profile/place` instead of direct Nominatim.
- Consume `Hooks::OpenerStateDecorator` state on discovery cards for "opener already sent".
- Handle the daily-Discover-shrinks-to-zero UX (empty state + reset time from `selection.refreshes_at`).
- Decide: hide notification filter tabs until G3 ships.

### Product / Legal
- Data export scope + retention periods (messages, audit logs, location). (G9, §8)
- Processor register (R2 region, Resend, Twilio) + cross-border transfer basis.
- Moderation appeal / support process (manual acceptable for closed beta).
- Photo policy decision owner (moderate-first vs automated check vs review-primary).

### Cross-cutting
- Confirm Solid Queue failure/retry/DLQ handling operationally before launch.
- Real-device auth matrix test (see §14).

---

## 12. Recommended backend ticket order (next 8)

> Ordered for execution. Each unblocks the next or a frontend workstream.

### T1 — Incoming & outgoing Likes list capability
- **Priority:** P0
- **Scope:** `GET /api/v1/likes/incoming`, `GET /api/v1/likes/outgoing`. Incoming = profiles who liked the viewer and where no active Match exists and neither blocks the other and the liker is still visible. Outgoing = profiles the viewer liked, same filters. Cursor-paginated, `PublicSerializer` payloads + `StatusFields`.
- **Files/domains:** `config/routes.rb`, `app/controllers/api/v1/likes_controller.rb`, new `domains/matching/incoming_likes.rb` + `outgoing_likes.rb` (reuse `VisibilityScope`, `BlockPolicy`, `Matching::Cursor`), OpenAPI doc, `domains/d8n/platform/capabilities/match.rb` (new `match.interaction.like.list` capability + enable for DateZA).
- **Implementation intent:** thin services mirroring `MatchList`'s shape; base scope = `Like.kept.where(brand:, liked_profile: viewer)` (or `liker_profile:`), joined to `VisibilityScope.call(brand:, viewer:)` to inherit brand/active/age/block rules, `where.not` an active Match exists.
- **Tests:** brand isolation; block either direction hides the row; matched pair excluded; suspended/closed liker excluded; pagination stable; cross-brand like id 404; unauthenticated 401.
- **Acceptance:** frontend can render both Likes sub-tabs with real, block-safe, paginated data.
- **Dependencies:** none.
- **Frontend can proceed independently:** yes, against the documented contract once merged.

### T2 — Browser session topology / Bearer-for-web decision
- **Priority:** P0
- **Scope:** Either (a) document + configure a first-party API host under the DateZA site domain and update `D8N_CORS_ORIGINS` + `BrandDomain` records + cookie domain, or (b) formally support `session_mode: "web_token"` returning a Bearer token for the SPA and document the storage/XSS guidance. Pick one.
- **Files/domains:** `config/initializers/cors.rb`, `domains/identity/browser_session.rb`, `app/controllers/api/v1/auth/passwords_controller.rb` (`session_payload`), deploy config, `BrandDomain` seed.
- **Implementation intent:** no new crypto; if (a), the existing cookie code already works same-site; if (b), the Bearer path already exists — just make it a first-class, documented mode and confirm CSRF exemption is correct for token auth.
- **Tests:** cookie set with correct attributes for the chosen topology; token mode returns `token` + `token_type`; CSRF not required for Bearer; `SessionAuthenticator` unchanged.
- **Acceptance:** logged-in session persists across navigation on Chrome desktop, Safari desktop, iOS Safari, iOS Chrome, Android Chrome — verified on real devices.
- **Dependencies:** infra decision (Product + DevOps).
- **Frontend can proceed independently:** partially — needs the final contract.

### T3 — Profile photo publication gate
- **Priority:** P0
- **Scope:** Prevent unreviewed images from being shown as dating photos. Recommended: add an automated safety check (aspect/quality + NSFW classifier hook) in `Media::ProcessProfilePhotoJob` that must pass before `visibility` flips to `visible`; keep `IMMEDIATE` only for "passed automated check". Fallback: switch DateZA `initial_visibility` to `:moderate_first`.
- **Files/domains:** `domains/media/photo_policy.rb`, `domains/media/image_processor.rb` or a new `domains/media/safety_check.rb`, `app/jobs/media/process_profile_photo_job.rb`, `domains/d8n/platform/brands/dateza.rb`.
- **Implementation intent:** new terminal states already exist (`pending_review`/`approved`/`rejected`, `visible`/`hidden`); wire the check to gate the transition. If no classifier is available for V1, ship the `moderate_first` flip (one-line config) + ensure the admin queue is staffed.
- **Tests:** photo not `deliverable?` until check passes; rejected photo never in `PublicSerializer`; `publication_eligible?` semantics preserved; owner still sees their own pending upload.
- **Acceptance:** no image reaches another user's view before either an automated pass or a human approval.
- **Dependencies:** classifier provider decision (or accept moderate-first).
- **Frontend can proceed independently:** yes — the photo payload shape is unchanged.

### T4 — Core notification events
- **Priority:** P1
- **Scope:** Add event publishers + types for `match_created`, `message_received` (debounced per conversation), `opener_received`, `opener_reply`. Each `payload` carries `{ target: { type, public_id } }` for navigation and an actor `public_id`. Presenter tolerates a since-blocked/-deleted actor (fall back to generic copy).
- **Files/domains:** `domains/notifications/event_publisher.rb`, `domains/notifications/types.rb`, `domains/notifications/presenter.rb`, `domains/d8n/platform/brands/dateza.rb` (`NotificationConfiguration.event_plans` + `allowed_payload_keys`), call sites in `Matching::LikeProfile`, `Messaging::SendMessage`, `Hooks::SendHook`, `Hooks::ReplyToHook`.
- **Implementation intent:** reuse `NotificationEvent` + `MaterializeEvent` (idempotency, channel gating, delivery fan-out already built). Only new work is publishers + type definitions + payload validation keys.
- **Tests:** each event materializes exactly one notification (idempotent on retry); brand-scoped; blocked actor → generic copy, still navigable or safely dropped; `unread_count` reflects new events; mark-read works.
- **Acceptance:** Notifications tab filters (Matches / Messages / Activity) have real data; badges are accurate.
- **Dependencies:** T1 not required but complementary.
- **Frontend can proceed independently:** yes, against the payload schema.

### T5 — `GET /api/v1/profile/location`
- **Priority:** P1
- **Scope:** Authoritative read of the viewer's saved dating location: `{ configured, source, accuracy_meters, captured_at, place: {id, name, display_path} | null, coordinates: {lat, lng} | null }` — coordinates included only for the owner.
- **Files/domains:** `config/routes.rb`, `app/controllers/api/v1/profile_locations_controller.rb` (`#show`), reuse `Profiles::CurrentLocation`.
- **Implementation intent:** trivial read; return the same fields the `PUT` responses build plus `place` and owner-only `coordinates`.
- **Tests:** returns `configured: false` when absent/deleted; place fields present for place-sourced; coordinates only for owner; 403 without a profile.
- **Acceptance:** Edit Profile reliably shows the saved location without relying on `localStorage` or the last `PUT` response.
- **Dependencies:** none.
- **Frontend can proceed independently:** yes.

### T6 — Server-side Discover filtering for DateZA
- **Priority:** P1
- **Scope:** Make `verified`, option-group facets, activity, age, and distance actually filter the DateZA daily Discover result. Decide: filter the frozen daily set on read (simple, keeps determinism) vs. add a filterable browse surface for Discover (more work, better UX).
- **Files/domains:** `domains/matching/discovery.rb` (`daily_selection_result`), `domains/matching/stable_daily_selection.rb` (`deliver`), `domains/matching/facet_filter.rb`, possibly `domains/d8n/platform/brands/dateza.rb` (new surface).
- **Implementation intent:** cheapest correct fix — apply `FacetFilter.apply` + age/distance predicates to the `currently_eligible_ids` re-check query in `deliver`, so the returned subset honours filters while the underlying allocation stays stable.
- **Tests:** `?verified=true` removes unverified from the daily result; invalid facet still 422; distance filter respects persistent location; empty result when filters exclude all 10.
- **Acceptance:** frontend stops filtering client-side; filter params have observable effect.
- **Dependencies:** none.
- **Frontend can proceed independently:** yes — params already sent, just start working.

### T7 — Unmatch
- **Priority:** P1
- **Scope:** `POST /api/v1/matches/:id/unmatch` — viewer ends an active Match; conversation becomes inaccessible; no like resurrection; idempotent.
- **Files/domains:** `config/routes.rb`, `app/controllers/api/v1/matches_controller.rb`, new `domains/matching/unmatch.rb`, `domains/d8n/platform/capabilities/match.rb` (promote the planned `match.relationship.unmatch`), enable for DateZA.
- **Implementation intent:** transaction + row locks mirroring `BlockProfile.remove_positive_relationships!` minus the block row: Match → `ended`, delete both-direction likes, leave `Conversation` (becomes unreachable via `MatchAccess`'s `status_active` requirement).
- **Tests:** only a participant can unmatch; ended match 404s on message send/list; idempotent; not reversible via like; brand-scoped.
- **Acceptance:** users can leave a match without blocking.
- **Dependencies:** none.
- **Frontend can proceed independently:** yes.

### T8 — Notification preferences endpoint
- **Priority:** P1 (P0 if push/email actually ship for V1)
- **Scope:** `GET/PATCH /api/v1/notifications/preferences` → `{ product_email: bool, push: bool }`. Security/transactional email always on (already enforced in the model).
- **Files/domains:** `config/routes.rb`, new `app/controllers/api/v1/notification_preferences_controller.rb`, `NotificationPreference` (add `kept` upsert helper).
- **Implementation intent:** thin controller; `MaterializeEvent` already consumes `Policy.channel_allowed?`.
- **Tests:** default (no row) = all allowed; PATCH creates/updates the kept row; brand + membership scoped; unknown keys rejected.
- **Acceptance:** users can turn off product email/push; delivery respects it.
- **Dependencies:** T4 (otherwise nothing to suppress).
- **Frontend can proceed independently:** yes.

---

## 13. Verification results

| Check | Command | Result |
|---|---|---|
| Full test suite | `RAILS_ENV=test bin/rails test` | **1069 runs, 6513 assertions, 1 failure, 0 errors, 0 skips.** The one failure is a flaky test, not a code defect: `test/domains/media/object_key_test.rb:49` asserts a randomly-generated UUID does not contain the substring `"ada"`; this seed produced UUID `...4ada-b480...`. Object-key PII-safety logic is sound (keys are `brands/<slug>/users/<id>/profiles/<uuid>/photos/<uuid>/...`). Recommend the test assert against actual PII tokens, not arbitrary substrings |
| Contract / OpenAPI tests | `RAILS_ENV=test bin/rails test test/contracts` | **4 runs, 1014 assertions, 0 failures** |
| Lint | `bundle exec rubocop --format simple` | **566 files, no offenses** |
| Static security scan | `bundle exec brakeman -q` | **0 security warnings** (42 controllers, 48 models, 0 errors) |
| Dependency audit | `bundle exec bundler-audit check --update` | **No vulnerabilities found** (advisory DB @ 2026-08-23) |
| Autoload / eager load (test) | `RAILS_ENV=test bin/rails zeitwerk:check` | **"All is good!"** |
| Autoload / eager load (production) | `RAILS_ENV=production bin/rails zeitwerk:check` | Aborts: `KeyError: D8N_AR_ENCRYPTION_PRIMARY_KEY` not set locally. Expected — production keys are Kamal secrets; not a code defect. **NOT VERIFIED** in a production-like env |
| Working tree | `git status --porcelain` / `git diff --check` | Clean / clean |

---

## 14. Final launch recommendation

### **LIMITED PRIVATE BETA** — invite-only, ≤ a few dozen known users, on Chrome/Android, with the Likes and Notifications tabs hidden or labelled, and a manual moderation + support process.

**Not NO-GO:** the hard parts are genuinely done and done well. Auth, sessions (server side), profile, photos (file safety), Find, openers, matches, conversations, messages, blocking, and reporting are real, transactional, brand-isolated, and test-covered. The platform architecture is sound and reuse-first.

**Not CLOSED BETA yet**, because:

1. **Two of the four primary navigation destinations have no backend contract** — Likes entirely, Notifications effectively (one welcome message). A dating product where "who liked me" cannot load is not ready for users who did not agree to test around it.
2. **Session persistence is unverified and architecturally broken for Safari/iOS as deployed.** iPhone is the single most likely device for a South African dating beta. This must be fixed and verified on real hardware.
3. **Photos are shown before any review**, with no automated safety net. One bad image in front of one beta user is a reputational and safety problem.
4. **No data-export path and an undefined retention position** — acceptable to defer only if the beta cohort explicitly consents and the numbers are small.

**Path to CLOSED BETA:** ship T1, T2, T3, and T4 (minimum), verify the real-device auth matrix, and take a Product/Legal decision on export + retention. That is roughly the P0 block plus one P1. Nothing in the architecture needs to change to get there.

**Real-device auth matrix to complete before CLOSED BETA (currently all NOT VERIFIED):**

| Browser | Login persists? |
|---|---|
| Chrome desktop | NOT VERIFIED (expected: yes) |
| Safari desktop | NOT VERIFIED (expected: **no**, third-party cookie) |
| iPhone Safari | NOT VERIFIED (expected: **no**) |
| iPhone Chrome | NOT VERIFIED (expected: **no** — iOS Chrome uses WebKit + same ITP) |
| Android Chrome | NOT VERIFIED (expected: yes) |
