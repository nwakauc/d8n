# ADR 0028: Migration media byte transfer — source-storage adapter and non-transactional recovery

## Status

**Proposed** (2026-09-03). Extends [ADR 0027](0027-migration-media-preflight-architecture.md)
(media preflight, Accepted) into the byte-transfer phase (Pass 2). Detailed
execution design lives in
[`docs/migrations/date9ja-to-d8n/MEDIA-TRANSFER.md`](../migrations/date9ja-to-d8n/MEDIA-TRANSFER.md),
which this ADR governs. Not implemented — a design checkpoint. Needs
independent (Codex) review and the open product/operator decisions in
MEDIA-TRANSFER.md §"Open" resolved before implementation.

## Context

ADR 0027 deliberately stopped at preflight: `Migration::MediaObjectRef` /
`MediaAttachmentRef` record the source media graph and integrity metadata, no
bytes move, no `ProfilePhoto` is created. Pass 2 must now turn that graph into
real D8N `ProfilePhoto` media.

Two questions ADR 0027 left open:

1. **How does migration code read source storage bytes** without becoming a
   generic cloud-storage abstraction, without embedding legacy credentials in
   app config, and without any Date9ja-storage knowledge leaking into shared
   `Migration::` code?
2. **How is a non-transactional side effect (object upload) made
   deterministically recoverable** when the surrounding DB work
   (`ProfilePhoto` create, `ReferenceMap` bind, processing) can fail
   independently — without duplicate objects, duplicate `ProfilePhoto`s,
   orphaned storage, or silent missing media?

## Decision

### 1. Source-storage adapter — thin, injected, allowlisted

- `Migration::MediaTransfer` (shared) performs verify → upload → mark for **one**
  blob. It knows nothing about legacy schemas or brands. It consumes a
  `source_reader` object and a `Migration::MediaObjectRef`.
- `Date9ja::Storage::SourceReader` (Date9ja adapter) implements the reader
  contract against an S3-compatible endpoint supplied **only** by run-time
  environment (`DATE9JA_SOURCE_R2_*`), with a **hard-coded host allowlist**
  (`*.r2.cloudflarestorage.com` + an explicit rehearsal host). It issues only
  `HEAD`/`GET`. It **fails closed** when config is absent or the host is not
  allowlisted. It never follows a redirect off the allowlist.
- `Date9ja::Snapshot::MediaLocatorSource` (Date9ja adapter) maps
  `source_blob_id → { key, service_name }` from the restored snapshot's
  `active_storage_*` rows, via the existing schema-guarded, column-allowlisted
  snapshot adapter. The legacy storage locator is read **only here**, only at
  transfer time, and is never persisted in a migration table in plaintext, never
  logged, never serialized.
- No generic "storage provider" layer. The only abstraction is "give me the
  bytes + integrity metadata for this `source_blob_id`", implemented once per
  source system.

### 2. Credentials

- Source credentials are **read-only**, bucket-scoped, and exist only in the
  migration run's environment — never in `config/`, `config/deploy.yml`, Rails
  encrypted credentials, or a migration table.
- Destination (D8N R2) credentials are the existing ones, untouched and separate.
- Recommended operator model: a dedicated scoped read-only R2 token (option A);
  a pre-exported controlled bundle (option C) is an acceptable
  hard-boundary alternative. The choice is an open operator decision.
- Migration has **no** code path that writes, deletes, copies, or overwrites a
  source object.

### 3. Non-transactional recovery — deterministic keys + staged state

- **Deterministic destination key.** The destination original object key is a
  pure function of the source blob:
  `object_uuid = UUIDv5("date9ja-photo-transfer-v1", source_blob_id)`, fed to
  `Media::ObjectKey.profile_photo_original`. A retry that already uploaded the
  object reuses the existing `ActiveStorage::Blob` (looked up by key) instead of
  creating a duplicate. The display-derivative key is already deterministic from
  the original key, so `ProcessProfilePhotoJob` retries are safe.
- **Staged `transfer_state`** on `MediaObjectRef`: `not_started → planned →
  transferred / failed`. `planned` (with the intended destination key, stored in
  a new **encrypted** `destination_blob_key` column) is written *before* the
  upload; `transferred` + `transferred_at` *after* the upload is confirmed
  present. A crash between the two leaves a row the next run re-attempts
  idempotently.
- **Per-photo idempotent upsert** keyed on the `ReferenceMap`
  `date9ja/photo/<Photo.id>` binding. Before accepting an existing binding as
  complete, the orchestrator validates the whole destination chain (kept
  `ProfilePhoto`, `image` attached, blob key == the deterministic key,
  owner/brand match, position/status/visibility == the computed plan,
  `transfer_state == transferred`). Any mismatch → `binding_conflict`, fail
  closed. Never auto-heal a partial state without full validation.
- **Orphan detector.** Because every expected destination key is derivable from
  `MediaObjectRef`, a reconciliation pass can list expected vs. actual
  destination objects and flag orphaned transferred blobs (uploaded, never
  attached). Cleanup of an orphan is a **separate explicit operator action**,
  never automatic inside the importer, and never touches an object the importer
  did not create.
- **No distributed-transaction framework** — no saga, no 2PC, no outbox. The
  four mechanisms above (deterministic key, staged state, validated idempotent
  upsert, orphan detector) are the whole design.

### 4. `ProfilePhoto` is still not weakened

Pass 2 creates `ProfilePhoto` through the same `image.attach(blob)` + `save!`
path an ordinary upload uses, running every `on: :create` validation, then
enqueues the existing `Media::ProcessProfilePhotoJob`. The one shared-domain
addition is `Media::PhotoImport` — a thin service beside
`Profiles::PhotoUpload.attach!` that accepts an explicit `position` / `status` /
`visibility` (so migration can set the source-ordered position and the
moderation-mapped state) and otherwise runs the identical verify + attach
sequence. `Profiles::PhotoUpload.attach!` is refactored to call it. This is not
an importer-only permanent media path.

### 5. Reconciliation

Deterministic, PII-free, mutually-exclusive terminal dispositions with the
invariant `photos_considered == Σ dispositions`. Full vocabulary and measures in
MEDIA-TRANSFER.md §15. No storage locator, checksum value, or per-row PII in the
output.

## Consequences

- One new shared service (`Migration::MediaTransfer`) + one new shared thin
  service (`Media::PhotoImport`) + `MediaObjectRef` gains `destination_blob_key`
  (encrypted, nullable) and `destination_service_name`.
- Date9ja adapter gains `Date9ja::Storage::SourceReader`,
  `Date9ja::Snapshot::MediaLocatorSource`, `Date9ja::Import::PhotoTransfer`,
  `PhotoOrderPlan`, `PhotoTransferReconciliation`.
- No change to `Migration::ReferenceMap`, `Migration::DestinationTypes`
  (`ProfilePhoto` already present), `ProfilePhoto`, `Media::PhotoPolicy`, or the
  processing pipeline.
- The same `Migration::MediaTransfer` + adapter pattern is expected to serve the
  later profile-video and message-media migrations.

## Alternatives rejected

- **Relax `ProfilePhoto` create validations for a "migration" flag** — puts
  undeliverable rows in a security-sensitive shared model (already rejected in
  ADR 0027).
- **Wrap upload + DB work in a transaction and rely on rollback** — a rollback
  cannot un-upload an object; leaves orphans with no detector.
- **Random destination keys** — a retry after a crash cannot find its own prior
  upload, producing duplicate objects.
- **A generic `Migration::StorageProvider` abstraction** — no second
  implementation is in demand; build it when video/message media proves a
  different shape is needed.
