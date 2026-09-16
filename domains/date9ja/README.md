# `Date9ja::` — source-specific migration adapter boundary

This domain is the **explicitly source-specific Date9ja migration adapter**
referenced by `docs/migrations/date9ja-to-d8n/` and ADR 0022.

Rules (see the task control-plane, "No empires inside kingdoms"):

- Date9ja legacy-schema knowledge (legacy table/column names, legacy enum
  encodings, Date9ja null/default semantics) lives **here** and in
  `scripts/date9ja/*`.
- It must **not** leak into shared `Migration::*` primitives
  (`Migration::ReferenceMap`, `Migration::DestinationTypes`,
  `Migration::SourceSystems`) or into shared D8N domains (`Identity::*`,
  `Profiles::*`).
- This adapter is a **customer** of those shared capabilities: it calls
  `Migration::ReferenceMap.bind!`, `Identity::LoginIdentifier`, and the D8N
  models — it never modifies them to accommodate legacy rows.

## Layout

- `snapshot/` — reads a **restored scratch PostgreSQL** copy of a Date9ja backup
  (never a live connection) and yields canonical `UserRecord`s in deterministic
  order. `Connection` holds the DB-safety fences; `SchemaGuard` runs the shared
  v2 schema signature (`scripts/date9ja/schema_signature.sql`) before any row is
  read.
- `import/` — maps those records onto D8N Identity + Date9ja `BrandMembership` +
  shared `Profile`, binds every destination through `Migration::ReferenceMap`,
  and produces a deterministic, PII-free `Reconciliation`.

Scope of the first slice: **User, IdentityIdentifier, Credential (+ password
hash, copied verbatim), Date9ja BrandMembership, Profile (non-sensitive fields
only), LegacyReference bindings.** Nothing else — no media, no relationship
graph, no verification/trust/entitlements, no sensitive profile fields.
