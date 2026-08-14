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
- Status: Not started
- Work: Provide a recovery flow only through a verified identifier, prevent
  account enumeration, use single-use expiring challenges, and make an explicit
  session-revocation decision. Do not create an automatic account-merging path.
- Evidence: End-to-end tests cover valid recovery, unknown/unverified identifiers,
  replay, expiry, throttling, session behavior, and cross-brand privacy.

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

