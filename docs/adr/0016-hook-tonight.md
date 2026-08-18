# ADR 0016: Hook Tonight (temporary availability)

## Status

Accepted for the V1 HookUs Hook Tonight slice on 2026-08-18. Builds directly on
the 🔥 Hook slice (ADR 0015). Product confirmed reciprocal pool access (you must
be available to browse who's available); the 6h window and single `open_to_meeting`
intent are accepted for V1 (see "Open questions" for what remains deferred).

## Context

Hook and Hook Tonight answer different questions:

- **Hook** — "I specifically want *you*." A high-intent, one-shot opener (ADR 0015).
- **Hook Tonight** — "I'm available / open to meeting *tonight*." A temporary
  availability state that populates a discovery pool of other available members.

Hook Tonight is availability/intent only. Finding someone attractive in that pool
and approaching them still goes through the existing 🔥 Hook. There must be exactly
one messaging/matching system, not a parallel "Hook Tonight" one.

## Decision

### A temporary state record, not a profile setting

`hook_tonight_states` holds exactly **one current-state row per (brand, profile)**
(`HookTonightState`). A unique `(brand_id, profile_id)` index enforces that:
repeated activate/deactivate toggling reuses the one row via a Postgres upsert
(`ON CONFLICT`), so history never grows unbounded and concurrent double-activation
converges on a single row without a `RecordNotUnique` dance.

### Expiry is lazy, and correctness never depends on a sweeper

`HookTonight::Policy::EXPIRES_IN` (6h) bounds availability. `HookTonightState#live?`
(and the `live` scope) re-check `expires_at` against the clock **and** require
`deactivated_at IS NULL`, so a stale or deactivated row can never make anyone appear
available and no background job is needed for correctness. 6h is a deliberately
simple fixed duration: the platform has no per-user timezone today, so midnight/TZ
machinery would be unjustified complexity — a fixed window comfortably covers an
evening while guaranteeing a forgotten activation cannot linger into the next day.
Deactivation is a manual off-switch (`deactivated_at`), kept distinct from lapse so
activation-vs-deactivation stays auditable. A cosmetic cleanup job may later delete
lapsed rows; it is never a correctness dependency.

### Discovery is the existing engine, narrowed — not a fork

`HookTonight::Discovery` delegates to `Matching::Discovery`, passing a single
`restrict` clause that intersects the eligible population with members who have a
live availability. Everything else — brand isolation, active/visible lifecycle,
blocking (either direction), reciprocal age/gender/preference, distance/privacy,
exclusions (**including live Hooks, ADR 0015 §9**), facet filters, ranking, signed
cursors, safe photos, and the no-N+1 `Hooks::ViewerStates` / `Profiles::StatusFields`
decoration — is unchanged. So Hook Tonight can never surface someone normal
discovery wouldn't, and location stays the same privacy-preserving approximate
distance (never coordinates).

### Approaching reuses the existing Hook — no new allowance

There is no Hook-Tonight-specific approach path. From the pool the client calls the
existing `POST /profiles/{id}/hook`, so every ADR 0015 rule (one opener,
reply-is-acceptance, expiry, one-per-pair-ever, blocking, decline, and crucially
`Hooks::Policy::FREE_DAILY_LIMIT`) applies verbatim. Hook Tonight grants **no extra
Hook allowance**. Activation itself creates no Match, Conversation, or Message.

### Eligibility is always re-checked; stale activation is inert

Activation goes through `Matching::ProfileParticipant.discoverable!` (the same gate
as Liking/Hooking), so suspended/closed/incomplete members cannot activate. If a
member becomes suspended, closed, or blocked *after* activating, the stale row is
inert: discovery re-derives eligibility at read time and drops them. Blocking in
either direction removes the pair from the pool immediately.

### Pool access is reciprocal

"Available tonight" is a sensitive signal, so browsing the pool while invisible is
disallowed: `HookTonight::Discovery` requires the viewer to have a live activation
(a `guard` on the resolved viewer, symmetric with `restrict`) and otherwise raises
`NotActivated` → 403 `hook_tonight_required`. To see who's available tonight you
must be available tonight — which also makes activation meaningful and improves pool
liquidity. Eligibility is still checked first, so a non-discoverable viewer gets the
usual `discoverable_profile_required`, not the activation prompt. Normal discovery
is unaffected and remains open to every eligible member.

### Privacy

Hook Tonight ("I'm available tonight") is sensitive. It is never exposed
cross-brand, never on public profiles, and never as history through any public API.
`GET /hook_tonight` returns only the viewer's own authoritative `{active, expires_at,
intent}`. A deactivated/expired state simply disappears.

## Consequences

- New surfaces: `GET/POST/DELETE /api/v1/hook_tonight` (state, activate, deactivate)
  and `GET /api/v1/hook_tonight/discovery`.
- Audit events `hook_tonight.activated` / `hook_tonight.deactivated` follow the
  existing `SecurityEvent` pattern. Expiry emits **no** synchronous event: it is
  lazy, so an "expired" event would be misleading (nothing runs at expiry time).
- `Matching::Discovery` gained an optional `restrict:` hook — a reusable seam for
  any future "same population, extra predicate" surface.

## Open questions

- Whether "Tonight" should key off local evening (vs. the fixed 6h window) once
  per-user timezone exists.
- Whether to persist more than a single `intent`, or add coarse availability
  windows, once product validates that people use Hook Tonight at all.
