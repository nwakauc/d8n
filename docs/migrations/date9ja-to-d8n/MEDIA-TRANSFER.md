# Date9ja → D8N media transfer (profile-photo Pass 2) — execution design

**Status: DESIGN CHECKPOINT (2026-09-03). Not implemented.** Architecture
authority: [ADR 0027](../../adr/0027-migration-media-preflight-architecture.md)
(preflight, Accepted) + [ADR 0028](../../adr/0028-migration-media-byte-transfer.md)
(byte transfer + recovery, Proposed). Linked from `STATUS.md`. This file is
detailed execution design; it does not create new phase/decision authority.

Pass 1 (media preflight) is VERIFIED. This document specifies how the
preflighted `Migration::MediaObjectRef` / `MediaAttachmentRef` graph becomes real
D8N `ProfilePhoto` media, safely and idempotently, without weakening any shared
guarantee.

---

## 1. Rehearsal evidence carried in (Pass 1, sanitized, VERIFIED 2026-09-03)

| | first pass | second pass |
|---|---:|---:|
| `photos_considered` / `balanced` | 279 / true | 279 / true |
| `preflighted` | 276 | 0 |
| `already_preflighted` | 0 | 276 |
| `owner_not_imported` | 3 | 3 |
| `unavailable` / `malformed` / `failed` / `explicitly_skipped` | 0 | 0 |
| `MediaObjectRef` / `MediaAttachmentRef` created | 279 / 279 | 0 / 0 |

Stable measures: 279 photos · moderation 2 pending / 266 approved / 11 rejected ·
164 primary rows · `owners_total` 166 · `owners_with_one_primary` 164 ·
`owners_with_zero_primary` 2 · `owners_with_multiple_primary` 0 · `owners_over_six`
0 · `max_photos_per_owner` 6 · `owners_suspended` 3 · every anomaly counter 0 ·
`blob_reuse_objects` 0.

The 3 `owner_not_imported` photos and the 3 `owners_suspended` are **not** proven
to be the same accounts — the aggregate output does not establish that, and Pass 2
must not assume it.

---

## 2. Authoritative legacy storage findings

Inspected `/Users/uchechinwaka/pro/Date9ja/api/config/storage.yml`,
`config/environments/{production,development}.rb`, `config/deploy.yml`,
`app/models/photo.rb`. No network calls, no credentials read.

| Question | Finding |
|---|---|
| Production Active Storage service | `:cloudflare` → Active Storage **`S3` service** pointed at **Cloudflare R2** (`https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com`), `force_path_style: true`, `region: auto`. R2 speaks the S3 API; `aws-sdk-s3` is the client. |
| Bucket | Single bucket from `ENV["CLOUDFLARE_R2_BUCKET"]`. No per-brand/per-env split. |
| `blob.key` → object | Active Storage default: `key` is a random ~28-char token, stored **flat at the bucket root** (Date9ja `Photo` does not customise `key`). The object is `GET <bucket>/<key>`. No path structure, so no traversal surface from the key itself. |
| Credentials source | `ENV` only — `CLOUDFLARE_R2_ACCESS_KEY_ID`, `CLOUDFLARE_R2_SECRET_ACCESS_KEY`, `CLOUDFLARE_R2_BUCKET`, `CLOUDFLARE_ACCOUNT_ID` (Kamal secrets). **Not** Rails encrypted credentials. The current keys are full read/write on the bucket. |
| Object privacy | Private. The S3 service issues no public URLs; the app serves photos through `rails_blob_path` redirects/proxy. |
| Variants / previews | `Photo` declares only `has_one_attached :image` — **no declared variants**. `active_storage_variant_records` (census ~70) are derived thumbnails, regenerated D8N-side, **not migrated**. |
| Original bytes retrievable | Yes — `GET` the object by key returns the exact uploaded bytes. |
| `service_name` relevance | Blobs created in production carry `service_name = "cloudflare"`. Pass 2 must read `active_storage_blobs.service_name` and **refuse anything other than the expected legacy service** (fail closed). A census of distinct `service_name` values is a Pass-2 preflight input (Pass 1 did not read it — see gap below). |
| Historical / multiple services | Production has used `:cloudflare` since the 2026-07-11 R2 addendum; a small number of pre-cutover blobs *could* carry `service_name = "local"` or `"amazon"`. Treat any non-expected value as `source_unavailable` / quarantine, never guess an endpoint. |
| Structurally-valid graph, missing object | **Possible.** `active_storage_attachments` → `active_storage_blobs` is FK-clean, but the R2 object for a blob key can be absent (failed upload that still wrote the blob row, lifecycle deletion, manual ops). Pass 2 `HEAD`/`GET` is the authority; a missing object is a per-photo `source_unavailable`, not a graph error. |
| Checksum semantics | Rails `ActiveStorage::Blob#compute_checksum_in_chunks` → `OpenSSL::Digest::MD5` streamed → `.base64digest` (24-char base64, `Content-MD5` style). **Legacy Date9ja and D8N run the same Rails 8.1**, so the value already in `MediaObjectRef.checksum` is directly comparable to a freshly computed MD5-base64 of the transferred bytes. MD5 is a transit-integrity check, not a security control — structural decode validation is the real gate (§6). |

### Pass-1 gap to close before Pass 2

`MediaObjectRef` did **not** record `active_storage_blobs.service_name`. Pass 2's
first step is a **read-only source census extension** (via the existing Date9ja
snapshot adapter, schema-guarded) that reports the distribution of
`service_name` over the 279 photo blobs and confirms every value is the single
expected legacy service. If any blob is on an unexpected service, that is a
**global blocker** until classified (§17).

---

## 3. Proposed Pass 2 architecture

```
Migration::MediaObjectRef (preflighted, per source blob)
  └─ Date9ja::Storage::SourceLocator      # date9ja-only: source_blob_id -> {key, service_name, expected md5/size/type}
       (reads the restored snapshot's active_storage_* rows via the existing
        schema-guarded Date9ja snapshot adapter — NOT a live Date9ja connection)
  └─ Migration::MediaTransfer.call(object_ref:, source_reader:, ...)   # shared, reusable
       1. resolve locator (via the injected source_reader)
       2. stream source bytes  (bounded, temp-file, size-capped)
       3. verify: size, MD5-base64, magic bytes, libvips decode   (§6)
       4. allocate a DETERMINISTIC destination key (Media::ObjectKey + source_blob_id seed)
       5. upload to D8N-owned private storage (ActiveStorage::Blob.create_and_upload!, idempotent on key)
       6. set MediaObjectRef.transfer_state = transferred, transferred_at
  └─ Date9ja::Import::PhotoTransfer   # date9ja-only orchestrator (mirrors PhotoImport)
       per source Photo, in source order per owner:
       a. resolve owner Profile via Migration::ReferenceMap (profile entity)   -> owner_not_imported if absent
       b. ensure the blob is transferred (Migration::MediaTransfer, idempotent)
       c. Media::PhotoImport.attach!(profile:, blob:, position:, status:, visibility:)   # shared, NEW thin service
       d. Migration::ReferenceMap.bind!(date9ja/photo/<Photo.id> -> ProfilePhoto, brand: date9ja)
       e. enqueue the existing Media::ProcessProfilePhotoJob
  └─ Date9ja::Import::PhotoTransferReconciliation   # PII-free, §15
  └─ Date9ja::Import::PhotoOrderPlan                # deterministic ordering, §11
```

Byte streaming, verification, deterministic-key allocation, destination upload,
and `transfer_state` bookkeeping are **shared** `Migration::` primitives, source-
system-agnostic. Everything that knows a legacy table/column or the Date9ja
brand stays in `Date9ja::`.

---

## 4. Class / module ownership

| Unit | Layer | Responsibility |
|---|---|---|
| `Migration::MediaTransfer` | shared migration | Given an `object_ref` + an injected `source_reader`, perform verify→upload→mark for exactly one blob. Idempotent on the deterministic destination key. No brand knowledge, no legacy-schema knowledge. |
| `Migration::SourceObject` (Data) | shared migration | `{ byte_size, checksum, content_type, io }` handed back by a source reader — the only shape `MediaTransfer` consumes. |
| `Migration::MediaObjectRef` (exists) | shared migration | Gains `transfer_state` transitions (`not_started → planned → transferred / failed`) and, **new**, a nullable **encrypted** `destination_blob_key` + `destination_service_name` set at transfer time so a rerun/orphan-detector can find the destination object without re-deriving it. (Locator stays source-side and unpersisted; this is the *D8N-owned* key, non-secret but kept out of consumer surfaces.) |
| `Date9ja::Storage::SourceReader` | date9ja adapter | Implements the `source_reader` contract against an **explicitly configured** source-storage endpoint (§5). SSRF-safe (§19). Read-only. |
| `Date9ja::Snapshot::MediaLocatorSource` | date9ja adapter | `source_blob_id → { key, service_name, expected md5/size/type }` from the restored snapshot's `active_storage_*` rows (schema-guarded, column-allowlisted, same fences as Slice 3). |
| `Date9ja::Import::PhotoTransfer` | date9ja adapter | The Pass-2 orchestrator. Owns owner resolution, ordering, moderation mapping, `ReferenceMap` binding, reconciliation. |
| `Date9ja::Import::PhotoOrderPlan` | date9ja adapter | Pure function: `[source Photo rows for one owner] → [{photo, destination_position}]` (§11). |
| `Date9ja::Import::PhotoTransferReconciliation` | date9ja adapter | PII-free tally (§15). |
| `Media::PhotoImport` | shared media | **New thin service** beside `Profiles::PhotoUpload.attach!`: takes an already-persisted D8N blob + explicit `position` / `status` / `visibility`, runs `verify_uploaded_object!` (magic bytes + real size + content-type reconciliation), creates the `ProfilePhoto` through the normal `image.attach` path, returns it. Reuses `Media::PhotoPolicy`, `ProfilePhoto` validations, `Media::StorageResolver.compatible_service?`. Does **not** call `PhotoOrder.prepare_insert!` (caller supplies the position). |

`Media::PhotoImport` is the one shared-domain addition. It is *not* an
importer-only permanent path — it is the same attach+verify sequence
`Profiles::PhotoUpload.attach!` already performs, factored so a non-HTTP caller
(migration today, an admin tool tomorrow) can supply position/status explicitly.
`Profiles::PhotoUpload.attach!` is refactored to call it.

---

## 5. Source credential / access model

**Requirements met:** no broad permanent production-storage credentials in app
config; no credentials in migration tables or logs or docs; explicit opt-in
config; fail closed when absent; source and destination credentials fully
separate; source access read-only; migration never deletes/mutates/overwrites a
source object.

Options considered:

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A. Read-only legacy R2 credentials** — a dedicated R2 API token scoped **read-only** to the legacy bucket, provided to the migration process via `DATE9JA_SOURCE_R2_*` env at run time only | Exercises the real transfer path; no export step; delta re-runs are trivial | Requires the operator to mint a scoped token in Cloudflare; the migration host briefly holds credentials that can read all legacy media | **Recommended for controlled full rehearsal + cutover** |
| B. Temporary scoped credentials (STS-style, short TTL) | Smallest blast radius | R2 does not offer STS/short-lived keys the way AWS does; would need a custom vending service — overbuild | Rejected |
| C. Pre-exported controlled media bundle — operator `rclone`/`aws s3 sync` the legacy bucket into a D8N-controlled private prefix once, migration reads only that | Migration never touches legacy credentials at all; the export is a clean audit boundary; re-runnable against a frozen copy | Adds a large copy step + storage cost; delta handling moves to the export tool; still needs legacy read creds *somewhere* | **Recommended as the fallback / for the final pre-cutover full proof if minting a scoped token is not acceptable** |
| D. Other | — | — | — |

**Recommendation:** **A** for the working model (scoped **read-only** token,
`DATE9JA_SOURCE_R2_ACCESS_KEY_ID` / `_SECRET` / `_BUCKET` / `_ENDPOINT`, present
only in the migration run's environment, never in `config/`, `deploy.yml`, or
Rails credentials), with **C** available if the operator prefers a hard
credential boundary. Both keep destination (D8N R2) credentials untouched and
separate. `Date9ja::Storage::SourceReader` **fails closed** (raises, no
fallback) if the source env is unset or the endpoint host is not on the
allowlist (§19).

**Open — operator decision required:** A vs C, and who mints/holds the scoped
token.

---

## 6. Byte-verification algorithm (exact order, streamed, bounded memory)

Per source blob, `Migration::MediaTransfer`:

1. **Expected values** from `MediaObjectRef`: `source_blob_id`, `byte_size`
   (may be nil for a Pass-1 failure row — those are not transferred),
   `checksum` (MD5-base64), `content_type` (declared).
2. **`HEAD`/metadata** the source object. Missing → `source_unavailable`
   (per-photo). Provider error / redirect off the allowlisted host →
   `source_unavailable` + security event (§19).
3. **Stream** the object to a private temp file (mode `0600`, `Dir.mktmpdir`
   under a migration-only root), reading in ≤ 5 MB chunks, **aborting the moment
   the running byte count exceeds `8 MB` + slack** (Date9ja `Photo::MAX_FILE_SIZE`
   is 8 MB; D8N `ProfilePhoto::MAX_FILE_SIZE` is 10 MB — use the **lower**, 8 MB,
   as the hard ceiling). Oversize → `validation_failed` (`oversize`).
4. **Actual byte count** must equal `MediaObjectRef.byte_size` when that is
   known; mismatch → `source_changed` (fail closed — the source object is not
   what we preflighted).
5. **MD5-base64** of the streamed bytes must equal `MediaObjectRef.checksum`.
   Mismatch → `source_changed`.
6. **Magic-byte signature** (`Profiles::PhotoUpload.detect_image_type` — the
   existing authority: `FF D8 FF` JPEG, `89 PNG…` PNG, `RIFF…WEBP` WebP). `nil`
   → `validation_failed` (`not_an_image`). The declared `content_type` header is
   **never trusted**; the detected type wins.
7. **Detected type ∈ {image/jpeg, image/png, image/webp}** — the intersection of
   Date9ja and D8N allowed types. Anything else → `validation_failed`
   (`unsupported_content_type`). (Pass 1 already found 0 unsupported, but the
   check is unconditional.)
8. **Decode-safety probe** — `Media::ImageProcessor` header read only
   (`MAX_SOURCE_DIMENSION` 12 000 px/edge, `MAX_SOURCE_PIXELS` 40 MP
   decompression-bomb ceiling). A file that fails the probe →
   `validation_failed` (`malformed_image`). This is the real safety gate; MD5 is
   only transit integrity.
9. Only now is the object eligible for upload (§8).

All checks stream; peak memory is one 5 MB chunk + libvips header state. The temp
file is `unlink`ed in an `ensure` whether or not any step raised.

---

## 7. Destination `ProfilePhoto` integration path

Imported photos must be **indistinguishable from a legitimately uploaded D8N
photo**. Pass 2 therefore reuses the exact D8N attach + processing sequence:

1. `Media::ObjectKey.profile_photo_original(brand:, user:, profile:, content_type:, object_uuid:)`
   with `object_uuid` **seeded deterministically from `source_blob_id`** (§8) so
   the key is stable across reruns.
2. `ActiveStorage::Blob.create_and_upload!(io:, key:, filename: "photo.<ext>",
   content_type: <detected>, service_name: Media::StorageResolver.service_name(brand:))`
   — writes the **verified** bytes to D8N's own private R2. Idempotent: if a blob
   with that key already exists (a prior partial run), reuse it after
   re-verifying its size/checksum (§9).
3. `Media::PhotoImport.attach!(profile:, brand:, blob:, position: <PhotoOrderPlan>,
   status: <moderation map>, visibility: <moderation map>)` — creates the
   `ProfilePhoto` through `image.attach(blob)` + `save!`, running every
   `on: :create` validation (`image_is_attached`, content-type, size,
   `within_brand_photo_limit`, `profile_matches_scope`). The migration passes an
   explicit position and moderation-derived status/visibility instead of the
   brand default.
4. `Migration::ReferenceMap.bind!` (§10).
5. `Media::ProcessProfilePhotoJob.perform_later(photo.id)` — the **same** safe-
   derivative pipeline (decode → re-encode → strip EXIF/GPS → store display
   derivative → purge raw). No bypass of processing, private storage, ownership,
   moderation, brand policy, or delivery constraints.

Nothing about the resulting row, blob, key shape, processing, or delivery
differs from an ordinary upload except that the raw bytes arrived from a
server-side stream instead of a browser PUT.

---

## 8. External side effect + DB transaction — recovery design

Storage upload is a non-transactional side effect. The design makes every step
**idempotent and individually recoverable** rather than attempting distributed
atomicity.

### Deterministic destination key

`object_uuid = UUIDv5(namespace = "date9ja-photo-transfer-v1",
name = source_blob_id)`. The destination original key is therefore a pure
function of the source blob. Consequences:

- A retry that already uploaded the object **reuses the same blob** (key
  collision → `ActiveStorage::Blob.find_by(key:)` first), never a duplicate
  object.
- The display-derivative key is already deterministic from the original key
  (`Media::ObjectKey.profile_photo_display`), so `ProcessProfilePhotoJob` retries
  are safe.
- An **orphan detector** can list every expected destination key from
  `MediaObjectRef` and diff against what exists.

### Staged transfer state (on `MediaObjectRef`)

`not_started → planned → transferred → failed`. `planned` is written **before**
the upload starts (with the intended `destination_blob_key`); `transferred` +
`transferred_at` **after** the upload is confirmed (`service.exist?` +
re-`HEAD` size). A process that dies between `planned` and `transferred` leaves a
row that the next run re-attempts: it checks whether the destination object
already exists (deterministic key) and either adopts it (after re-verify) or
re-uploads over the same key.

### Per-photo state machine (Pass-2 orchestrator, on the `photo` ReferenceMap + destination)

| Observed state | Action |
|---|---|
| `ReferenceMap(photo)` resolves + `ProfilePhoto` present + `image` attached + `MediaObjectRef.transfer_state = transferred` + position/status/visibility match the plan | `already_transferred` — no-op |
| blob transferred, no `ProfilePhoto` | create `ProfilePhoto` + bind + enqueue processing (resume) |
| `ProfilePhoto` exists, no `ReferenceMap(photo)` binding | **do not auto-heal.** Verify the `ProfilePhoto` was created by this importer (its blob key matches the deterministic key for this `source_blob_id`) AND owner/brand/position/status match the plan; only then bind. Any mismatch → `binding_conflict`, fail closed. |
| `ReferenceMap(photo)` binding exists but points at a `ProfilePhoto` whose blob key ≠ deterministic key, or whose owner/brand differ | `binding_conflict`, fail closed |
| processing job failed (`processing_state = failed`) | `processing_failed` — photo row exists and is bound, but not deliverable; re-enqueueable |

No step deletes a destination object or `ProfilePhoto` it did not create. Cleanup
of a genuinely orphaned transferred blob (uploaded, never attached, older than a
grace window) is a **separate, explicit, logged operator action**, never
automatic inside the importer.

### Smallest reliable mechanism (not a transaction framework)

Deterministic keys + staged `transfer_state` + idempotent upsert + an orphan
detector + fail-closed conflict handling. No sagas, no 2PC, no outbox.

---

## 9. Idempotency contract (Pass 2 rerun)

Per source `Photo`, exactly one terminal disposition (§15). Rerun rules:

| Prior state | Rerun result |
|---|---|
| fully transferred + bound + processed, everything matches the plan | `already_transferred`, zero writes |
| bytes uploaded (`transfer_state = transferred`), no `ProfilePhoto` | resume: create + bind + enqueue |
| `ProfilePhoto` exists, no binding | bind **only after** strict validation (blob key == deterministic key, owner/brand/position/status/visibility == plan); else `binding_conflict` |
| `ReferenceMap(photo)` exists | validate the whole destination chain (`ProfilePhoto` kept, `image` attached, blob key deterministic, owner/brand match, position/status/visibility match plan, `MediaObjectRef.transfer_state = transferred`); all-good → `already_transferred`; any gap → `binding_conflict` / `processing_failed` as applicable, fail closed |
| destination drift (position/status/visibility no longer match the plan, or blob replaced) | `binding_conflict`, fail closed — never silently re-mutate |
| source bytes changed since preflight (size or MD5 ≠ `MediaObjectRef`) | `source_changed`, fail closed |

**Invariant proven by rehearsal:** a second complete run creates **zero**
duplicate `ProfilePhoto` rows and **zero** duplicate destination storage objects.

---

## 10. `Migration::ReferenceMap` contract

```
source_system    = "date9ja"
source_entity    = "photo"
source_id        = <legacy Photo.id, as text>
destination_type = "ProfilePhoto"        (already in Migration::DestinationTypes, brand-owned)
destination_id   = <D8N ProfilePhoto.id>
brand            = the date9ja Brand     (ReferenceMap enforces destination.brand_id == brand.id)
importer_version = "date9ja-photo-transfer-v1"
fingerprint      = digest(source position, is_primary, moderation_status, source_blob_id)
```

Source **blob** ids are **never** bound to `ProfilePhoto` — blob identity stays
in `MediaObjectRef`. Before accepting an **existing** `photo` binding as
complete, the orchestrator validates: destination `ProfilePhoto` is kept;
`image` attached; the blob's key equals `UUIDv5(source_blob_id)`-derived key;
`profile.user_id`/`brand_id` match the resolved owner; `position` == the
`PhotoOrderPlan` result; `status`/`visibility` == the moderation map;
`MediaObjectRef.transfer_state == transferred`. Any failure → `binding_conflict`.

---

## 11. Deterministic ordering algorithm (design only — NOT applied this checkpoint)

Input: the owner's source `Photo` rows. Decided mapping (DECISIONS.md / ADR 0027):

```
def plan(source_photos):
    ordered = source_photos.sort_by { |p| [p.position, p.id] }   # deterministic, ties broken by id
    primaries = ordered.select(&:is_primary)
    raise MultiplePrimary if primaries.length > 1                 # -> quarantine, never guess
    if primaries.length == 1:
        primary = primaries.first
        rest = ordered.reject { |p| p.id == primary.id }
        result = [primary] + rest
    else:
        result = ordered                                          # position 0 == effective primary
    result.each_with_index.map { |photo, i| { photo:, destination_position: i } }
```

Destination positions are `0..n-1`, contiguous, gap-free — consistent with
`index_profile_photos_on_profile_id_and_position` (unique where kept). Rehearsal
expectation: 164 owners take the one-primary branch, 2 take the zero-primary
branch, 0 hit `MultiplePrimary`.

---

## 12. Moderation / visibility mapping — representability check

| Source `moderation_status` | `ProfilePhoto.status` | `ProfilePhoto.visibility` |
|---|---|---|
| `pending` (0) | `pending_review` | `visible` (Date9ja `:immediate` policy — `Media::PhotoPolicy::IMMEDIATE`) |
| `approved` (1) | `approved` | `visible` |
| `rejected` (2) | `rejected` | `hidden` |
| anything else | — | **fail closed** (`moderation_unmapped`, quarantine) |

**Representable cleanly today — no shared-model change needed.**
`ProfilePhoto` has `enum status { pending_review, approved, rejected }` and
`enum visibility { hidden, visible }` as independent columns, exactly matching
the three target states. `Media::PhotoPolicy::IMMEDIATE` is already
`{status: :pending_review, visibility: :visible}`. `ProfilePhoto.deliverable?` /
`moderation_publicly_eligible` (`status IN (pending_review, approved)` AND
`visible` AND `processing_ready`) reproduce Date9ja's "pending & approved shown,
rejected hidden" behaviour without any change. `rejected + hidden` is delivered
to nobody, matching legacy. No gap.

The migration sets `status`/`visibility` **explicitly** from this table rather
than through `Media::PhotoPolicy.initial_state` (which would force every photo to
`pending_review`).

---

## 13. `owner_not_imported` behaviour (3 photos in rehearsal)

- **Do not** create a `ProfilePhoto` — there is no Date9ja `Profile` destination
  to own it. No orphan photos.
- The `MediaObjectRef` / `MediaAttachmentRef` preflight evidence stays intact.
- The blob is **not** transferred (no point moving bytes for a photo that cannot
  land). `transfer_state` stays `not_started`.
- Terminal disposition `owner_not_imported`.
- **Revisitable:** if the identity importer later imports that owner (e.g. a
  deleted/banned-account policy change), a subsequent Pass-2 run will find the
  `profile` binding and transfer normally — no special path, the disposition
  simply changes. Nothing is discarded.

---

## 14. Suspended-owner behaviour (3 owners in rehearsal)

- Suspension is **not** a reason to discard media. The identity importer already
  created these profiles with `status: :suspended` and a suspended
  `BrandMembership`.
- Pass 2 transfers their photos and creates `ProfilePhoto` rows **normally**,
  with the moderation-derived `status`/`visibility` from §12.
- Delivery stays correct because a suspended `Profile` / `BrandMembership` is
  already excluded from every public serializer and discovery path upstream of
  the photo — the photo does not need its own suppression, and adding one would
  diverge from how a natively-suspended D8N profile behaves.
- Measured (`owners_suspended`), not branched. Not assumed equal to
  `owner_not_imported`.

**Open — product confirmation:** is "migrate suspended users' media, rely on
profile-level suppression" the intended stance? (Consistent with the identity
importer's decision to migrate suspended users structurally.)

---

## 15. Pass-2 transfer reconciliation contract (PII-free)

Terminal dispositions (mutually exclusive; every source `Photo` gets exactly one):

| Disposition | Meaning |
|---|---|
| `transferred` | bytes verified + uploaded + `ProfilePhoto` created + bound + processing enqueued, this run |
| `already_transferred` | rerun; full destination chain validated, nothing written |
| `owner_not_imported` | no Date9ja `Profile` destination; evidence kept, bytes not moved |
| `source_unavailable` | source object missing / unreadable / off-allowlist |
| `source_changed` | source size or MD5 ≠ `MediaObjectRef` (fail closed) |
| `validation_failed` | not an image / unsupported type / malformed / oversize |
| `destination_failed` | D8N storage upload or `ProfilePhoto` create failed (transient — retryable) |
| `binding_conflict` | `ReferenceMap` / `ProfilePhoto` / plan mismatch — fail closed |
| `processing_failed` | photo created + bound, but the safe-derivative job ended `failed` |
| `quarantined` | multiple-primary owner, or another explicitly-flagged anomaly requiring product review |
| `explicitly_skipped` | reserved; a documented policy exclusion only |

**Invariant:** `photos_considered == Σ (exactly one terminal disposition)`.

Aggregate measures (counts only — no PII, no locator, no per-row id):
`total_source_photos`, `bytes_expected`, `bytes_transferred`,
`source_objects_fetched`, `destination_uploads_created`,
`destination_uploads_reused`, `profile_photos_created`, `profile_photos_reused`,
`reference_map_bindings_created`, `processing_enqueued`,
`processing_succeeded`, `processing_failed`, `moderation_pending|approved|rejected`,
`owners_ordered`, `owners_one_primary`, `owners_zero_primary`,
`owners_multiple_primary_quarantined`, `orphan_transfers_detected`,
`missing_destination_objects`, `owner_not_imported`, `source_checksum_mismatches`,
`source_size_mismatches`, `binding_conflicts`.

Rehearsal acceptance baseline (from Pass 1): 279 considered, 276 transfer-eligible,
3 `owner_not_imported`, 0 `owners_multiple_primary_quarantined` expected,
`profile_photos_created` 276 on a clean first run, 0 on rerun.

---

## 16. Processing strategy

Options: (A) synchronous during migration, (B) enqueue existing jobs, (C) create
then drain a bounded migration processing queue, (D) other.

**Recommendation: C — enqueue the existing `Media::ProcessProfilePhotoJob`, then
block the migration run on a bounded drain loop** that polls until every enqueued
photo reaches `processing_state ∈ {ready, failed}` (with a timeout that turns
into a `processing_failed` disposition, not a hang).

Rationale: reuses the identical, already-tested derivative pipeline (B's win)
while giving the migration deterministic completion evidence (A's win) —
essential for "no cutover with photos stuck unprocessed". Failure is isolated
per photo (`processing_failed` disposition, re-enqueueable), throughput is
whatever the worker fleet does, and a photo is never delivered before its
derivative exists because `deliverable?` already fails closed on
`processing_state != ready`. Synchronous in-process (A) would couple migration
throughput to libvips and lose retry isolation; a bespoke queue (C-as-new) is
overbuild.

**Open — operator decision:** acceptable drain timeout + whether the cutover
gate requires `processing_failed == 0` or tolerates a small manually-reviewed
tail.

---

## 17. Failure / quarantine model

**Global blockers (abort the whole run, transfer nothing):**
- Date9ja snapshot schema-signature (v2) failure.
- Source storage config unsafe/absent, or endpoint host not on the allowlist.
- Destination `Media::StorageResolver` cannot resolve a private D8N service for
  the brand.
- Any blob on an **unexpected `service_name`** (until classified).
- A systemic checksum-algorithm mismatch (e.g. a sample of known objects all
  fail MD5) — indicates a semantic misunderstanding, not per-object corruption.
- Wrong/inactive brand.

**Per-photo quarantine (`quarantined` / the specific failure disposition),
run continues:**
- source object genuinely missing (`source_unavailable`)
- malformed / non-image / oversize / unsupported (`validation_failed`)
- source bytes changed since preflight (`source_changed`)
- multiple source primaries for one owner (`quarantined`)
- `ReferenceMap` / destination mismatch (`binding_conflict`)

**Product-impact decisions flagged, NOT decided here:**
- If a `quarantined` photo is an owner's **only** photo, or is the intended
  **primary**, may the profile still publish with a different / no photo? This
  affects onboarding/publication state and is a product call — see §21.
- Whether a run with any `quarantined` / `processing_failed` may proceed to
  cutover, or must reach zero first.

---

## 18. Production cutover / media-delta strategy

Date9ja is **live**; media cannot be frozen instantly. Recommended model:
**hybrid — bulk pre-copy + delta at cutover.**

1. **Bulk pre-copy (days before cutover):** run Pass 2 against a recent
   production restore into the throwaway D8N DB's storage (or option C's export).
   This transfers ~all 279 (real number at cutover) blobs and creates
   `ProfilePhoto`s. Idempotent, so it can be re-run as the date approaches.
2. **Freeze window (short):** at cutover, restore the final production snapshot.
   Re-run identity Pass + photo Pass 1 + photo Pass 2. Because every step is
   idempotent on canonical source ids and deterministic destination keys, only
   the **delta** (photos added/removed/re-moderated since the bulk copy) does
   real work: new photos → `transferred`; unchanged → `already_transferred`;
   a source photo deleted since bulk copy → its binding + `ProfilePhoto` are
   **flagged for review** (`binding_conflict` / a `source_removed` measure), not
   auto-deleted.
3. **Final delta reconciliation:** the Pass-2 reconciliation invariant + a diff
   of `ReferenceMap(photo)` bindings vs. the final source `photos` set must be
   clean (or have an approved exception list) before cutover completes.

This minimises the freeze window to "restore + idempotent re-run of the delta"
while guaranteeing the final state reflects the final source. Copying **only**
during cutover (no pre-copy) risks a long freeze if the corpus grows; pre-copy
**only** (no delta) risks missing last-minute changes. Hybrid is the safe
practical middle.

**Open — operator decision:** bulk-copy destination (throwaway rehearsal storage
vs. a real pre-provisioned D8N private prefix that becomes production), and the
acceptable freeze-window length.

---

## 19. Security review

| Concern | Design |
|---|---|
| SSRF / arbitrary endpoint | `Date9ja::Storage::SourceReader` accepts **only** an S3-style `{endpoint, bucket, key}` from config; the endpoint host must match an **allowlist** (`*.r2.cloudflarestorage.com`, plus an explicit rehearsal host). No URL is ever taken from a DB row or a redirect. Provider redirects to a non-allowlisted host → refuse + `source_unavailable` + security event. |
| Source endpoint allowlist | Hard-coded allowlist constant; config supplies the account/bucket, not the host pattern. |
| Credential scoping | Source token is **read-only**, bucket-scoped, run-environment-only (§5). Destination creds untouched and separate. |
| Private storage both ends | Source is private R2; destination via `Media::StorageResolver.service_name` (private D8N R2). No public URL is ever generated in Pass 2. |
| Key / path traversal | Legacy keys are flat random tokens; the reader treats the key as an opaque S3 object key, never a filesystem path. Destination keys are `Media::ObjectKey`-allocated (brand/user/profile/UUID), never derived from a source-controlled string. |
| Object-size limits | 8 MB hard ceiling enforced **while streaming** (abort mid-download), before decode. |
| Decompression / image bombs | `Media::ImageProcessor` header probe (`MAX_SOURCE_DIMENSION` 12 000, `MAX_SOURCE_PIXELS` 40 MP) before any full decode; the actual re-encode happens in the existing `ProcessProfilePhotoJob` which already has these guards. |
| Malformed image parsing | libvips selects the loader from bytes, not extension; a non-image or truncated file → terminal `validation_failed`, never retried. |
| Log redaction | No storage key, credential, checksum value, email, name, or per-row id is logged. Transfer logs carry `source_blob_id` + disposition + a safe failure code only. `MediaObjectRef#inspect` / reconciliation exclude the encrypted `destination_blob_key`. |
| Checksum exposure | Checksums live only in `MediaObjectRef` (not serialized anywhere) and are compared in memory; never printed. |
| Temp-file permissions / cleanup | `Dir.mktmpdir` under a migration-only root, files `0600`, `unlink` in `ensure` on every path including exceptions. |
| Crash recovery | Deterministic keys + staged `transfer_state` (§8); a crashed run leaves only re-attemptable state, never a duplicate or a silent gap. |
| Local filesystem safety (rehearsal) | The synthetic-media source (§ below) lives under an explicit rehearsal root; the reader refuses absolute/`..` keys. |
| Destination object ownership | Every destination blob is created by D8N with a D8N-allocated key on a D8N service; `ProfilePhoto.profile_matches_scope` enforces user+brand. |
| Cross-brand isolation | `source_system = "date9ja"` on every `MediaObjectRef` / `ReferenceMap` row; `ReferenceMap.bind!` enforces `destination.brand_id == date9ja.brand.id`. |
| Source immutability | The reader issues **only** `HEAD` / `GET`. No `PUT`/`DELETE`/`COPY` code path exists in `SourceReader`. |

---

## Sanitized / synthetic media rehearsal design (§5 of the brief)

The sanitized snapshot keeps blob **rows** (key, size, checksum, type — the
checksum/size are the sanitizer's synthetic-but-consistent values) but has **no
object bytes**, and must never gain production bytes.

**Design: a synthetic object store keyed by `source_blob_id`.**

1. A generator (`script`/rake, operator-run) reads the sanitized
   `active_storage_blobs` rows for the 279 photo blobs and, for each, produces a
   **synthetic image file** whose bytes hash to the recorded `checksum` and whose
   length equals the recorded `byte_size` and whose magic bytes match the
   recorded `content_type`.
   - Since the sanitizer controls both, the cleanest approach is to **regenerate
     the sanitizer's synthetic blobs deterministically from `source_blob_id`**
     (a fixed procedural JPEG/PNG/WebP of the right size) and have the sanitizer
     record *that* file's real MD5/size/type. i.e. the synthetic corpus and the
     sanitized DB are generated together from the same seed. (Requires a small
     addition to the sanitizer or a companion generator — operator-run, no
     production data.)
2. The corpus is written to a **local S3-compatible test source** (MinIO or the
   Active Storage `Disk` service) OR a plain directory, under a rehearsal root.
   `source_blob_id → synthetic object` mapping is 1:1 by key.
3. `Date9ja::Storage::SourceReader` is pointed at that endpoint via the same
   `DATE9JA_SOURCE_*` env — **identical transfer code path**, only the config
   differs. The verification algorithm (§6) runs unchanged and passes because the
   synthetic file genuinely has the recorded size/MD5/signature and decodes.

**Staged rehearsal levels:**

| Level | Corpus | Proves |
|---|---|---|
| L1 — unit/synthetic | a handful of generated images + injected failures (missing object, truncated, wrong checksum, non-image, oversize, multi-primary) | verification order, every disposition, idempotency, recovery, PII-free reconciliation |
| L2 — full sanitized rehearsal | all 279 synthetic objects, local source | end-to-end scale, ordering across all 166 owners, reconciliation invariant, rerun = zero duplicates, processing drain |
| L3 — controlled real rehearsal (pre-cutover) | real production restore + real read-only source R2 (option A) or an exported bundle (option C), into throwaway D8N storage | the real bytes transfer, real checksums match, real images decode; the only run that touches real media, operator-only, evidence in RECONCILIATION.md |

**All 279 must be represented at L2 and L3** — "prefer proof over convenience"
for the pre-cutover run. A representative subset is acceptable only for L1.

---

## Resolved vs. open

### Resolved (architecture — ADR 0027 + this design)
- Three-identity separation; `ReferenceMap` is the sole source→dest binding.
- `MediaObjectRef` / `MediaAttachmentRef` carry no destination ids.
- `ProfilePhoto` validations and the shared media pipeline are **not** weakened;
  Pass 2 reuses the normal attach + `ProcessProfilePhotoJob` path via a new thin
  `Media::PhotoImport` shared service.
- Deterministic destination keys (UUIDv5 of `source_blob_id`) + staged
  `transfer_state` + idempotent upsert + orphan detector = the recovery
  mechanism. No transaction framework.
- Byte verification order (§6); MD5-base64 checksum semantics confirmed identical
  legacy↔D8N.
- Moderation/visibility mapping is representable with **no** shared-model change.
- Ordering algorithm (§11); multiple-primary → quarantine.
- `owner_not_imported` → no `ProfilePhoto`, evidence kept, revisitable.
- Suspended owners → migrate structurally, rely on profile-level suppression.
- Processing: enqueue existing job + bounded drain (§16).
- Cutover: hybrid bulk pre-copy + idempotent delta (§18).
- Synthetic-media rehearsal via `source_blob_id`-keyed generated corpus (§ above).

### Open — require Uchechi / operator / security sign-off before implementation
1. **Source access model:** option **A** (scoped read-only legacy R2 token) vs
   **C** (pre-exported controlled bundle); who mints/holds the token. (§5)
2. **`service_name` census:** run the read-only Pass-2 preflight extension and
   confirm all 279 photo blobs are on the single expected legacy service. (§2 gap)
3. **Publication when a photo is quarantined:** if an owner's only/primary photo
   fails, may the profile still publish? Product-impact. (§17)
4. **Cutover gate strictness:** must `quarantined` + `processing_failed` be zero
   before cutover, or is a small manually-reviewed tail acceptable? (§16, §17)
5. **Bulk-copy destination + freeze-window length.** (§18)
6. **Suspended-owner media stance** — confirm §14 is the intended policy.
7. **`source_removed` at delta** (a photo deleted in production between bulk
   copy and cutover): auto-flag for review is proposed; confirm no auto-delete
   of the D8N `ProfilePhoto`. (§18)

---

## Implementation readiness

**Pass 2 is BLOCKED — pending the 7 open decisions above**, principally #1
(source access), #2 (`service_name` census — cheap, do first), and #3 (product:
publication vs. quarantined photo). The architecture, class boundaries,
verification, recovery, idempotency, reconciliation, and rehearsal design are
**READY** and unambiguous; nothing else needs design work. Once #1–#3 are
answered the remaining items (#4–#7) can be resolved during the controlled
rehearsal without blocking the build.
