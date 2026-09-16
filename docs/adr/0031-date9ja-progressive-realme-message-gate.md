# ADR 0031: Date9ja progressive RealMe message gate

## Status

**Accepted** (2026-09-12, product-owner decision). Amends the Date9ja interaction
policy described in ADR 0024; DateZA and HookUs policies are unchanged. Updated
the same day to disable Date9ja phone verification pending sustainable SMS economics.

## Context

Requiring verification immediately after signup or only revealing a wall when a
member tries to message creates avoidable early friction and a high-emotion
surprise. Date9ja should show the value of the product first while progressively
encouraging contact confirmation and RealMe completion across discovery, Likes,
profile, conversation, and safety surfaces.

Email confirmation proves control of an email address. It is not RealMe identity
assurance and must not silently satisfy Date9ja's message-safety requirement.
The shared D8N backend can verify phone control, but Date9ja does not presently
use phone as a product signal and SMS verification is uneconomic. Existing
Date9ja migration records can preserve approved selfie, video, and government-ID
assertions; future liveness assertions use the same policy category.

## Decision

Date9ja has no verification wall for registration, onboarding, publication,
discovery, profile detail, likes, passes, matches, conversation creation, or
message-history reads.

Creating a message requires one same-user Date9ja RealMe method. If Date9ja
later enables message-media uploads, its upload-intent endpoint uses the same
requirement:

- an approved, Date9ja-scoped `VerificationAssertion` whose type is selfie,
  video, liveness, or government ID.

A verified email alone never satisfies this gate. Rejected, revoked, pending,
cross-user, or cross-brand assertions do not satisfy it. The API returns `403
realme_verification_required` without revealing the method or evidence.

`verify.contact.phone` is intentionally absent from Date9ja's brand contract.
The shared D8N phone-verification implementation remains available to other
brands and can be restored for Date9ja by re-enabling that one capability when
the economics justify it. The rule is brand-contract configuration evaluated by
`Identity::InteractionAccess`; it is not a Date9ja controller fork. DateZA keeps
its `verified_login_identifier` interaction rule and HookUs keeps no equivalent
requirement.

## Presentation

Clients should progressively frame RealMe around protection and readiness before
the member reaches message send. The backend denial is still authoritative, so a
client must handle it and route to the verification-method picker. Until live
selfie/video/ID status is exposed, clients must never present phone or email as
Date9ja RealMe completion, and must never over-claim imported evidence.

## Migration consequences

No new database migration is required by this policy. Date9ja's existing
identity importer already preserves `phone_verified_at`, and its verification
importer preserves approved legacy assertions. Those records become inputs to
the runtime gate after the verification import/reconciliation runs.

This intentionally changes access for two cohorts:

- members with verified email only may still use the dating loop through
  matching and chat history, but must complete a RealMe method before sending;
- members with an imported approved selfie/video/government-ID assertion may
  send even when their login email is unconfirmed.

Cutover reconciliation must report the eligible message-send cohort by each
qualifying method, rejected/revoked states, and overlaps. Verification evidence
privacy, retention, review, and production-import gates from ADRs 0011 and 0024
remain in force.
