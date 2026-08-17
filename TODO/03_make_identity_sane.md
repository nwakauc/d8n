# Milestone 3 — Make Identity Sane

Outcome: users can register and recover accounts without obvious identifier,
abuse, or operational traps. This is proportionate consumer dating-app security,
not bank-grade user authentication.

## Tasks

### ID-01 — Normalize phones as E.164

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Select the accepted countries/default country behavior and use a proven
  parser to produce canonical E.164 values. Plan the treatment of existing
  identifiers before changing uniqueness behavior; never auto-merge accounts.
- Evidence: Tests cover country codes, national input, invalid characters,
  ambiguous input, duplicates after normalization, and existing-data migration.

### ID-02 — Apply sane registration and authentication throttling

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Count successful account creation as well as failures, limit by trusted
  client IP and appropriate identifier/device signals, preserve generic responses,
  and avoid making shared networks unusable. Configure trusted proxies before IP
  values become security inputs.
- Evidence: Request and concurrency tests prove distinct-identifier mass signup
  cannot bypass the registration limit; staging confirms proxy-derived client IPs
  are trustworthy; limits and support override behavior are documented.

### ID-03 — Productionize identifier verification

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Wire approved email/SMS delivery through durable jobs with timeouts,
  bounded retries, generic responses, expiry/attempt limits, and no session
  creation. Keep verification optional for onboarding unless product policy says
  otherwise.
- Evidence: Provider sandbox tests and application tests cover resend limits,
  duplicate jobs, provider failure, expiry, successful verification, and logs
  without codes or raw provider payloads.

### ID-04 — Implement password recovery

- Priority: P1
- Beta blocker: Yes
- Owner: Unassigned
- Status: **IMPLEMENTED + TESTED** (2026-08-17) — awaiting founder commit/deploy/staging QA.
- Work: Provide a recovery flow only through a verified identifier, prevent
  account enumeration, use single-use expiring challenges, and make an explicit
  session-revocation decision. Do not create an automatic account-merging path.
- Delivered: Three-step signed-out flow `POST /api/v1/auth/password/recovery` →
  `.../recovery/verify` → `.../recovery/reset`. Verified-identifier-only,
  enumeration-resistant neutral `202` (throttle = silent non-delivery, never
  `429`), single-use 10-min recovery code + single-use 15-min HMAC-digested reset
  authorization reusing `OtpChallenge`/throttle/lock and SMS/email adapters.
  Reset reuses the shared password policy and revokes every session from the
  affected credential **across all brands** (D8N-wide password). Recovery never
  touches `BrandMembership`, so suspended/left/closed state and login gating are
  unchanged. No new ADR (fits ADR 0012 Slice 4B); no migration.
- Evidence: `test/controllers/api/v1/auth/password_recoveries_controller_test.rb`
  (18 tests) covers valid recovery, unknown/unverified identifiers, replay, expiry,
  attempt-lock, throttling, single-use, password policy, cross-brand session
  revocation, suspended-user and left-membership boundaries, and secret-free logs.
- Production gate (not code): approved SMS/email provider + final recovery copy
  (shared with ID-03). Email fails closed in production until configured.
- Follow-up product decision: recovery requires a *verified* identifier, so users
  who never verified their signup identifier cannot self-serve recover — routes to
  ID-03 (productionize verification) and ID-05 (support/squatting policy). Rejoin
  after `left`/closed membership is intentionally out of scope.

### ID-05 — Define the beta identifier-squatting response

- Priority: P2
- Beta blocker: Yes
- Owner: Unassigned
- Status: Not started
- Work: Decide how support handles a real owner whose phone/email was registered
  but never verified by someone else. Keep the decision small and manual for beta;
  do not invent automatic merging.
- Evidence: Approved support policy and a tested administrative action that is
  narrow, authenticated, and audited if code is required.

