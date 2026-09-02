# ADR 0022: External legacy reference map for migrations

## Status

**Accepted** (2026-09-02, independent review). Drafted by the Date9ja parity builder as the minimum
architectural decision required before Wave A slice 2 (reusable external identity
mapping) in `docs/migrations/date9ja-to-d8n/PARITY-BUILD-PLAN.md`. Builds on
ADR 0002 (brand tenancy), ADR 0003 (identity vs brand profiles). Needs
product-owner acknowledgment before any importer code is written. This ADR defines the *reference mechanism* only; the Date9ja *data
mapping* still depends on an approved sanitized snapshot and data dictionary
(non-negotiable gate in `docs/migrations/date9ja-to-d8n/README.md`).

## Context

Migrating the live Date9ja product (and any future acquired/legacy dataset) onto
D8N means creating D8N records that correspond to rows in a foreign system.
Every dependent import step — memberships, profiles, options, photos, likes,
matches, conversations, messages, notifications — must resolve "the D8N record
for legacy X" deterministically, and must be safe to re-run after an
interruption without creating duplicates or crossing tenants.

`docs/migrations/date9ja-to-d8n/AUDIT.md` already specifies the required shape:
a restricted, unique map of `(source system, entity type, source id) → (destination
type, destination id)` plus source fingerprint/version and importer version, with
`find-or-create` semantics under database uniqueness.

The open architectural questions this ADR settles:

1. Is the map a first-class D8N domain, a migration-only table, or reused
   `metadata`?
2. Is a legacy binding immutable once written?
3. Which D8N domain owns it, and does application code ever read it at runtime
   (outside import/reconciliation)?
4. How are source identifiers kept out of D8N public surfaces?

## Decision

### A dedicated migration-owned table, not `metadata`, not per-domain columns

Introduce one table (working name `legacy_references`) owned by a new focused
`Migration` domain module. It is **not** brand-owned in the tenancy sense (it
spans the platform), but every row that resolves to brand-owned data records the
resolved `brand_id` so cross-tenant binding is detectable.

Columns (indicative):

| Column | Purpose |
|---|---|
| `source_system` | e.g. `date9ja` — namespaces every mapping |
| `source_entity` | e.g. `user`, `photo`, `message` |
| `source_id` | the foreign primary key, stored as text |
| `source_fingerprint` | hash/version of the source row at import time |
| `destination_type` / `destination_id` | the D8N record (polymorphic) |
| `brand_id` | resolved brand for brand-owned destinations; null for platform records |
| `importer_version` | the importer build that created/updated the row |
| `created_at` / `updated_at` | audit |

Database invariants:

- `UNIQUE (source_system, source_entity, source_id)` — one destination per source row.
- `UNIQUE (source_system, destination_type, destination_id)` — one source per destination (no accidental many-to-one merge).
- FK on `brand_id`; no FK on the polymorphic destination (records may be soft-deleted independently), but reconciliation verifies resolvability.

### Bindings are immutable

Once `(source_system, source_entity, source_id) → destination` is written, the
destination is never reassigned by an importer. `source_fingerprint` and
`importer_version` may be updated on re-import (to record that the source row was
re-processed), but a change of destination requires an explicit, audited data
migration — never a silent importer decision. This is the "no automatic account
merge" rule (AGENTS.md) applied to migration.

### Import steps resolve through the map; runtime code does not

`Migration::ReferenceMap.resolve(source_system:, source_entity:, source_id:)` is
read-only. `.bind!(...)` is the only write path and uses this algorithm:

1. Normalize the three source-key parts and destination tuple.
2. In a transaction, lock an existing source-key row if present.
3. If it exists, require the destination tuple and brand to match exactly; a
   mismatch raises an immutable-binding error and never updates the row.
4. If it does not exist, insert under both unique constraints. A concurrent
   unique-key failure reloads the conflicting row and performs the same exact
   match check; it never creates a second binding.
5. Only after the binding is verified may fingerprint/importer metadata be
   updated.

Importers and reconciliation read it. **No consumer-facing controller,
serializer, matching, messaging, or trust code reads `legacy_references`.**
Source identifiers never appear in any D8N API response, log line, or public ID;
D8N's existing opaque `public_id` remains the only external handle. Operational
logs may contain a redacted reference-map key or fingerprint for diagnosis, but
never a raw source identifier.

### Tenant safety

Relationship imports (like, match, conversation, block, …) must resolve *both*
endpoints through the map and assert both resolved profiles belong to the same
expected brand before writing the D8N relationship, per AUDIT.md. The
`brand_id` column makes a cross-brand binding a query, not a manual audit.
The binding API must require `brand_id` for every destination type classified as
brand-owned and reject a brand mismatch before persistence. A platform-owned
destination uses a null brand. A single `(source_system, source_entity,
source_id)` can map to only one destination; the same numeric source ID may map
to separate destinations only when its source entity type is different.

### Scope

This ADR covers the reference map only. It does **not** decide: snapshot
access, the Date9ja field/value mappings, bcrypt/session compatibility
(separate ADR), media object copy strategy, or reconciliation report format.
Those remain their own slices/decisions.

## Consequences

- Every importer slice has one deterministic, idempotent, re-runnable resolution
  primitive with DB-enforced uniqueness in both directions.
- Interrupted or repeated imports converge instead of duplicating.
- Cross-tenant binding bugs are detectable by query.
- One new small domain (`Migration`) and one table; no change to any runtime
  domain.
- Legacy IDs are contained: raw IDs exist only in the migration table; importer
  logs use redacted keys/fingerprints, never raw identifiers or PII.
- A genuine re-binding (e.g. a mis-imported account) is deliberately made
  hard — it needs an explicit migration, matching the platform's no-silent-merge
  stance.

## Alternatives considered

- **Store `legacy_id` columns on each domain table.** Rejected: scatters
  migration concerns across every domain, pollutes runtime schemas, and makes
  "one source per destination" hard to enforce globally.
- **Reuse `profiles.metadata` / similar JSON.** Rejected by ADR 0008's rule that
  `metadata` is not used for authorization, reconciliation, or identity.
- **Migration-only throwaway table with no invariants.** Rejected: the binding is
  needed for the rollback window and post-cutover verification (MASTER-PLAN
  phases 9–10), so it must be durable and constrained.
- **Deterministic ID derivation (hash legacy id → D8N id) with no table.**
  Rejected: cannot represent fingerprint/version, cannot detect collisions, and
  cannot support an audited re-binding.
