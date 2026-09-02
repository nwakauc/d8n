# ADR 0026: Entitlement preservation for migration

## Status

**Accepted** (2026-09-02, independent review) — architecture only; implementation remains gated as stated below. Product owner decision: no migrated user may lose an
existing founding / premium / permanent entitlement because of the D8N
migration. Establishes the **minimum** D8N entitlement model needed to carry
existing rights across cutover. **This ADR does not introduce pricing, plans,
purchase flows, or any new commercial behaviour** — those need explicit product
decisions and their own ADR. Needs independent review before implementation.

## Context — Date9ja source audit

| Source field | Meaning |
|---|---|
| `users.subscription_status` (`enum free:0, premium:1`) | current premium state; "Phase 5 payment webhooks flip this" — no live billing in source |
| `users.premium_expires_at` (datetime, nullable) | premium expiry; null ⇒ no expiry |
| `users.founding_member` (boolean, indexed) | permanent founding grant |
| `User#premium_access?` | `premium? || founding_member? || admin?` |
| `/me` contract | exposes `subscription_status`, `founding_member`, `premium_access` |

There is no Date9ja billing provider, plan catalogue, or purchase history to
migrate — only the **derived access state** on the user.

## Decision

### A brand-scoped `Entitlement` grant record — the minimum

```
D8N PAY / Entitlements  (future shared authority)
  → Entitlement        one granted right, brand-scoped, with a source and optional expiry
        ↓
  brand policy
    → which product capabilities a held entitlement unlocks
```

`Entitlement` belongs to a `BrandMembership` (brand-scoped — a right on Date9ja
is not a right on another brand; AGENT_RULES: entitlements are brand-scoped).
Fields:

- `key` — stable code (`premium`, `founding_member`)
- `source` — how it was granted (`migration`, `grant`, and later `purchase`,
  `promo`)
- `granted_at`, `expires_at` (nullable — null ⇒ permanent)
- `revoked_at` + audit columns
- `metadata` jsonb (bounded; e.g. legacy grant note)

No plan, price, provider, subscription, or invoice model is introduced. The
`pay.*` capability keys stay `planned` except a new `pay.entitlement.hold`
(`available`) that answers only "does this membership currently hold entitlement
X?" — a read used by other capabilities' policy seams.

### Preservation mapping

The importer (ADR 0022 mechanism) creates, per eligible Date9ja user:

- `founding_member = true` → `Entitlement(key: "founding_member", source: "migration", expires_at: nil)`
- `subscription_status = premium` → `Entitlement(key: "premium", source: "migration", expires_at: users.premium_expires_at)`

`admin?` is **not** migrated as an entitlement — admin access is D8N HQ
authorization (ADR 0013/0020), separate from consumer entitlements. Idempotent:
a unique `(brand_membership_id, key)` for active grants means a re-run creates no
duplicates; `LegacyReference` binds the source user for traceability.

### Policy seam, not hard-coded allowances

Where Date9ja code checks `premium_access?` directly (e.g. explore-quota
exemptions), D8N routes that through an entitlement policy seam
(`Entitlements::Holds.for(membership:)` or similar) so a future PAY subsystem can
replace or decorate it without rewriting the consuming capability — exactly the
"hard-coded product allowances must be referenced through policy seams" rule from
the platform remediation plan.

### Explicitly out of scope

- New plans, prices, trials, or tiers
- Purchase / checkout / provider webhook flows
- Subscription renewal, dunning, proration
- Any change to what `premium` unlocks vs. what Date9ja unlocks today

Those are commercial product decisions. This ADR only preserves the rights that
already exist.

## Consequences

- Every existing founding/premium right survives cutover with a defined,
  idempotent mapping and an audit trail.
- Entitlement checks become a policy seam a real PAY subsystem can later own.
- No commercial behaviour ships; the PAY domain stays `planned` apart from the
  one read capability.
- Permanent (`founding_member`, null-expiry) grants are modelled as
  non-expiring, not as a long date.

## Alternatives considered

- Copy `subscription_status` / `founding_member` as `BrandMembership` columns.
  Rejected — cannot express grant source, audit, or multiple concurrent rights,
  and bakes Date9ja's two-value model into the platform.
- Build the full PAY/plans/purchases model now. Rejected — needs pricing product
  decisions; violates "do not invent commercial behaviour".
- Migrate `premium_access?` as a single boolean. Rejected — loses the
  founding-vs-premium distinction and the expiry semantics.
