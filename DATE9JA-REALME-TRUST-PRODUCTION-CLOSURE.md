# Date9ja Backend Production Closure — Pass 3

## RealMe + Trust Operational Closure

**Date:** 2026-09-15
**Branch:** `date9ja-parity`
**Prior passes:** Pass 1 (Production Configuration) CLOSED; Pass 2 (Migration Parity) PARITY_ACCEPTED — CUTOVER READY WITH EXPLICIT OPERATOR STEPS. Neither reopened — no regression was found in either area.

---

# Executive Summary

The existing D8N RealMe and Trust architecture was already correct, coherent, and internally non-contradictory. This pass's job was to prove that, not to redesign it — and the audit confirms it holds up under direct testing: two genuinely independent thresholds (a single approved RealMe method unlocks messaging; all three plus a confirmed email earns the public badge), zero automatic negative trust scoring, zero coupling between the RealMe and Trust systems, and no path by which email or phone verification can produce a false RealMe badge.

Three real, concrete problems were found and fixed, none requiring a redesign:

1. **Stale OpenAPI contract** — 7 live RealMe/Trust Score routes were entirely undocumented, and the documented `/api/v1/me` response schema was missing the `realme_assertions`/`realme_badge` fields altogether. This is the most likely root cause of the frontend contradiction this pass was asked to investigate (see below) — a client generated from the stale spec would not know these fields exist.
2. **Test-environment provider leakage** (identified in Pass 2, fixed here) — no `.env.test` existed, so a developer's local `.env` (real Resend/Twilio/OpenAI credentials, production-shaped CORS) silently governed `bin/rails test`. Fixed with a new, git-tracked, secret-free `.env.test`.
3. **Two test coverage gaps** — no test exercised the full live submission→moderation→gate/badge path end-to-end (every existing test used a pre-seeded imported assertion), and no test proved an admin without the moderation capability is rejected. Both closed.

A minor, repeated doc-citation bug (5 files citing "ADR 0032" — actually an unrelated AI-provider ADR — for the RealMe badge/moderation rule, which is really ADR 0034) was also fixed.

No messaging-gate, badge, or trust-scoring **behavior** changed. Full suite: 2,384 runs / 1 failure / 0 errors — the single failure is the same pre-existing, independently-confirmed DateZA-only welcome-email test from Pass 2, unrelated to RealMe/Trust.

---

# Canonical RealMe Contract

Two deliberately distinct thresholds exist, evaluated by two deliberately distinct pieces of code, and this pass proved (via a new end-to-end test) that they are genuinely independent — approving one RealMe check unlocks messaging without flipping the badge:

| Concept | Code | Rule | ADR |
|---|---|---|---|
| **Messaging eligibility** (Date9ja) | `Identity::InteractionAccess.message_send_allowed?` | ANY ONE approved, same-user, same-brand `VerificationAssertion` with `check_type` in `{selfie, video, liveness, government_id, gov_id}` (phone counts too, but Date9ja has phone verification disabled — see `phone_verification_enabled?`) | ADR 0031 |
| **RealMe badge** (public "it's really them" signal) | `Identity::RealmeBadge` | Confirmed email AND approved selfie AND approved video AND approved government_id — **all three, no partial badge** | ADR 0034 |

Email verification alone never satisfies either. Phone verification alone never satisfies the badge (and Date9ja has it disabled entirely, so it never satisfies messaging either). A rejected, pending, resubmission-requested, cross-user, or cross-brand assertion satisfies neither.

The messaging-gate 403 response is deliberately opaque (`{"error":"realme_verification_required"}`, no method/evidence detail) — this is an intentional ADR 0031 decision, not an oversight: the client is expected to already hold (or fetch) the detailed per-check-type state from `GET /api/v1/me`'s `realme_assertions` + `realme_badge` fields, and use the 403 purely as a signal to open the verification-method picker. This satisfies the "backend exposes enough canonical state for frontend nudges without duplicating policy logic" requirement — the 403 is a trigger, `/me` is the state.

---

# Messaging Eligibility Matrix (Date9ja)

| State | Browse | Like | Match | Start conversation | Send message | RealMe badge |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| No verification at all | ✅ | ✅ | ✅ | ✅ | ❌ (`realme_verification_required`) | ❌ |
| Email verified only | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Phone verified only | ✅ | ✅ | ✅ | ✅ | ❌ *(Date9ja has phone verification disabled — this state cannot occur in practice; if re-enabled per-brand, phone alone still does not satisfy the badge)* | ❌ |
| One selfie approved | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| One video/liveness approved | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| One government ID approved | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Partial RealMe (1–2 of 3 approved) | ✅ | ✅ | ✅ | ✅ | ✅ *(any one suffices)* | ❌ |
| Full RealMe (all 3 approved + confirmed email) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Pending moderation (any check_type) | ✅ | ✅ | ✅ | ✅ | ❌ unless a *different* check_type is already approved | ❌ |
| Rejected verification | ✅ | ✅ | ✅ | ✅ | ❌ unless a *different* check_type is already approved; member may resubmit the rejected check_type immediately | ❌ |

Browse, like, match, start-conversation, and message-history reads have no verification wall on Date9ja at all (ADR 0031 — "no verification wall for registration, onboarding, publication, discovery, profile detail, likes, passes, matches, conversation creation, or message-history reads"). Only creating a **new message** is gated. (DateZA has a separate, unrelated `verified_login_identifier` wall on some interaction surfaces — unchanged by this pass, not applicable to Date9ja.)

---

# RealMe State Model

The canonical states are `Identity::RealmeAssertions::STATUSES`, already exactly matching what the task asked to confirm before inventing anything new — no duplicate state model was created:

- **`pending`** — submitted, awaiting admin decision. (No submission at all = absent from the `realme_assertions` array — this is the `NOT_STARTED` state, represented by omission rather than an explicit enum value, which is correct: there is nothing to show for a check_type never attempted.)
- **`approved`** — terminal, contributes to messaging eligibility and (with the other two) the badge.
- **`rejected`** — terminal for that submission; member may resubmit the same check_type immediately (the one-pending-per-check_type guard only blocks a second *pending* submission, not a fresh one after a terminal decision).
- **`resubmission_requested`** — terminal for that submission, same resubmit-freely behavior as rejected; distinguished from `rejected` so the product can message "try again with a clearer photo" rather than "denied."

`/api/v1/me`, the RealMe endpoints, and the messaging gate all derive from the same underlying `VerificationAssertion` rows — there is exactly one source of truth, not three separate interpretations.

---

# Verification Methods

`Identity::RealmeSubmission::CHECK_TYPES = %w[selfie video government_id]` — no phone, per product rule 3/4. (`liveness` and `gov_id` exist only as *aliases* recognized on read, for legacy/migrated Date9ja assertion rows — new member submissions always write `video` or `government_id`.)

| Method | Content types | Max size | Evidence storage | Processing |
|---|---|---|---|---|
| selfie | image (same allowlist as `ProfilePhoto`) | `ProfilePhoto::MAX_FILE_SIZE` | Private-service R2 object, original only (no public derivative, unlike `ProfilePhoto`) | Cheap magic-byte sniff + real-size bound on attach; no automated face-match (explicitly deferred, ADR 0034) |
| video/liveness | video (same allowlist as `ProfileVideo`) | 50 MB (independent of the profile-video feature toggle — RealMe liveness works even for a brand without profile intro videos) | same | same |
| government_id | image | `ProfilePhoto::MAX_FILE_SIZE` | same | same |

Upload authorization: `Identity::RealmeSubmission.create_intent` mirrors `Profiles::PhotoUpload`/`Profiles::VideoUpload` — D8N allocates a PII-free object key and returns a short-lived (15 minute) direct-to-R2 presigned `PUT`; bytes never pass through the app server. `attach!` then creates a `pending` `VerificationAssertion` (`source_type: "member_submission"`) and attaches the verified blob.

Rate limits: `create_upload` and `create` (attach) are both rate-limited (`enforce_rate_limit!(:media_upload_intent)` / `:media_attach`).

Duplicate/concurrent submissions: exactly one `pending` submission per check_type at a time (`PendingSubmissionExists` → `422 verification_already_pending`); confirmed by existing test coverage and re-confirmed this pass.

Stale/pending submissions: no automatic expiry exists — a pending submission stays pending until an admin decides it. This is consistent with the deliberately manual v1 (ADR 0034); no gap found requiring one.

---

# RealMe Badge Semantics

Confirmed exactly what the badge requires (see Canonical Contract table above) and confirmed this is the **intended, current, correctly-implemented** product contract — not a documentation error, not conflated anywhere in code with "has completed one verification method." `Identity::RealmeBadge.bulk` is the single implementation reused identically by:

- `GET /api/v1/me` (`Identity::RealmeBadge.call`)
- `Profiles::StatusFields` (discovery cards, profile detail) — reused unchanged by `DiscoveryController`, `FindController`, `ProfilesController`, `LikesController`, `HookTonightController`

There is exactly one `realme_badge` boolean computation in the entire codebase. Email verification and phone verification are structurally incapable of producing a false badge — the badge computation reads `VerificationAssertion` rows filtered to `check_type` in `{selfie, video, government_id}` (aliases included) and separately checks `IdentityIdentifier` email verification; neither path can substitute for the other.

---

# End-to-End Verification Results

Proven this pass with a new integration test (`test/controllers/api/v1/date9ja_interaction_verification_test.rb`) exercising the **live** path — every prior test used a pre-seeded imported assertion, none exercised submission→moderation→gate end-to-end:

```
unverified member
→ attempts message send → 403 realme_verification_required
→ Identity::RealmeSubmission.create_intent + attach! (real upload, not a fixture)
→ VerificationAssertion created, status "pending"
→ message send still 403 (pending does not satisfy the gate)
→ Trust::ModerateRealmeVerification approves it
→ GET /api/v1/me: realme_assertions shows "approved" for selfie
→ GET /api/v1/me: realme_badge is FALSE (only 1 of 3 required checks approved — proves
  the messaging gate and the badge are genuinely independent thresholds)
→ message send now succeeds
```

Rejection path (existing coverage, re-confirmed): admin rejects → member's `realme_assertions` shows `rejected` for that check_type → member can immediately submit a **new** upload for the same check_type (the pending-submission guard does not block after a terminal decision) → messaging remains gated if this was the member's only attempt.

Duplicate/concurrent submission: confirmed existing coverage — a second `create_upload`/`attach` for a check_type still `pending` is rejected with `verification_already_pending`.

Race condition (backend-authoritative, no caching/staleness): the same new test proves the gate is evaluated live per-request — a message send that was 403 becomes 200 in the very next request after approval, with no session refresh, token reissue, or cache invalidation step required.

---

# Moderation Results

`Trust::ModerateRealmeVerification` (audited in full):

- **Approve/reject/resubmission_requested** transitions are correctly implemented via a `lock!` + `status == "pending"` guard — clean idempotent-conflict handling.
- **Idempotency**: repeating the same terminal decision on an already-decided assertion is a no-op (`transitioned: false`, same result returned); attempting the *opposite* decision returns `409 realme_verification_conflict`.
- **Cross-brand isolation**: the admin controller's queue and lookup are scoped `.where(brand: Current.brand, source_type: "member_submission", ...)` — an admin for brand A cannot see or decide brand B's queue/assertion; an out-of-brand id lookup returns `404 realme_verification_unavailable`, never a cross-brand row.
- **Audit trail**: every decision writes a `SecurityEvent` (admin id, target user, assertion id, check_type, decision) — queryable, admin-identity-only, never exposed to the member (the member's own `/me` response only ever shows `status`/`reviewed_at`, never who decided or why beyond the optional `note` field which the admin controls).
- **Trust interaction**: `award_trust!` fires only on `approved`, via idempotency-keyed `Trust::AwardEvent`; rejection/resubmission-requested never award or deduct trust automatically — consistent with "no automatic negative scoring anywhere."

Admin authorization (existing + one new test this pass):

- No `admin.realme_verifications.moderate` capability → `403` (new test: `test/controllers/api/v1/admin/realme_verifications_controller_test.rb`).
- No MFA-verified admin session → `403 admin_mfa_required`, enforced centrally in `Admin::BaseController#require_admin_mfa!` (shared by every admin controller, including this one and trust adjustments — not a per-endpoint gap; confirmed via the existing shared MFA test).

---

# Privacy/Security Verification

- **Private storage, no public derivative**: unlike `ProfilePhoto` (which generates a public-servable derivative), RealMe evidence stays original-only on a private-service R2 object — there is nothing to accidentally serve publicly.
- **Authorized access only**: the only reader of evidence bytes besides the submitting member is the admin moderation endpoint.
- **Signed URL expiry**: 5 minutes (`EVIDENCE_URL_EXPIRES_IN`), generated fresh per `GET /api/v1/admin/realme_verifications` request — never cached, never persisted.
- **No evidence exposure on any member-facing serializer**: exhaustively grepped `app/` + `domains/` for `.evidence` — the only non-admin hits are an unrelated `Report#evidence` jsonb field (content reports, a different model entirely). Zero paths where RealMe evidence content or URL reaches a discovery card, profile detail, `/me`, or any other member-facing response.
- **No logging leakage**: no `Rails.logger` call anywhere in the submission or moderation code paths references blob URLs, evidence content, or params.
- **Admin capability + MFA**: confirmed above.

---

# Trust Score Results

Independently audited (separate fork, zero shared code paths with RealMe):

- **Deterministic, pure function**: `Trust::Ledger.score` is recomputed from `TrustEvent`/`TrustAdjustment` rows every call — never a stored, driftable counter. Calling it twice with no new rows returns the same number.
- **Bounded below**: `max(0, events + adjustments)` — never negative. (No enforced upper bound exists; not flagged as a gap since nothing in the product contract calls for one.)
- **Breakdown never leaks moderator identity or free-form notes** — only `event_type`/`reason_code`, a label, points, and whether the entry currently applies (an overturned adjustment stays visible with `applies: false` for transparency).
- **Manual adjustments are deduction-only**: `Trust::RecordAdjustment` only accepts `points.negative?` — there is no manual-positive-adjustment path; all positive points come from automated system events (`Trust::AwardEvent`, the only `TrustEvent.create!` call site in the codebase) triggered by approved RealMe checks, approved photos, publication milestones, etc.
- **Idempotency is real, not just at the DB-unique-constraint level**: `RecordAdjustment` and `AwardEvent` both pre-check `(brand, idempotency_key)` before creating, *and* rescue `ActiveRecord::RecordNotUnique` by returning the existing row — a genuine race (two concurrent requests with the same key) cannot double-apply.
- **Full audit trail**: every manual adjustment records `actor_admin_user` on the row and writes a `SecurityEvent` (`admin.trust_adjustment_applied`), queryable via `GET /api/v1/admin/profiles/{id}/trust_adjustments`.
- **Cross-brand isolation**: `TrustEvent`/`TrustAdjustment` are brand-scoped; a user's Date9ja trust history is invisible to and non-additive with their DateZA/HookUs trust history for the same underlying `User`.
- **Capability + MFA gated**: `admin.trust_adjustments.manage` required; MFA enforced centrally, same as RealMe moderation.

Test run: `test/domains/trust/`, `trust_adjustment_test.rb`, `trust_event_test.rb`, `trust_block_profile_concurrency_test.rb`, `test/jobs/trust/`, `trust_scores_controller_test.rb`, `admin/trust_adjustments_controller_test.rb`, `hq/trust_safety_controller_test.rb`, `hq/trust_safety/`, `verification_verifier_trust_award_test.rb` — **42 runs / 133 assertions / 0 failures / 0 errors**. No gaps found; no new tests were needed (the independence claim is provable from the absence of any cross-reference between the two systems' code, which the audit confirmed directly rather than via an assertion that would just restate the architecture).

---

# RealMe vs Trust Score Contract

- **RealMe = identity assurance** (is this a real person, matching this claimed evidence). **Trust Score = behavioral/reputation assurance** (has this member behaved well). These are structurally independent systems — `grep -rln "Trust::Ledger"` across the entire codebase returns exactly 4 files, none of which is `Identity::InteractionAccess` (the messaging gate) or `Identity::RealmeBadge`. A low Trust Score cannot block messaging (only the RealMe gate can); a high Trust Score cannot substitute for RealMe verification.
- **What RealMe contributes to Trust Score**: an approved RealMe check is one of several `TrustEvent` triggers (alongside approved photos, publication milestones, etc.) — it awards a bounded number of points, it does not set or override the score.
- **A low Trust Score never implies a fake identity** — Date9ja's product policy (Trust Score = reputation, computed independently of identity checks) never conflates the two, and no code path does either.
- **A RealMe badge never implies good behavior** — the badge is silent on Trust Score; a fully RealMe-verified member with zero trust events has a normal baseline score, not an inflated one, and a badge does not shield a member from trust deductions.

---

# Frontend Source-of-Truth Guidance

Investigated the reported contradiction (Settings: "RealMe Verified"; Safety: "Not yet verified / Trust Score 0", same account, same time). This backend repository contains no frontend code, so the actual binding bug cannot be traced here — but the backend was audited end-to-end and found **internally consistent**, which narrows the cause to the frontend:

- There is exactly **one** `realme_badge` boolean in the entire backend, computed by `Identity::RealmeBadge` and surfaced identically everywhere it appears (`/api/v1/me`, discovery, find, profiles, likes, hook_tonight).
- `verified` (contact/email-phone control) and `realme_badge` (full RealMe) are two distinct, clearly and consistently named fields — the backend never conflates them, and no code path derives one from the other.
- There is no separate member-facing "safety" endpoint in the backend distinct from `/api/v1/me` — whatever a "Safety" screen shows is either built from `/me` plus `/api/v1/trust_score`, or from stale/cached client state.
- **Until this pass, the OpenAPI spec did not document `realme_assertions`/`realme_badge` on `/me` at all** — a client whose types were generated from that spec would have had no typed knowledge these fields existed, which is a very plausible mechanism for a "Settings" surface to have been built against some other, looser signal (most likely `identifier.verified`/`verification.*`, which is contact verification, not RealMe) while a "Safety" surface was built correctly against `realme_badge`. This is now fixed (see OpenAPI Changes below), removing the most likely root cause.

**Canonical guidance for any client surface claiming "RealMe Verified":**

> Use `realme_badge` (boolean) from `GET /api/v1/me`, or the equivalent field on discovery/profile-detail responses (same underlying computation). Never derive "RealMe Verified" from `identifier.verified` / `verification.*` (contact verification only) or from the mere presence of one `approved` entry in `realme_assertions` (that satisfies messaging eligibility, not the badge — see Canonical RealMe Contract above).

No frontend code was written or changed in this pass, per the task's own instruction.

---

# OpenAPI Changes

Added the 7 previously-undocumented live routes (all from the RealMe/Trust Score feature work), each with request/response schemas matching the actual controllers/serializers audited above:

- `POST /api/v1/realme_verifications/uploads`
- `POST /api/v1/realme_verifications`
- `GET /api/v1/trust_score`
- `GET /api/v1/admin/realme_verifications`
- `PATCH /api/v1/admin/realme_verifications/{id}`
- `GET /api/v1/admin/profiles/{profile_id}/trust_adjustments`
- `POST /api/v1/admin/profiles/{profile_id}/trust_adjustments`

New schemas: `RealmeAssertionEntry`, `RealmeVerificationUpload`, `AdminRealmeVerificationQueueEntry`, `AdminRealmeVerificationDecision`, `TrustAdjustmentEntry`, `TrustLedgerEntry`.

**Also fixed** (found during this pass, not in the original 7): `MeResponse` was missing `realme_assertions` and `realme_badge` entirely, despite the live controller (`Api::V1::MeController#show`) returning both. Added both fields to the schema with descriptions explicitly warning against the two most likely frontend misuses (see Frontend Source-of-Truth Guidance).

No route was documented that does not exist — every addition traces to a live controller action read directly, with response shapes matching the actual `*_payload` methods in those controllers.

`bin/rails test test/contracts/openapi_contract_test.rb` — **4 runs / 0 failures / 0 errors** (was 1 failure before this pass).

---

# Test Environment Changes

Root cause (identified in Pass 2, fixed here): no `.env.test` existed, so `.env`'s production-shaped `D8N_EMAIL_PROVIDER=resend` (real API key), `D8N_SMS_PROVIDER=twilio` (real credentials), `D8N_AI_PROVIDER=openai` (real API key), and a production-shaped `D8N_CORS_ORIGINS` silently governed `bin/rails test` — a live cost/safety risk (real Resend/Twilio/OpenAI calls possible from an ordinary test run) as well as the cause of ~12 spurious Pass-2 test failures.

**Fix**: new, git-tracked, secret-free `.env.test`:

```
D8N_EMAIL_PROVIDER=action_mailer
D8N_SMS_PROVIDER=null
D8N_AI_PROVIDER=disabled
D8N_CORS_ORIGINS=<the same local/test origins config/initializers/cors.rb already hard-codes as its own default>
```

`dotenv` loads `.env.test` before `.env` and never overrides an already-set value, so this pins the test suite regardless of a developer's local `.env` contents, without touching or destroying that file. `.gitignore` was updated with a targeted negation (`!/.env.test`) so this file is committed while `.env`/`.env.local` (both containing real secrets) remain ignored.

**Verified working**: `RAILS_ENV=test bin/rails runner` confirms all four variables resolve to the safe values with zero manual override, and the full suite now runs deterministically without needing `D8N_EMAIL_PROVIDER=action_mailer` set by hand (as Pass 2 had to do).

---

# Files Changed

- `docs/api/openapi.yaml` — 7 new paths + 6 new/updated schemas (see OpenAPI Changes)
- `.env.test` (new) — deterministic test-environment provider/CORS defaults
- `.gitignore` — negated `.env.test` so it can be committed
- `domains/identity/realme_badge.rb` — ADR citation fix (0032 → 0034)
- `domains/identity/realme_submission.rb` — ADR citation + doc path fix
- `domains/d8n/platform/capabilities/verify.rb` — ADR citation fix
- `domains/trust/moderate_realme_verification.rb` — ADR citation fix
- `domains/profiles/status_fields.rb` — ADR citation fix
- `app/controllers/api/v1/admin/realme_verifications_controller.rb` — ADR citation fix
- `test/controllers/api/v1/admin/realme_verifications_controller_test.rb` — new test (capability-forbidden case)
- `test/controllers/api/v1/date9ja_interaction_verification_test.rb` — new test (live E2E submission→moderation→gate/badge independence)

No production behavior changed anywhere: every code change is either a comment/doc citation, documentation-only (OpenAPI), or additive test coverage.

# Tests Added

- `test/controllers/api/v1/admin/realme_verifications_controller_test.rb`: "an admin without the moderate capability is forbidden"
- `test/controllers/api/v1/date9ja_interaction_verification_test.rb`: full live upload → pending → approve → gate-unlocked → badge-still-false E2E, proving messaging-gate/badge independence with real (not pre-seeded) submissions

# Test Results

| Suite | Result |
|---|---|
| RealMe domain + controller tests (targeted, this pass) | 39 runs / 172 assertions / 0 failures / 0 errors |
| Trust Score / Trust domain tests (targeted, this pass) | 42 runs / 133 assertions / 0 failures / 0 errors |
| Combined RealMe+Trust+Identity+Messaging+Admin+OpenAPI (targeted) | 92 runs / 2,342 assertions / 0 failures / 0 errors |
| OpenAPI contract test (isolated) | 4 runs / 0 failures / 0 errors |
| **Full Rails suite** | **2,384 runs / 26,898 assertions / 1 failure / 0 errors** |
| RuboCop (all Ruby files touched this pass) | 0 offenses |
| Brakeman | 0 errors / 0 security warnings |
| Zeitwerk | "All is good!" |
| `.env.test` isolation | Confirmed: `RAILS_ENV=test bin/rails runner` shows `action_mailer`/`null`/`disabled`/safe-CORS with zero manual override |

The one remaining full-suite failure is `Notifications::DeliverProductNotificationJobTest#test_welcome_email_uses_the_DateZA_template_and_a_brand_sender_exactly_once` — the same pre-existing, DateZA-only, non-RealMe/Trust test carried forward unchanged from Pass 2 (the welcome email intentionally includes a CTA `href`; the test's no-links premise is stale). Confirmed still unrelated to this pass's scope.

---

# Remaining Risks

| Risk | Severity | Disposition |
|---|---|---|
| Frontend Settings/Safety contradiction — actual root cause unconfirmed (no frontend code in this repo) | Medium | Backend confirmed consistent; canonical field documented above; the stale `MeResponse` OpenAPI schema (now fixed) is the most likely mechanism and should resolve it once a frontend client regenerates from the updated spec — but this needs frontend-side confirmation, which is out of this pass's scope |
| No pending-submission expiry/timeout | Low | Deliberate v1 scope (manual review, ADR 0034); not flagged as a defect, but worth tracking if review volume grows |
| DateZA welcome-email test failure | None (unrelated) | Carried forward, out of scope, unchanged |

---

# Blocker Status

**CLOSED**

The repository demonstrates a coherent, tested RealMe/Trust contract: two independently-verified thresholds (messaging gate vs. badge), zero false-badge paths from email/phone, zero automatic negative trust scoring, full moderation/admin audit trails with capability+MFA enforcement, verified evidence privacy, and a now-accurate OpenAPI contract. The one open item (frontend root-cause confirmation) is explicitly outside this backend pass's scope and does not indicate a backend defect — the backend guidance needed to resolve it has been documented.

```
RealMe/Trust blocker: CLOSED
Canonical RealMe source: GET /api/v1/me -> realme_badge (boolean) + realme_assertions (array); Identity::RealmeBadge / Identity::RealmeAssertions
Messaging gate: VERIFIED
Email falsely grants RealMe: NO
Phone falsely grants RealMe: NO
RealMe moderation: VERIFIED
Evidence privacy: VERIFIED
Trust Score: VERIFIED
Frontend source-of-truth: DOCUMENTED
OpenAPI: PASS
Test environment isolation: PASS
Full suite: 2383 passed / 1 failed (pre-existing, unrelated DateZA test)
Recommendation: PROCEED
```
