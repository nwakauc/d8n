# Data Retention & Account Closure (beta)

Status: minimum privacy-preserving beta policy, 2026-08-17. Legal retention periods
are **not** finalized — items marked _policy decision required_ need product/legal
sign-off before GA. Architecture rationale is in ADR 0014.

## Scope of "close my account" today

`DELETE /api/v1/me` performs **brand-level closure** (the user leaves this brand,
e.g. HookUs). It does **not** delete the user's D8N network identity, because
credentials and identity identifiers are shared across brands. **Platform-wide
identity deletion** (erasing email/phone/credentials across all of D8N) is a
separate, not-yet-built capability — _policy decision required_.

Closure is one-way at the product API (no reinstate endpoint; a returning identity
rejoins via fresh registration). A suspended user cannot self-close (their sessions
are already revoked); admin-initiated closure is out of scope.

## Deletion matrix (brand-level closure)

| Data class | Behavior | Why |
| --- | --- | --- |
| User (network identity) | **retain, active** | Cross-brand identity; brand closure ≠ identity deletion. |
| Credentials / password hashes | **retain** | Identity-level, cross-brand. Erasure is platform deletion (_policy decision required_). |
| Identity identifiers (email/phone) | **retain** | Identity-level, cross-brand. _Policy decision required_ for erasure/anonymization. |
| BrandMembership | **tombstone** (`status: left`) | Every auth/product surface gates on `kept.active`; `left` removes all access, stays findable for idempotency. |
| Profile | **discard + anonymize** (`deleted_at`, hidden, `display_name`/`bio` cleared) | Remove from product + minimize retained personal text; row kept for relational integrity. |
| Profile preferences | **discard** (`deleted_at`) | Brand-scoped, no longer needed. |
| Profile locations (GPS) | **hard delete** | Precise location is sensitive and never needed post-closure. |
| Profile photos (rows) | **discard** (`deleted_at`, hidden) | Removed from product; row kept as tombstone (holds no PII). |
| Profile media (R2 objects + blobs) | **physically purge** (async job) | Real erasure of user-owned media — display derivatives and any raw originals. |
| Likes / passes | **discard** (`deleted_at`) | Remove from active discovery/matching; rows kept for integrity. |
| Matches | **end** (`status: ended`) active ones | Graceful unavailable; shared record not hard-deleted. |
| Conversations | **retain** | Shared with the counterpart; becomes unavailable via membership tombstone. |
| Messages | **retain** | Shared content; not deleted because one participant left. Sender reference stays valid. |
| Blocks | **retain** | Safety value; the closed profile auto-drops from others' block lists (`kept` filter). |
| Reports | **retain** | Moderation/safety evidence; survives closure of reporter or target. |
| AccountEnforcement | **retain** | Safety/audit history; a closing user cannot erase enforcement evidence. |
| SecurityEvents / audit | **retain** | Audit integrity; a closure writes `account.closed`. |
| Product notifications / events / delivery attempts | **retain, inaccessible** | Operational/audit evidence; the left membership and revoked sessions remove inbox access. Final retention period requires policy. |
| Notification preferences | **retain, inactive** | Bound to the tombstoned membership; no longer consulted. Final retention period requires policy. |
| Device registrations | **revoke** | Prevent any queued or future product push for the closed brand; encrypted token remains pending final retention policy. |
| AccountClosure record | **create** | Durable closure + async purge-state tracking. |

## Media purge lifecycle

Closure is synchronous and atomic (state change + session revocation + closure
record); the physical R2 purge runs afterwards in `Media::PurgeProfileMediaJob`.
The account is never left open waiting on storage. The job is idempotent and
retry-safe, purges display + raw for every photo (including already soft-deleted),
and records the outcome on `account_closures.media_purge_state`
(`pending → completed | failed`) so a persistently failing purge is operationally
discoverable — never silently marked done.

## Frontend implications

- After closure the caller's token is revoked; treat the 200 as terminal and drop
  the session. A retry returns 401.
- A counterpart in a shared conversation sees it become **unavailable**
  (`conversation_unavailable`); history is retained server-side. No "deleted user"
  product experience is built — display the counterpart as unavailable.

## Open policy decisions (require product/legal sign-off)

- Platform-wide identity deletion + email/phone/credential erasure/anonymization.
- Legal retention periods for messages, reports, and audit events.
- Re-registration semantics for a returning identity (reactivate vs. fresh membership).
- Whether closed-account personal identifiers need time-boxed anti-abuse retention.
