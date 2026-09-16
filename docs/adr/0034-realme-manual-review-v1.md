# ADR 0034: RealMe manual-review v1

## Status

**Accepted** (2026-09-14, product-owner decision). Builds on ADR 0031, which
gates Date9ja message-send on an *already-approved* `VerificationAssertion`
but assumed such assertions arrived only via the Date9ja historical importer.
This ADR adds the missing piece: how a *current* member actually gets one.

## Context

RealMe exists to protect users against scam and impersonation. The full
vision confirms four things: a member's email (control), a selfie (a real
face), a liveness video (a real, present person), and a government ID
(matched, eventually, to both the profile name and the selfie). Automating
the two matching steps — selfie-to-profile-photo face match and ID-to-profile
name match — is real computer-vision/OCR work that is out of proportion to
D8N's current scale. Building the honest, working v1 first is the
scope-proportionate choice: a human (today, the product owner) reviews each
submission and decides.

Phone verification remains a shared D8N capability but stays absent from
Date9ja's brand contract (ADR 0031) — no change here; it is uneconomic at
Date9ja's SMS volumes and is not part of RealMe's identity claim anyway.

## Decision

A member submits selfie/liveness-video/government-ID evidence through a
direct-to-R2 control-plane upload (`Identity::RealmeSubmission`, mirroring
`Profiles::PhotoUpload`/`Profiles::VideoUpload`). Each submission creates a
`pending` `VerificationAssertion` (`source_type: "member_submission"`).

An admin with the `admin.realme_verifications.moderate` capability reviews
pending submissions (`Trust::ModerateRealmeVerification`) and decides:

- `approved` — the evidence is genuine and matches (face/name checked by eye);
- `rejected` — the evidence is fraudulent, does not match, or is otherwise
  disqualifying;
- `resubmission_requested` — the evidence is inconclusive (blurry, wrong
  document, cropped) and the member should try again.

The **RealMe badge** (`Identity::RealmeBadge`) is the single trust signal
shown to other members: confirmed email AND approved selfie AND approved
liveness video AND approved government ID. Any one missing/rejected/pending
check withholds the badge — there is no partial badge. It is computed
alongside the existing `verified` (contact-only) signal in
`Profiles::StatusFields`, so it surfaces on discovery cards, profile detail,
and `/me` for free.

`verify.identity.selfie`, `.liveness`, and `.document` move from `:planned`
to `:available` in the platform capability catalog. `verify.identity.face_match`
and `verify.level` (automated scoring) stay `:planned` — that automation is
explicitly deferred, not abandoned.

## Consequences

- Raw evidence (`VerificationAssertion#evidence`) is admin-review-only,
  never delivered to any other member, and reviewed via a short-lived signed
  URL exactly like `ProfilePhoto`'s raw original is for moderators.
- A member can have only one `pending` submission per check_type at a time,
  but may resubmit freely after `rejected` or `resubmission_requested` —
  `Identity::RealmeAssertions` and the badge always read the latest row per
  check_type, so history accumulates without special-casing.
- This is deliberately a v1: no OCR, no face-match score, no automated
  fraud detection. If manual review volume outgrows what one admin can
  handle, that is the trigger to revisit automation — not before.
