# ADR 0013: Administrative Identity, Authorization, and Brand-Level Enforcement

## Status

Accepted for the TS-03/TS-04 beta moderation slice on 2026-08-17. Platform-level
(cross-brand) bans and admin MFA are explicitly out of scope and remain gated.

## Context

D8N needs moderators to review reports (TS-03) and remove bad actors (TS-04) for a
controlled HookUs beta, and eventually a shared multi-brand "D8N Operations Command
Center" will consume the same backend. Before this work the `AdminUser`,
`AdminRole`, and `AdminAssignment` tables existed but were inert: there was **no
admin authentication of any kind** and `AdminUser` had no identity/credentials.

D8N separates network `User` identity from brand `Profile` participation (ADR 0003),
resolves the brand from the request host (ADR 0006), and issues brand-scoped
sessions (ADR 0007). Enforcement must respect those boundaries and must not become a
second authentication universe or a standalone moderation product.

## Decision

### Admins reuse the ordinary session; `AdminUser` is administrative identity only

An administrator signs in through the **existing brand-scoped session** as a normal
`User` (the same credential/session/`SessionAuthenticator` path as any member — a
brand membership is required). `admin_users.user_id` links that `User` to an
`AdminUser`. There is deliberately **no** `AdminSession`, `AdminCredential`, admin
password, or separate admin auth stack. `AdminUser` carries administrative
status/metadata; it is not a login.

### `AdminAssignment` is brand-scoped authorization

Authorization is server-derived only (`Admin::ModeratorContext`): the caller must
map to a kept, active `AdminUser` **and** hold a kept, active `AdminAssignment` for
the request's brand (resolved from the host, never trusted from client input).
Unauthenticated → 401; authenticated non-moderator → 403. Any active admin role
currently grants report moderation and enforcement; **differentiated admin RBAC is
deferred** until more roles genuinely exist. Because the brand comes from the host
and every query is scoped to it, brand isolation is structural: cross-brand
resources are simply absent and return neutral not-found responses.

### Report decision state is separate from account enforcement state

A report's lifecycle (`open/reviewing/actioned/dismissed`, ADR — TS-03) never
implies an account action. Enforcement is a distinct, explicit action recorded in a
durable `AccountEnforcement` (target user/membership/profile, acting admin, optional
originating `report_id`, reason, reversal provenance). This lets future decisions
(no action, warning, suspension) exist without overloading the report enum.

### Enforcement is brand-level, atomic, and session-revoking

Brand-level suspension suspends the target's `BrandMembership` — the single gate
every existing access object already checks (auth, discovery, likes/passes, matches,
conversations, messaging) — **and** explicitly revokes that user's sessions for that
brand, writes the `AccountEnforcement`, and audits, all in one transaction. Status
change without session revocation, or an audit without the state change, are both
unacceptable partial states. Suspension is not deletion: history is retained.
Reinstatement restores only the membership; it does not revive revoked sessions,
ended matches, blocks, or deleted data. One active enforcement per (brand, user) is
DB-enforced for idempotency/conflict handling.

### Platform-level bans are not modelled yet

`User.status` (network-wide) could express a platform ban, but no global/cross-brand
admin authority exists, and brand-scoped moderators must not wield one. Until such an
authority is deliberately introduced, only brand-level enforcement ships.

## Consequences

- Admin capability is an API/domain surface a future Operations Command Center can
  consume across brands without a separate auth system or admin UI in this repo.
- Suspending a membership transitively enforces across all product surfaces, so no
  scattered `if suspended?` checks are added.
- Admin MFA remains a required pre-launch gate (admins can read report content); it
  is not built here.
- A bad actor can still be fully removed from a brand today; cross-brand/platform
  removal waits for an explicit authority decision.

## Alternatives Considered

- A separate admin authentication stack (admin passwords/sessions/MFA universe) —
  rejected as premature scope and a second identity system.
- Driving enforcement purely off `Profile.status` — rejected; membership is the
  gate every surface already checks and the cleaner brand-participation lever.
- Encoding enforcement in the report lifecycle (`actioned` == banned) — rejected;
  conflates moderation decisions with account state.
- A generic admin status-mutation endpoint — rejected in favour of explicit domain
  actions (suspend/reinstate) to prevent arbitrary state changes.
