# ADR 0014: Account Closure and Data Lifecycle

## Status

Accepted for the TS-06 beta account-closure slice on 2026-08-17. Platform-wide
identity deletion and finalized legal retention periods are out of scope and remain
policy decisions (see `docs/operations/data-retention.md`).

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

## Consequences

- User media is genuinely erased from storage; personal profile data is minimized;
  shared and safety records remain intact and trustworthy.
- A future Operations Command Center can surface closure and purge state from the
  `AccountClosure` record and audit events without new plumbing.
- Platform-wide identity erasure, legal retention periods, and re-registration
  semantics remain explicit open policy decisions rather than accidental defaults.

## Alternatives Considered

- Hard-deleting the user and cascading — rejected; destroys shared/safety data and
  cross-brand identity.
- Soft-deleting everything and keeping media forever — rejected; retains personal
  media/PII with no justification.
- Deleting the whole conversation/messages when a participant leaves — rejected;
  destroys the counterpart's history.
- Running the R2 purge inside the closure transaction — rejected; ties account
  closure to storage availability and lengthens the critical transaction.
