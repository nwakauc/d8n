# ADR 0024: Shared verification-evidence architecture

## Status

**Accepted** (2026-09-02, independent review) — architecture only; implementation remains gated as stated below. Product owner has decided all shipped/reachable
Date9ja verification capabilities are retained parity. Extends ADR 0011 (the
verification-assertion boundary, still unbuilt). Establishes the `Verification`
domain and the evidence model needed to preserve existing Date9ja verification
state during migration. **Implementation is gated on the ADR 0011 human gates
(provider selection, evidence retention/erasure policy, cross-brand portability,
review/appeal permissions)** — this ADR defines the architecture; it does not
resolve those product/legal decisions.

## Context — Date9ja source audit

Reachable verification surfaces in `/Users/uchechinwaka/pro/Date9ja/api`:

| Source | Shape |
|---|---|
| `phone_verifications` | custom OTP with throttling; sets `users.phone_verified_at` |
| `selfie_verifications` | one per user, admin compares selfie to primary photo, approve → `users.verification_tier = 2` |
| `verification_checks` | `check_type ∈ {email, phone, selfie, video, government_id}`, `status ∈ {not_started, submitted, pending, approved, rejected, resubmission_required, revoked}`, `has_one_attached :evidence`, `provider`, `provider_reference`, `rejection_code`, `submitted_at`, `decided_at`, `evidence_expires_at`, `reviewed_by`, `ai_review_status`/`ai_review_result` |
| `verification_events` | append audit per check; `event_type`; metadata guarded against raw identity data |
| `users.verification_tier` | plain integer 0 (unverified) / 1 (phone) / 2 (selfie); web clients do numeric `>= 1` / `>= 2` comparisons |
| `/api/v1/verification/{selfie,video,government_id,realme}` | status (never 404 — "no submission" is valid), submit (multipart, resubmission overwrites in place), RealMe status aggregate |

Government-ID and video-verification checks exist and are reachable but manual-
review-only (no automated provider). RealMe is Date9ja's brand name for the
aggregate verification programme.

## Decision

### `Verification` is a D8N platform domain; badges/gates are brand policy

```
D8N Verification
  → VerificationCheck        (one bounded assertion about a platform User)
  → VerificationEvidence     (private, minimized, retention-bounded)
  → VerificationEvent        (append-only audit)
  → derived assertion        (verified-phone, verified-selfie, …)
        ↓
  brand policy/config
    → available checks
    → badge / tier presentation
    → prerequisites and required gates (only where product policy is explicit)
```

`VerificationCheck` belongs to a **platform `User`**, not a brand profile
(matching ADR 0011: an assertion is about the person). A brand contract declares
which checks it offers, how they roll up into a user-visible badge/tier, and
which product actions (if any) they gate. **No new gate is invented** — Date9ja's
only established gate today is `verified_login_identifier` on interaction
(already in the DateZA contract shape); Date9ja's `verification_tier` is
presentation, not a hard gate, and migrates as such unless the product owner
states otherwise.

### Evidence is separate, minimized, and retention-bounded

`VerificationEvidence` holds the private upload (selfie image, verification
video, ID document) as an ADR-0011-style quarantined media object with a
`retention_expires_at`. Raw evidence is retained **only** while an approved
policy requires it; after that it is purged and the check keeps only the derived
assertion + decision metadata. `provider` / `provider_reference` /
`ai_review_result` are internal and never serialized to consumers. Public
payloads expose only the approved derived badge/tier — never a score, failure
reason, provider reference, or the evidence itself.

### Cross-brand isolation

A check completed under one brand does not disclose membership on another brand
and does not make a profile visible elsewhere. Portability across brands
requires explicit policy, consent, purpose compatibility, and expiry (ADR 0011)
— out of scope here.

### Migration-state preservation

`LegacyReference` (ADR 0022) maps `verification_checks` → `VerificationCheck`,
`selfie_verifications` → the selfie `VerificationCheck`, preserving `status`,
`decided_at`, `rejection_code`, `reviewed_by` (→ D8N admin actor or historical
metadata), and `verification_tier` → the derived Date9ja badge. `verification_events`
→ `VerificationEvent`. Evidence objects re-ingest through the D8N media pipeline;
evidence past its retention window is not migrated. Confirmed/unconfirmed email
and verified/unverified phone map from the identity layer, not re-derived.

### Providers and webhooks

When a provider is later approved: webhooks are signature-verified, replay-safe,
idempotent, and mapped to a server-created attempt — never trusting
client/payload-supplied user/brand/profile ownership (ADR 0011). Manual review
is the safe default and is sufficient for Date9ja parity today.

## Consequences

- Existing Date9ja verification state (tier, per-check status, history) survives
  migration with a defined mapping.
- Verification stays platform-owned with no implicit cross-brand disclosure.
- Evidence retention becomes an explicit, enforceable policy rather than
  indefinite storage.
- Real implementation still waits on the ADR 0011 human gates; this ADR unblocks
  the *design* and the migration mapping, not a production verification flow.

## Alternatives considered

- Store verification state on `Profile` / `users` columns (Date9ja's approach).
  Rejected — it is a platform-identity assertion, and columns cannot express
  evidence retention or audit.
- One `verification_tier` integer as the contract. Rejected as the *internal*
  model (keep the per-check ledger); retained only as a *derived* Date9ja badge
  for client compatibility.
- Automated provider review now. Rejected — no provider approved; manual review
  meets parity.
