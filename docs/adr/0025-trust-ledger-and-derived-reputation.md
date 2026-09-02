# ADR 0025: Trust ledger and derived reputation

## Status

**Accepted** (2026-09-02, independent review) — architecture only; implementation remains gated as stated below. Product owner has decided existing Date9ja Trust XP /
reputation state and relevant history are migration parity. Establishes the
D8N Trust reputation architecture. **This ADR does not decide new scoring rules**
— Date9ja's existing point values migrate as parity configuration. Whether a raw
score, a derived badge, or history is user-visible remains an open product
decision in `DECISIONS.md`; this ADR makes the model support any of those
without a rewrite. Needs independent review before implementation.

## Context — Date9ja source audit

| Source | Shape |
|---|---|
| `trust_events` | append-only positive ledger: `event_type`, `points > 0`, `idempotency_key` (unique), polymorphic `source`, `metadata` jsonb |
| `trust_adjustments` | negative, moderator-applied: `points < 0`, `reason_code`, `actor`, `appeal_status ∈ {not_requested, pending, upheld, overturned}`, `resolved_by`, `idempotency_key` |
| `TrustScore::Backfill` / `TrustScore::Ledger` | reconciles the ledger from pre-ledger facts (email/phone/selfie/video/gov-id verified, photos, profile completion, compatibility completion) with stable idempotency keys; `Ledger.rebuild!` derives the current score |
| `GET /api/v1/trust_scores` (`show`) | runs backfill, returns the user's score |
| point values | e.g. email +25, phone +50 (from `Backfill`); the full table is in the source and migrates verbatim |

## Decision

### Events/ledger → derived state → brand presentation

```
D8N Trust
  → TrustEvent        append-only, positive, idempotent, polymorphic source
  → TrustAdjustment   moderator negative entries, appealable, audited
        ↓  (pure function, rebuildable)
  → derived reputation state   (score + optional band/badge)
        ↓
  brand policy/presentation
    → what (if anything) the user sees
    → whether history is exposed
```

`TrustEvent` and `TrustAdjustment` belong to a platform `User` **but every entry
records the `brand_id` it was earned/applied under** — trust earned on Date9ja is
not silently network-wide (AGENT_RULES: minor brand-level violations do not
become network bans; serious fraud is platform-level only through approved
policy). The derived state is computed per brand context.

The derived reputation is a **pure, rebuildable function** of the entries — never
a stored mutable counter that can drift. `rebuild!` is idempotent and safe to
re-run (as Date9ja's `Ledger.rebuild!` already is).

### Point values are migration parity, not new rules

Date9ja's award table (`event_type → points`) is imported as a versioned
configuration constant (`Trust::Date9jaSchedule` or brand config), preserving
existing user scores exactly. D8N does not change any value, add an award reason,
or introduce a decay/expiry rule in this work. A future D8N-wide trust schedule
is a separate product decision.

### User-visible surface stays a brand decision

The model supports: raw score, score + explanation, derived badge/band only, or
history-private. `DECISIONS.md` "User-visible trust score/history" is unresolved;
until it is answered, the Date9ja migration **preserves whatever the current
Date9ja client shows** (the raw score via `/trust_scores`) as the default, and
any change to that is an explicit product decision, not a migration side effect.

### Adjustments and appeals

`TrustAdjustment` carries the full appeal lifecycle from the source
(`not_requested/pending/upheld/overturned`, `resolved_by`, timestamps). Applying
or resolving an adjustment is an audited admin action (`SecurityEvent`), brand-
scoped. An overturned adjustment is reflected by the rebuild, not by deleting the
row (audit integrity).

### Migration-state preservation

`LegacyReference` (ADR 0022) maps `trust_events` → `TrustEvent` and
`trust_adjustments` → `TrustAdjustment` **by their existing `idempotency_key`**,
so a re-run of the importer plus a post-cutover `rebuild!` produces identical
scores with zero double-counting. `TrustScore::Backfill` logic is ported as the
D8N reconciliation path for any pre-ledger facts that need re-deriving.

## Consequences

- Existing Date9ja trust scores and history migrate exactly, idempotently.
- Auditable events are cleanly separated from user-visible status; the
  presentation decision can be made later without touching the ledger.
- Trust stays brand-scoped by default; network-level escalation remains an
  explicit, approved policy path.
- No new scoring behaviour ships; a future D8N trust schedule is unblocked but
  not implied.

## Alternatives considered

- Copy Date9ja's `TrustScore` service and tables directly. Rejected — keep the
  ledger/derived split and the brand-scoping; port the reconciliation logic, not
  the schema.
- Store a mutable `trust_score` integer on `users`. Rejected — drifts, not
  rebuildable, not brand-scoped.
- Decide the user-visible presentation now. Rejected — that is an open product
  decision; the model is built to defer it.
