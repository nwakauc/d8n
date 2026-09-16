# ADR 0027: Generic migration-media preflight architecture

## Status

**Accepted** (2026-09-03). Accepted architecture for the Date9ja parity builder's Wave A
"media preflight foundation + profile-photo pass 1"
(`docs/migrations/date9ja-to-d8n/`). Builds on ADR 0022 (external legacy
reference map), ADR 0023 (profile video as a shared Media capability). Needs
independent (Codex) review before the primitives are treated as `VERIFIED`.

Supersedes the ad-hoc `Migration::MediaObjectRef` column sketch in
`STATUS.md` "Wave A slice 5a — BLOCKED AT DESIGN"; the review requested changes,
which this ADR incorporates.

## Context

Migrating Date9ja profile photos (and later profile video, message media, and
verification evidence) onto D8N means reconciling three *different* identities
that legacy Active Storage collapses in the reader's mind:

1. **Source storage object / blob** — one stored byte sequence
   (`active_storage_blobs`). May be referenced by several attachments.
2. **Source attachment / use** — one `(record, name) → blob` link
   (`active_storage_attachments`). For a Date9ja profile photo the authoritative
   link is `record_type = "Photo"`, `name = "image"`, `record_id = Photo.id`.
3. **Destination domain identity** — the D8N `ProfilePhoto` (created only in
   pass 2), bound to the source `Photo` through `Migration::ReferenceMap`.

D8N's shared `ProfilePhoto` is deliberately a "bytes exist in private R2"
record: `image_is_attached`, `image_has_allowed_content_type`,
`image_has_allowed_size` are all `validate … on: :create`, and delivery,
`deliverable?`, every public serializer, and the safe-derivative pipeline assume
a real blob. A migration cannot create a byteless `ProfilePhoto` without
weakening a security-sensitive shared model.

So the migration needs somewhere to record **source media graph + transfer
readiness** that is *not* `ProfilePhoto` and *not* `Migration::ReferenceMap`,
and it must be a reusable platform primitive, not a Date9ja subsystem.

## Decision

### Two generic migration-owned tables

| Primitive | Canonical identity | Owns |
|---|---|---|
| `Migration::MediaObjectRef` (`migration_media_object_refs`) | `(source_system, source_blob_id)` | source-blob integrity metadata + preflight state + **transfer state** |
| `Migration::MediaAttachmentRef` (`migration_media_attachment_refs`) | `(source_system, source_attachment_id)` | one source attachment/use → `media_object_ref_id` + the source record it hangs off |

Both are written only through the model's own idempotent class method
(`MediaObjectRef.preflight!`, `MediaAttachmentRef.record!`) — the same
single-write-path discipline as `Migration::ReferenceMap.bind!`. Neither is read
by consumer-facing code.

A single `MediaObjectRef` may have **many** `MediaAttachmentRef`s (blob reuse).
Attachment identity is never collapsed into blob identity.

### Blob identity vs. checksum

`checksum` / `byte_size` / `content_type` are **integrity metadata**, used to
verify a later byte transfer and to detect drift between runs. They are **not**
domain identity: two `MediaObjectRef`s (or two future `ProfilePhoto`s) with an
identical checksum stay distinct. The tables never deduplicate on checksum.

`source_fingerprint` is a short hash over `(checksum, byte_size, content_type)`
— a fast drift key. A rerun whose source blob metadata differs from the recorded
fingerprint raises `MediaObjectRef::Drift` and the importer fails that row
closed; it never silently overwrites.

### Legacy storage locator handling

Pass 1 **does not read or store** the legacy storage locator
(`active_storage_blobs.key`), `filename`, `metadata`, or `service_name`. The
source SELECT lists name only `id, byte_size, checksum, content_type`. Pass 2's
controlled source-storage adapter re-reads the locator from the restored
snapshot by `source_blob_id` when (and only when) it actually fetches bytes.

If a future pass genuinely needs to persist a locator, it is added as an
`ActiveRecord::Encryption`-encrypted column (mirroring
`DeviceRegistration#token`), never serialized through a consumer API, never
logged, never placed in an exception message or in reconciliation output. Even
sanitized-rehearsal locators are treated as sensitive.

### Transfer-state ownership

The **blob**, not the attachment, is what gets copied, so `transfer_state`
(`not_started / planned / transferred / failed`) and `transferred_at` live on
`MediaObjectRef`. Pass 1 leaves every row `not_started`. The column exists now so
pass 2 needs no schema change and the ownership decision is materialised, not
just documented.

### Relationship to `Migration::ReferenceMap`

`Migration::ReferenceMap` remains the **sole** source→destination domain
identity binding. `MediaObjectRef` / `MediaAttachmentRef` carry **no**
`legacy_reference_id` and **no** `destination_type` / `destination_id`. In pass 2
the reference map binds `date9ja / photo / <source Photo.id> → ProfilePhoto`;
the media tables continue to model only the source graph and transfer state.
Two systems, two jobs, no overlap.

### Idempotency

- `MediaObjectRef.preflight!` upserts by `(source_system, source_blob_id)`;
  identical rerun → `:unchanged`; integrity drift → `Drift`.
- `MediaAttachmentRef.record!` upserts by `(source_system, source_attachment_id)`;
  identical rerun → `:unchanged`; drift in blob / source record / attachment
  name → `Drift`.
- Row-locked inside a transaction; a lost insert race is caught
  (`RecordNotUnique`) and re-resolved through the same drift check.
- The importer never assumes a `ProfilePhoto` exists.

### Cross-brand / cross-source isolation

Every row is namespaced by `source_system`. The same `source_blob_id` under a
different `source_system` is a different object. A Date9ja importer only ever
reads and writes `source_system = "date9ja"` rows.

### Why `ProfilePhoto` is not weakened

Relaxing `ProfilePhoto`'s `on: :create` byte validations (even behind a
`metadata["migration"]` flag) would put undeliverable rows into a
security-sensitive shared model, break `deliverable?` / serializer assumptions,
and leave rows stuck in `processing_state: pending` forever. Instead, pass 1
records the preflight in the migration-owned tables and pass 2 creates a fully
valid `ProfilePhoto` through the normal attach + safe-derivative pipeline.

### Pass-1 vs pass-2 boundary

**Pass 1 (this ADR + the Date9ja photo preflight importer):** read the source
media graph, record `MediaObjectRef` + `MediaAttachmentRef`, resolve whether the
owner profile was imported, produce PII-free reconciliation. No bytes, no
`ProfilePhoto`, no D8N Active Storage records, no processing jobs, no
`ReferenceMap` binding, no reordering, no visibility policy.

**Pass 2 (future, separate slice):** preflight record → controlled
source-storage adapter → fetch bytes → verify checksum/size/content-type →
D8N-owned private storage → valid shared `ProfilePhoto` → existing
processing/safe-derivative pipeline → approved moderation/visibility mapping →
`ReferenceMap` bind `photo → ProfilePhoto` → reconciliation. External object
transfer is not transactional, so pass 2 must make orphaned transferred objects
detectable and quarantinable (`transfer_state` + `transferred_at` on
`MediaObjectRef` are the hook).

### Approved Date9ja pass-2 moderation mapping (recorded, not applied in pass 1)

Authoritative source enum (`/Users/uchechinwaka/pro/Date9ja/api/app/models/photo.rb`):
`pending: 0, approved: 1, rejected: 2`.

| Source | `ProfilePhoto.status` | Visibility |
|---|---|---|
| `pending` | `pending_review` | Date9ja immediate-publication policy (`Media::PhotoPolicy::IMMEDIATE`) |
| `approved` | `approved` | `visible` |
| `rejected` | `rejected` | `hidden` |

Unknown source values fail closed. This does not change Date9ja's existing
publication-policy decision (ADR 0022 / batch 1).

### Approved Date9ja primary-photo mapping (recorded, applied in pass 2)

D8N `ProfilePhoto` has ordering (`position`) but no `is_primary`. Date9ja's
explicit `is_primary` semantics are preserved by ordering:

- exactly one source primary → that photo becomes destination `position 0`;
  the rest keep their relative source order behind it;
- zero source primaries → preserve deterministic source order; `position 0` is
  the effective primary;
- multiple source primaries for one retained profile → **fail closed /
  quarantine for product review**; never pick arbitrarily.

Pass 1 only **measures** these three cases (plus per-owner photo counts and
owners exceeding six photos). It never reorders or normalises.

### Photo-limit handling

D8N's current six-photo maximum is not applied destructively in migration. Pass 1
measures `owners_over_six` and `max_photos_per_owner` and preserves every source
row's evidence; the cap/quarantine decision is a pass-2 product call.

## Scope discipline

Only what the Date9ja photo slice demonstrably needs is built. No
per-provider abstraction, no generic "media migration engine", no speculative
columns beyond `transfer_state` / `transferred_at` (justified above). The same
two primitives are expected to serve the later profile-video, message-media, and
verification-evidence migrations unchanged; if one of those needs more, it adds
it with its own slice and ADR amendment.

## Consequences

- `ProfilePhoto`, `Media::PhotoPolicy`, and the media pipeline are untouched.
- `Migration::ReferenceMap` is untouched (no new destination type in pass 1;
  pass 2 adds `ProfilePhoto`, already in `Migration::DestinationTypes`).
- Two new platform tables, written only by their model's class methods.
- A future locator-persistence need is a small, well-scoped follow-up
  (encrypted column) rather than a redesign.
