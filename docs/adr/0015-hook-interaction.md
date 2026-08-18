# ADR 0015: The 🔥 Hook Interaction

## Status

Accepted for the V1 HookUs Hook slice on 2026-08-18. Sender-withdraw/cancel, Plus
Hook allowances, and re-Hook-after-expiry cooldowns are out of scope and remain
product decisions (see "Open questions").

## Context

HookUs has three profile actions: ✕ Pass, ❤️ Like, and 🔥 Hook. Hook signals
stronger, immediate hookup intent and behaves unlike a Like in three ways a `Like`
row cannot express:

1. it carries an **opening message**;
2. it grants the sender exactly **one unsolicited opener**, then locks them out
   until the recipient engages;
3. the recipient's **first reply is acceptance** — no separate accept step, no
   requirement that both press 🔥 — which unlocks a normal two-way conversation.

The existing stack already has the pieces we want to reuse once a Hook is
reciprocated: canonical `Match` (mutual), `Conversation` (one per match), `Message`
(match-gated), `Matching::EligibilityScope`/`VisibilityScope` (who may reach whom),
`Trust::BlockPolicy` (blocks both directions), and signed cursors/serializers. The
`Like` model even already carries a `kind: hook` enum value.

## Decision

### A Hook is its own record, not a `Like`

A new `hooks` table + `Hook` model represents the pre-acceptance state. Overloading
`Like` (even with `kind: hook`) cannot store the opener, the one-shot lockout, or the
pending/accepted/declined/expired lifecycle. Crucially, **sending a Hook does not
create a `Like`**: doing so would let a later mutual-like auto-create a Match and
bypass the opener-reply flow. The `Like.kind = hook` enum value is left unused by V1.

### Pre-acceptance state lives entirely on the Hook — this is what makes the lockout real

When a Hook is sent, the opener is stored on the Hook and **no Match, Conversation,
or Message is created**. That is the enforcement mechanism, not a frontend nicety:

- With no Conversation, there is no message endpoint the sender can reach — every
  messaging path requires a Conversation, which requires a Match, which does not
  exist. The sender cannot send message #2 through any endpoint.
- A unique `(brand_id, sender_profile_id, recipient_profile_id)` index makes a second
  Hook to the same person impossible — including concurrently (paired with a
  `RecordNotUnique` rescue) and including a delete/resend loop (rows are never
  hard-deleted). This is the V1 **one-Hook-per-pair-ever** anti-spam rule.

`Hooks::SendHook` mirrors `Matching::LikeProfile` (viewer `discoverable!`, target by
public id, both rows `FOR UPDATE` locked, re-checked through `EligibilityScope`), so a
Hook can never reach anyone a Like couldn't (blocked/suspended/closed/hidden/
cross-brand/self all fail closed as neutral `profile_unavailable`).

### Reply IS acceptance, and it promotes into the existing chat system

`Hooks::ReplyToHook` runs one transaction under a row lock on the Hook: verify it is
still live, verify both parties are available and unblocked, then create the canonical
active `Match` + `Conversation` + participants, materialize the opener as the first
`Message` (sender) and the reply as the second (recipient), and flip the Hook to
`accepted` with its `conversation_id` linked. From that point the relationship is an
ordinary Match + Conversation, so **all further messaging flows through the existing
Messaging endpoints** — there is exactly one chat system, not two. The row lock makes
concurrent replies safe: the loser observes a non-live Hook and fails closed, so
messaging permissions can never end up inconsistent.

### Expiry is lazy, not a background job

Pending Hooks expire after `Hooks::Policy::EXPIRES_IN` (48h). `Hook#live?` (and the
`live` scope) re-check expiry against the clock rather than trusting the `status`
column, so an old Hook can never suddenly unlock and no sweeper job is required for
correctness. (A cosmetic sweep to flip `pending → expired` can be added when a durable
worker runs.)

### Rate limit is centralized and tiering-ready

`Hooks::Policy` centralizes both the expiry window and a conservative per-sender daily
allowance (`FREE_DAILY_LIMIT = 10` per rolling 24h). `daily_limit_for(profile)` is the
seam for a future Plus tier; nothing about Hook correctness depends on billing.

### Privacy: the sender never learns the outcome

Decline, expiry, and block all collapse to the same sender-visible `hook_state:
unavailable`, indistinguishable from one another. Only the ignored-but-still-live case
reads as `pending`. Hooks are never enumerable by third parties; the inbox is
recipient-only.

## Consequences

- New surfaces: `POST /profiles/{id}/hook`, `GET /hooks` (recipient inbox),
  `POST /hooks/{id}/reply`, `POST /hooks/{id}/decline`, plus a viewer-relative
  `hook_state` on discovery and profile detail (bulk-computed by
  `Hooks::ViewerStates`, no N+1). A live Hook removes the pair from discovery.
- Hook Tonight (a future availability/discovery mode) reuses this exact Hook domain to
  express intent — it does not get its own message mechanism.
- Edge case accepted for V1: if a pair mutually Likes while a Hook is live (only
  reachable by a direct Like API call, since the pair is excluded from discovery),
  they may Match via the Like path. This is genuine mutual interest and is documented
  rather than specially blocked.
- Account closure does not yet discard a closing user's Hooks; closed accounts are
  already excluded from eligibility so their Hooks are inert and expire. Wiring Hooks
  into `Accounts::CloseAccount` is a minor follow-up.

## Open questions

- Sender-withdraw/cancel (the `cancelled` status is reserved but unused).
- Whether to relax one-Hook-per-pair-ever to allow re-Hook after expiry + a cooldown.
- Plus Hook allowances (the policy seam exists; the numbers do not).
