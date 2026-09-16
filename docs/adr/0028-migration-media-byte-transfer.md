# ADR 0028: Migration media byte transfer — source-storage adapter and non-transactional recovery

## Status

**ACCEPTED (2026-09-03).**
[ADR 0027](0027-migration-media-preflight-architecture.md) (media preflight)
**remains Accepted**. Detailed execution design:
[`docs/migrations/date9ja-to-d8n/MEDIA-TRANSFER.md`](../migrations/date9ja-to-d8n/MEDIA-TRANSFER.md),
which this ADR governs. **Not implemented** — acceptance clears the design for
implementation; it does not mean bytes have moved.

Revision 4 closed the Codex FINAL narrow review's three blockers. The Codex FINAL
**acceptance check** then found one documentation defect — the final storage key
included `original.<ext>` (from `canonical_content_type`) while
`canonical_content_type` was not among the declared canonical-identity fields, so
the key was not technically a total function of the declared identity. That is
now fixed (`canonical_content_type` is a declared field and appears in the
canonical string before the UUIDv5 — `MEDIA-TRANSFER.md` §7). Codex named this as
the **sole remaining blocker** and accepted every other reviewed contract; the
ADR is therefore Accepted.

## Context

The Codex final narrow review of Revision 3 returned BLOCK on three issues
(closed in Revision 4):

1. **Destination key stability** — Revision 3 fed `Brand#slug` and
   `Profile#public_id` (via `Media::ObjectKey.profile_photo_original`) into the
   key; the current D8N models do not guarantee those immutable.
2. **Short attachment lock** — Revision 3 could be read as holding the
   `MediaAttachmentRef` `FOR UPDATE` lock across network / storage / libvips work.
3. **Abandoned processing claim** — a worker that crashes after claiming
   `processing_state = processing` leaves the row stuck forever; a bare timestamp
   does not defeat the ABA race on reclaim.

The FINAL acceptance check then required one documentation fix: add
`canonical_content_type` to the declared canonical identity and string so the
final key is a total function of the declared identity.

## Closed / accepted — not reopened in Revision 4

ADR 0027 is Accepted. These are settled:

1. `Migration::MediaObjectRef` is source-only; no destination columns.
2. `Migration::ReferenceMap` is the sole source→destination **domain** binding.
3. No new migration transfer table.
4. `service_name` census: `cloudflare` = 279 (single service).
5. One destination `ActiveStorage::Blob` per source attachment/use; no
   destination-checksum deduplication.
6. Active Storage cases 2 / 3 / 4 (including **remote-orphan quarantine**, no
   adoption) and per-reuse real remote-byte verification.
7. Source verification order.
8. Synthetic-artifact design — `date9ja_snapshot_sanitized` untouched; distinct
   `date9ja_snapshot_sanitized_media_v2`; synthetic bytes carry their own
   metadata.
9. Source-reader security direction (endpoint from config only, HTTPS only,
   redirects refused, source/destination creds separated, read-only,
   bucket-scoped).
10. Date9ja moderation mapping.
11. Suspended owners retain media structurally.
12. Hybrid pre-copy + final authoritative delta; no automatic destructive
    cleanup.
13. Inference-based recovery concept.
14. **Shared seam — `Profiles::PhotoUpload.build_photo!` extraction. FINAL —
    Codex selected it; there is no A/B choice left, and the standalone-duplication
    fallback is withdrawn.**

## Decision

### 1. `MediaObjectRef` boundary unchanged; no new persistence model

`Migration::MediaObjectRef` / `Migration::MediaAttachmentRef` stay source
evidence only. `Migration::ReferenceMap` remains the sole domain binding.
Destination/transfer state is **inferred** from: the deterministic final key
(§4) → `ActiveStorage::Blob` row + **verified** remote object;
`ReferenceMap.resolve` → `ProfilePhoto`; `ProfilePhoto.processing_state` +
display derivative. `MediaObjectRef.transfer_state` is a coarse hint that
**never overrides observed destination reality**. `MEDIA-TRANSFER.md` §13
confirms the seven Revision-3 corrections do not defeat inference-based recovery;
no table is added. A `migration_media_transfer_attempts` table
(`(source_system, source_attachment_id, destination_purpose, destination_brand)`
→ `state, disposition, attempted_at, failure_code`) is proposed **only if**
independent review requires a durable audit trail.

### 2. Source-storage adapter — thin, injected, allowlisted, with an explicit security contract

- `Migration::MediaTransfer` (shared) performs verify → adopt-or-upload (with
  real remote-byte verification on every reuse) → return a persisted
  object-backed `ActiveStorage::Blob` for one source blob. No legacy-schema or
  brand knowledge.
- `Date9ja::Storage::SourceReader` MUST (`MEDIA-TRANSFER.md` §5b): construct the
  R2 endpoint from `DATE9JA_SOURCE_R2_ACCOUNT_ID` only; **reject any
  caller/DB/argument-provided endpoint**; HTTPS only; **refuse redirects** (`3xx`
  → `source_unavailable` + security event, `Location` never followed);
  bucket-scoped read-only credentials; expose no write/delete/copy method; stream
  with an 8 MB hard ceiling; bounded `0600` temp file `unlink`ed in `ensure`;
  enforce `Media::ImageProcessor` dimension/pixel ceilings; bounded retry +
  backoff; redact provider exceptions; never log credentials, locators, keys,
  signed URLs, or checksums.
- `Date9ja::Snapshot::MediaLocatorSource` reads `source_blob_id → {key,
  service_name}` from the restored snapshot only at transfer time; never
  persisted, never logged.
- No generic "storage provider" layer.

### 3. Migration storage-object key — pure function of immutable migration/storage identity (BLOCKER 1)

Revision 3 fed `Brand#slug` and `Profile#public_id` into the key (via
`Media::ObjectKey.profile_photo_original`); the current D8N models do not
guarantee those immutable. We do **not** impose broad immutability constraints
across D8N, and we do **not** persist a key on `MediaObjectRef`. Instead the
migration storage-object identity is **simplified** to immutable
migration/storage facts only:

```
identity = { version: "migration-media-transfer:v3",
             source_system, source_blob_id, source_attachment_id,
             destination_purpose, destination_brand,   # STABLE migration brand token, checked-in map, NOT Brand#slug
             canonical_content_type }                  # verified detected media type (§6 step 6) — drives <ext>,
                                                       #   so it is a DECLARED identity field

canonical = version +
  "|source_system="          + source_system +
  "|source_blob_id="         + source_blob_id +
  "|source_attachment_id="   + source_attachment_id +
  "|destination_purpose="    + destination_purpose +
  "|destination_brand="      + destination_brand +
  "|canonical_content_type=" + canonical_content_type
# e.g. ...|destination_brand=date9ja|canonical_content_type=image/jpeg

object_uuid = Digest::UUID.uuid_v5(Migration::MediaTransfer::KEY_NAMESPACE, canonical)
final_key   = "migrations/media/v3/" + destination_brand + "/" + destination_purpose + "/" +
              object_uuid + "/original." + Media::ObjectKey.extension_for(canonical_content_type)
           => "migrations/media/v3/date9ja/profile_photo_original/<uuidv5>/original.<ext>"
```

Both `object_uuid` and `<ext>` derive from the **same** `canonical_content_type`,
which is in `canonical`. The final key is therefore a **total deterministic
function of the complete declared identity** — no undeclared input.

**Not in the identity:** `destination_user_id`, `destination_profile_public_id`,
`Brand#slug`, any destination `Profile` mapping input. `Migration::ReferenceMap`
separately binds source `Photo → destination ProfilePhoto` — a different identity
layer (ADR 0027). A verified source content-type change between runs is
`source_changed` (fail closed), surfaced in reconciliation — never a silent
re-key.

The migrated original is **not** routed through
`Media::ObjectKey.profile_photo_original` (that helper necessarily adds
user/profile/slug segments). A dedicated
`Migration::MediaTransfer::CanonicalKey.final_key(identity)` (with
`canonical_content_type` inside `identity`) is the only path that produces the
key. The resulting `ActiveStorage::Blob` is still attached through the normal
`ProfilePhoto` domain seam, and its D8N-side display derivative still lands
beside it via `Media::ObjectKey.derived_key`.

**Mapping drift:** if the owner's `ReferenceMap(profile)` resolution changes
after pre-copy, **no new key is derived** — the object is tied to the immutable
source attachment. Classify `mapping_drift` (a `binding_conflict` sub-reason) and
reconcile explicitly; never a silent re-point or re-upload.

Full string + derivation + drift handling: `MEDIA-TRANSFER.md` §7.

### 4. Active Storage idempotency — explicit cases, no adoption, verify every reuse

`ActiveStorage::Blob` persists the row before the object, `key` is unique, and
**Rails 8.1 has no supported adopt-existing-object API**. For key `K` (=
`final_key`) and expected identity `E = {md5, byte_size, canonical_content_type ∈
allowed, dest_service}` (`MEDIA-TRANSFER.md` §7b):

1. **no row, no object** → serialized `create_and_upload!`, then **re-`HEAD` +
   stream + re-hash** the resulting object vs `E`.
2. **row + object** → reuse **only** after: lock the blob row; key / service /
   checksum / byte_size / content_type all match; **and a real streamed re-read
   of the remote object** → byte count, MD5-base64, magic bytes / decode probe
   all match `E`. Any failure → case 5.
3. **row, no object** (orphan blob row) → lock the blob row; prove key + service
   + checksum + byte_size + content_type; re-verify **source** bytes; then
   `blob.upload_without_unfurling(io)`; then **re-verify the remote result** vs
   `E`. Any missing proof → `binding_conflict` / quarantine. Never upload to an
   existing key without all proofs.
4. **no row, object exists** → **`remote_orphan`**. Do **not** manufacture a blob
   row, do **not** overwrite, do **not** delete. Classify, report PII-free,
   require explicit operator recovery outside the importer. Disposition
   `binding_conflict` (`remote_orphan`).
5. **identity / content ≠ `E`** (or any case-2/3 proof failed) →
   `destination_collision` → `binding_conflict`, quarantine. Never overwrite.
6. **candidate `ProfilePhoto` on a blob whose key ≠ `K`** (or owner / brand /
   `ReferenceMap` chain mismatch) → fail closed → `binding_conflict`.

`upload_without_unfurling` / direct `service.upload` are used only in cases 1 and
3, both serialized (§5) and both followed by real remote re-verification.

### 5. Concurrency control — short attachment lock, no network under it (BLOCKER 2)

**No R2 streaming, remote hashing, upload, or libvips work is ever done while
holding the `Migration::MediaAttachmentRef` `FOR UPDATE` lock** (`MEDIA-TRANSFER.md`
§7c):

- **Phase A — prepare / verify, NO lock held:** load source metadata; stream +
  verify source bytes → `E`; compute `final_key`; inspect destination object
  state; perform the case 1/2/3 storage operation (including the tiny **blob-row
  coordination transaction** — row insert only, no network — and the object
  upload **outside any transaction**); re-verify the resulting remote object;
  prepare the `Blob` + `ProfilePhoto` plan. Two workers may run Phase A
  concurrently — safe **only because** the deterministic storage identity (§3) +
  adopt-or-upload cases 1–5 (§4) make every write a no-op reuse of byte-identical
  content or a fail-closed `binding_conflict`; Phase A creates no domain rows.
- **Phase B — short finalization transaction:** `SELECT MediaAttachmentRef FOR
  UPDATE`; recheck (`MediaObjectRef` mapping, `E` fingerprint, `ReferenceMap`,
  `ActiveStorage::Blob` @ K, Phase-A remote-verification evidence, candidate
  `ProfilePhoto`, owner/profile/brand mapping); if another worker finished →
  `already_transferred`; if mapping changed → `binding_conflict` (`mapping_drift`);
  if source/`E` changed → `source_changed`; else create/reuse the valid `Blob`,
  `Profiles::PhotoUpload.build_photo!`, `ReferenceMap.bind!`, persist. Commit. The
  lock is held only across in-memory rechecks and local DB writes.
- **Phase C — after commit:** `Media::ProcessProfilePhotoJob.perform_later`.

Phase B **serializes DOMAIN creation/binding**: exactly one worker creates the
`ProfilePhoto` + binding. `ReferenceMap` uniqueness is defense-in-depth, not the
primary control. The blob-row coordination transaction is **distinct from** the
`MediaAttachmentRef` finalization lock. Interleavings A+B/crash/commit/rollback
are `MEDIA-TRANSFER.md` §8 rows O–R.

### 6. Processing concurrency + stale-claim recovery (BLOCKER 3 — shared D8N hardening)

A worker that crashes after claiming `processing_state = processing` leaves the
row stuck; a bare timestamp does not defeat the ABA race on reclaim. Fix — the
smallest durable claim (`MEDIA-TRANSFER.md` §16b):

- **Schema:** two nullable columns on `ProfilePhoto` —
  `processing_started_at :datetime` and `processing_claim_token :uuid`. This is a
  `ProfilePhoto` **processing-lifecycle** migration and reusable D8N hardening —
  **not** a migration transfer table. The `processing_state` enum
  (`pending`/`processing`/`ready`/`failed`) is unchanged.
- **CLAIM (short txn):** `ProfilePhoto.lock.find`; `:already_ready` if `ready` +
  valid derivative; from `pending` or retryable `failed` → set `processing`,
  `processing_started_at = now`, `processing_claim_token = SecureRandom.uuid`;
  from `processing` → `:in_progress` if `started_at` recent, else **reclaim**
  (new `started_at` + new token); non-retryable `failed` → `:terminal`.
- **WORK (no txn):** decode → re-encode → strip EXIF/GPS → upload the display
  derivative at its deterministic key (`find_by(key:) || create_and_upload!`).
- **FINALIZE / FAILURE (short txn):** mutate **only when**
  `processing_state == processing AND processing_claim_token == my_token`;
  mismatch → `:lost_claim`, discard the derivative, **do not touch
  `processing_state`**. On success: attach, set `ready`, clear
  `started_at`/`token`, then `image.purge_later`. On failure: set `failed`
  (retryable classification per the existing contract), clear `started_at`/`token`.
- **CRASH AFTER CLAIM:** no rescue code runs; the sweeper later detects stale
  `processing` and the next job's CLAIM reclaims.

**The claim token is required** — `processing_started_at` alone cannot prove the
finalizing worker still owns the current claim (ABA); the proof is in
`MEDIA-TRANSFER.md` §16b. A timestamp + token pair is sufficient — no distributed
lease subsystem.

**Sweeper:** considers `pending` · retryable `failed` · stale `processing`
(`started_at < STALE_THRESHOLD.ago`); never re-enqueues `ready` · non-retryable
`failed` · recent `processing`. Duplicate enqueue stays harmless — only the
current claim token can finalize. Bounded retry via the existing
`retry_on ... attempts: 5`.

### 7. Non-transactional recovery — deterministic key + inference + serialization, no framework

Deterministic migration storage key (§3) + short per-attachment serialization (§5)
+ adopt-or-upload with real remote verification (§4) + validated idempotent bind
+ inference-based recovery + concurrency-safe processing with stale-claim
recovery (§6) + a PII-free orphan detector (`MEDIA-TRANSFER.md` §22). All
crash/concurrency interleavings **A–U** resolved in `MEDIA-TRANSFER.md` §8. **No
saga, no 2PC, no outbox, no workflow engine, no new migration table.**

### 8. Processing enqueue is post-commit

Phase C (§5). `perform_later` is called after the Phase-B transaction commits,
from the orchestrator explicitly (not an `after_commit` callback). A job is never
enqueued against a row that later rolls back. A post-commit enqueue failure
leaves a `pending` `ProfilePhoto` with no job; the sweeper re-enqueues it
(harmless under §6). A photo is not `transferred` until `processing_ready`.

### 9. `ProfilePhoto` not weakened — minimal internal seam (FINAL)

The one shared-code change is a **minimal extraction**:
`Profiles::PhotoUpload.build_photo!(profile:, user:, brand:, blob:, position:,
status:, visibility:)`, called by `attach!` (policy-derived args, unchanged
behaviour) and by migration (explicit args). **It is an internal domain helper**
that owns `ProfilePhoto` domain invariants (validity, owner/profile/brand,
capacity, attachment invariants) — **not request authorization**, which stays
solely with the HTTP `attach!` path. Migration is trusted offline infrastructure
that still obeys every domain invariant. No new `Media::` class. Migration
specifics stay in `Date9ja::Import::*` / `Migration::MediaTransfer`. **Codex
selected this in the final review — there is no A/B choice; the
standalone-duplication fallback is withdrawn.** Regression surface + tests:
`MEDIA-TRANSFER.md` §23–24.

### 10. Synthetic rehearsal — a distinct versioned artifact

`date9ja_snapshot_sanitized` is **not** rewritten or relabelled — it stays the
verified sanitized **source** rehearsal artifact. A **distinct**
`date9ja_snapshot_sanitized_media_v2` is designed (`MEDIA-TRANSFER.md` §21): it
preserves the canonical sanitized source graph but rewrites `active_storage_blobs`
metadata for the synthetic photo corpus to the generated bytes' real
MD5/size/type, and carries its own generation procedure, manifest,
checksum/fingerprints, sanitizer/verifier result, Pass-1 rerun, and
reconciliation baseline. `v2` does not replace `v1`; `v2` synthetic evidence does
not supersede `v1` identity/Pass-1 evidence. The production transfer path runs
unchanged — no test-only branch. **Not created in this design turn.**

### 11. Reconciliation

Deterministic, PII-free, mutually-exclusive terminal dispositions;
`photos_considered == Σ dispositions`; every non-success disposition additionally
`unexplained_failure` or `reviewed_exception`; cutover requires
`unexplained_failure == 0`. Any reused destination object at final delta gets the
same real remote-byte re-verification. No storage locator, checksum value, or
per-row PII in the output. Full vocabulary and measures in `MEDIA-TRANSFER.md`
§15.

## Consequences

- One new shared service (`Migration::MediaTransfer` + `CanonicalKey` pure
  functions) + a minimal internal extraction of
  `Profiles::PhotoUpload.build_photo!` + concurrency + stale-claim hardening of
  the existing `Media::ProcessProfilePhotoJob` (benefits native uploads too).
- **No new migration table. No new columns on any migration model.**
- **Two nullable columns on `ProfilePhoto`** (`processing_started_at`,
  `processing_claim_token`) — `ProfilePhoto` processing-lifecycle hardening, not
  migration transfer identity.
- A dedicated migration key scheme (`migrations/media/v3/...`) — the migrated
  original does **not** use `Media::ObjectKey.profile_photo_original`.
- Date9ja adapter gains `Date9ja::Storage::SourceReader`,
  `Date9ja::Snapshot::MediaLocatorSource`, `Date9ja::Import::PhotoTransfer`,
  `PhotoOrderPlan`, `PhotoTransferReconciliation`.
- Per-attachment serialization uses an existing row lock; no new lock
  infrastructure.
- A new rehearsal artifact (`date9ja_snapshot_sanitized_media_v2`) to build and
  verify before L2.
- No change to `Migration::ReferenceMap`, `Migration::DestinationTypes`,
  `Migration::MediaObjectRef`, `Migration::MediaAttachmentRef`, the
  `ProfilePhoto` **enum/state model**, or `Media::PhotoPolicy`.
- The same `Migration::MediaTransfer` + adapter pattern is expected to serve the
  later profile-video and message-media migrations.

## Alternatives rejected

- **Automatic Active Storage adoption of a remote orphan** — Rails 8.1 has no
  supported API; manufacturing a blob row for an object we cannot prove we own is
  unsafe. Case 4 is quarantine + operator recovery.
- **Reuse a destination blob on `ActiveStorage::Blob` metadata alone** — a
  tampered or corrupted object with matching row metadata would be trusted; every
  reuse now re-streams and re-hashes the real object.
- **Routing the migrated original through `Media::ObjectKey.profile_photo_original`**
  — it embeds `Brand#slug` / `User#id` / `Profile#public_id`, none guaranteed
  immutable; a dedicated `migrations/media/v3/...` key depends only on immutable
  migration/storage identity.
- **Feeding destination user / profile / slug into the migration key** (Rev 3) —
  a brand rename or profile re-provisioning would move the expected object; the
  key now carries none of them, and mapping drift is a `binding_conflict`, not a
  re-key.
- **Broad D8N immutability constraints on `Brand#slug` / `Profile#public_id`** —
  out of scope and unnecessary once the key stops depending on them.
- **Leaving `canonical_content_type` out of the declared identity** (Rev 4 as
  first written) — it drives `<ext>`, so the key would not be a total function of
  the declared identity; it is now a declared field hashed into `object_uuid`.
- **`ReferenceMap` uniqueness as the primary concurrency control** — it is
  defense-in-depth; a `MediaAttachmentRef` row lock is the primary control.
- **A new lock table / a new migration transfer-attempt table** — an existing row
  lock and inference-based recovery suffice.
- **Holding the `MediaAttachmentRef` lock across network / hashing / upload /
  libvips work** — Phase A does all of that with no lock held; Phase B is a short
  finalization transaction.
- **A long DB transaction across libvips work in `ProcessProfilePhotoJob`** —
  claim / work-outside / finalize instead.
- **A bare `processing_started_at` timestamp for claim ownership** — an ABA race
  lets a stale worker finalize a newer claim; a per-claim
  `processing_claim_token` is required.
- **A distributed lease / lock subsystem for processing** — a timestamp + token
  pair on `ProfilePhoto` is sufficient and simple.
- **Rewriting `date9ja_snapshot_sanitized` in place** — it is verified evidence;
  a distinct `_media_v2` artifact instead.
- **Destination state on `MediaObjectRef`** (Rev 1) — withdrawn.
- **A default `migration_media_transfer_attempts` table** — inference-based
  recovery is sufficient.
- **`after_commit` model callback for enqueue** — explicit post-commit
  orchestration is more deterministic.
- **Sharing one D8N blob across `ProfilePhoto` uses** — unsafe under D8N's
  raw-blob purge lifecycle.
- **Relax `ProfilePhoto` create validations for a "migration" flag** — rejected
  in ADR 0027; still rejected.
- **A generic `Migration::StorageProvider` abstraction** — no second
  implementation is in demand.

## Acceptance

Every blocker from every Codex review (Rev 1 → Rev 4 → the FINAL acceptance
check) is closed in-design. The shared-seam choice is FINAL. The final migration
storage key is a total function of the complete declared canonical identity
(§3). **No unresolved architecture or product decision remains — this ADR is
ACCEPTED.**

**Implementation readiness:**

- **Pass 2 implementation: READY.**
- **L1 / L2: READY AFTER IMPLEMENTATION** (the `date9ja_snapshot_sanitized_media_v2`
  synthetic artifact must be built first — `MEDIA-TRANSFER.md` §21).
- **L3 (real R2): NOT YET READY** — blocked on operator logistics (R2 token
  custody, `STALE_THRESHOLD` / drain-timeout values, freeze-window length,
  bulk-copy destination confirmation), which are execution parameters, not
  decisions.

Profile-photo capability overall remains **PARTIAL — not `PARITY_ACCEPTED`, not
production-ready, not cutover-ready.** Acceptance of this ADR clears the design
for implementation; no bytes have moved.
