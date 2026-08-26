# ADR 0014: Account Closure and Data Lifecycle

## Status

Accepted for the TS-06 beta account-closure slice on 2026-08-17. Extended on
2026-08-26 with authenticated password change and reversible account
deactivation — the other two D8N ID account-control capabilities alongside
closure. Platform-wide identity deletion and finalized legal retention periods
remain out of scope and remain policy decisions (see
`docs/operations/data-retention.md`).

## Context

Beta users must be able to close their account safely, which is neither a hard
`DELETE` nor an indefinite soft-delete-everything. D8N separates network `User`
identity from per-brand `BrandMembership`/`Profile` participation (ADR 0003), stores
user media privately in R2 (ADR 0011), and holds shared (conversations/messages) and
safety (reports/enforcements/audit) records that other users or operators depend on.
A single deletion strategy for all of this would either destroy shared/safety data or
retain personal data it should not.

## Decision

### Closure is brand-level, not platform identity deletion

`DELETE /api/v1/me` closes the caller's participation in the request's brand: the
`BrandMembership` is tombstoned (`status: left`), the `Profile` is discarded and
anonymized, and brand sessions are revoked. The `User`, credentials, and identity
identifiers are **retained** because they are cross-brand shared identity. Erasing
them ("platform-wide identity deletion") is a separate future capability; doing it as
a side effect of leaving one brand would destroy unrelated D8N-brand identities.

### Immediate atomic deactivation, asynchronous physical erasure

The synchronous transaction performs the account-state transition (membership
tombstone, profile discard, matches ended, likes/passes discarded, sessions revoked,
closure recorded) so product access ends immediately and consistently — never
"closed but sessions valid" or "sessions revoked but still discoverable". The
physical R2 media purge is enqueued to run afterwards; the account is never held open
waiting on object storage. The purge is idempotent and retry-safe and records its
outcome on the `AccountClosure` record, so a failing purge is operationally
discoverable rather than silently completed.

### Per-data-class strategy, not one strategy

Data is classified deliberately (full matrix in `docs/operations/data-retention.md`):
physically **purge** user-owned media and precise locations; **tombstone/anonymize**
brand membership and profile; **end/discard** matches, likes, and passes; **retain**
shared content (conversations, messages) and safety/audit records (blocks, reports,
enforcements, security events); and **retain** cross-brand identity. Shared records
are never destroyed because one participant left, and safety/audit evidence cannot be
erased by the actor it concerns.

### Closure is one-way at the product API

There is no reinstate endpoint (unlike suspension, ADR 0013). A returning identity
rejoins through fresh registration; closed data is not restored. A recovery window
can be designed later if the product requires it.

### Deactivation is a distinct, reversible BrandMembership state

`BrandMembership.status` gained a fourth value, `deactivated`, alongside `active`,
`suspended` (moderation, ADR 0013), and `left` (this ADR's closure). It is
deliberately its own state rather than reusing `suspended`: suspension is always
tied to an `AccountEnforcement` and an admin actor; deactivation is always
self-service and carries no enforcement record. `POST /api/v1/account/deactivation`
(`Accounts::DeactivateAccount`) flips the membership off `active` and revokes this
brand's sessions and devices — nothing else. Because every product/auth surface
already gates on `BrandMembership.kept.active` (`Matching::ProfileParticipant`,
`Identity::SessionAuthenticator`, discovery/find/notifications scopes), that one
state change is sufficient to drop the member out of discovery, find, matching,
messaging, and new sessions platform-wide, with no brand-specific or per-surface
filtering. Profile, photos, matches, likes, conversations, location, and
preferences are left untouched, unlike closure.

### Reactivation re-verifies the password; it is not a bare confirm button

Deactivation revokes every session for the brand, so there is no live session left
to "just confirm" reactivation from. `Identity::AccountReactivation`
(`POST /api/v1/auth/password/reactivation`) mirrors `PasswordLogin` exactly —
identifier and password back in, a fresh session out — and only flips the
membership back to `active` once the password has been re-proven. It shares
`PasswordLogin`'s throttle purpose deliberately, so an attacker cannot double a
guess budget by alternating between `/login` and `/reactivation`. `PasswordLogin`
itself reveals `account_deactivated` as a distinct error from `invalid_credentials`
only after the password has already matched, so the state is never observable to
someone who doesn't already know the password.

### Password change reuses the same primitives as every other credential mutation

`PATCH /api/v1/auth/password` (`Identity::PasswordChange`, shipped ahead of this
ADR text) requires the current password, validates the replacement with the same
`Identity::PasswordEngine.valid?` policy used by registration and reset, and
revokes every other session on the credential while leaving the calling session
valid. It is the third capability declared under `id.account.*`
(`id.account.password_change`, `id.account.deactivate`,
`id.account.close_brand_membership`) so brand contracts can express availability
uniformly — see `Api::V1::MeController#show`'s `account_controls` block. All three
are enabled for both HookUs and DateZA today; nothing here is brand-specific.

## Consequences

- User media is genuinely erased from storage; personal profile data is minimized;
  shared and safety records remain intact and trustworthy.
- A future Operations Command Center can surface closure and purge state from the
  `AccountClosure` record and audit events without new plumbing.
- Platform-wide identity erasure, legal retention periods, and re-registration
  semantics remain explicit open policy decisions rather than accidental defaults.
- Deactivation reuses closure's and suspension's shared-predicate pattern, so no
  discovery/find/matching/messaging surface needed brand- or feature-specific
  exclusion logic to honor it.

## Alternatives Considered

- Hard-deleting the user and cascading — rejected; destroys shared/safety data and
  cross-brand identity.
- Reusing `suspended` for self-service deactivation — rejected; would conflate
  moderator-driven enforcement (which always carries an `AccountEnforcement` and
  drives `Admin::ReinstateProfile`) with a user's own reversible choice, and would
  let a member "reinstate" past an active moderation action by mistake.
- A bare authenticated "reactivate" endpoint on the existing session — impossible
  by construction (deactivation revokes the brand's sessions), and undesirable
  even if it weren't: re-proving the password is the intended reactivation
  confirmation, not a separate mechanism to invent.
- Soft-deleting everything and keeping media forever — rejected; retains personal
  media/PII with no justification.
- Deleting the whole conversation/messages when a participant leaves — rejected;
  destroys the counterpart's history.
- Running the R2 purge inside the closure transaction — rejected; ties account
  closure to storage availability and lengthens the critical transaction.
