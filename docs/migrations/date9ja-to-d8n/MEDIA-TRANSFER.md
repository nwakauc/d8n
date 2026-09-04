# Date9ja → D8N media transfer (profile-photo Pass 2) — execution design

**Status: DESIGN CHECKPOINT — REVISION 4 (2026-09-03), canonical-identity
correction applied. Not implemented.**
Architecture authority:
[ADR 0027](../../adr/0027-migration-media-preflight-architecture.md) (preflight,
**Accepted**) + [ADR 0028](../../adr/0028-migration-media-byte-transfer.md) (byte
transfer + recovery, **ACCEPTED**). Linked from `STATUS.md`. This file is
detailed execution design; it does not create new phase/decision authority.

> **Profile video (Wave A slice 5, 2026-09-03):**
> [ADR 0029](../../adr/0029-migration-media-transfer-generalized-across-media-kinds.md)
> **ACCEPTED** — the transfer architecture below is generalized across media
> kinds via a small injected `Migration::MediaTransfer::MediaKind` strategy
> (`MediaKind::Image` reproduces the behaviour in this document byte-for-byte;
> `MediaKind::Video` parameterizes only content types / extension / byte ceiling
> / magic-byte detector / container validation / remote re-verification body).
> Locking, canonical identity structure, `AdoptOrUpload`, deterministic recovery
> and `ReferenceMap` semantics are unchanged. For video, **Phase A derives
> authoritative playable duration (ffprobe via `Media::VideoProcessor.probe`,
> after `Media::VideoContainerValidator`) and enforces the brand limit BEFORE
> destination adoption** — unreadable or over-limit fails closed
> (`quarantined` / `duration_unreadable` | `duration_over_limit`) with no
> destination blob, `ProfileVideo`, binding or job. Video execution design
> (Pass 2A / 2B / 2C, synthetic-corpus L2) is tracked in `STATUS.md`
> "Profile-video pass 2 — architecture closeout"; not implemented.

Revision 4 closed the Codex FINAL narrow review's three blockers. The FINAL
acceptance check then found one documentation defect — `canonical_content_type`
influenced the final key (`original.<ext>`) without being in the declared
canonical identity — now fixed (§7): `canonical_content_type` is a declared
identity field and appears in the canonical string before the UUIDv5, so the
final key is a **total** function of the declared identity. No other architecture
changed. Everything in ADR 0028 §"Closed / accepted" — including the shared-seam
choice (`Profiles::PhotoUpload.build_photo!` extraction) — is unchanged.

### Revision 4 changes (three blockers)

1. **Destination key stability** (§7). Revision 3 fed `Brand#slug` and
   `Profile#public_id` into the key; the current D8N models do **not** guarantee
   those immutable. The migrated-object key is now a pure function of **immutable
   migration/storage identity only** — no `destination_user_id`, no
   `destination_profile_public_id`, no mutable `Brand#slug`, no destination
   `Profile` mapping input. A **dedicated migration-original key helper**
   (`Migration::MediaTransfer::CanonicalKey.final_key`) produces
   `migrations/media/v3/date9ja/profile_photo_original/<uuidv5>/original.<ext>` —
   it does **not** route through `Media::ObjectKey.profile_photo_original`. The
   declared identity is `version` + `source_system` + `source_blob_id` +
   `source_attachment_id` + `destination_purpose` + `destination_brand` +
   **`canonical_content_type`** (the seventh field — it drives `<ext>`, so it is
   declared and hashed into `object_uuid`, making the key a **total** function of
   the declared identity). Destination `Profile`/`User` remapping after pre-copy
   → `mapping_drift` / `binding_conflict`, reconciled explicitly; **no new key is
   derived**. Verified source content-type drift → `source_changed`.
2. **Short attachment lock** (§7c, §8). No R2 streaming, remote hashing, upload,
   or libvips work is done while holding the `MediaAttachmentRef` `FOR UPDATE`
   lock. Explicit **Phase A (prepare/verify, no lock)** → **Phase B (short
   finalization transaction: lock, re-check, create/reuse Blob, `build_photo!`,
   bind)** → **Phase C (after commit: enqueue)**. The tiny Active-Storage
   blob-row coordination transaction (row saved before object upload) is
   distinguished from the `MediaAttachmentRef` finalization lock.
3. **Abandoned processing claim** (§16b). `ProfilePhoto` gains nullable
   `processing_started_at` **and** `processing_claim_token` (shared D8N
   processing-lifecycle hardening — **not** a migration transfer table). Claim /
   stale-reclaim / finalize / failure all gate on
   `processing_state == processing AND processing_claim_token == worker_token`,
   which defeats the ABA race a bare timestamp cannot. Sweeper reclaims stale
   `processing`.

`RECONCILIATION.md` / `SNAPSHOT-RUNBOOK.md` contracts are unchanged by Revision 4
(the disposition vocabulary gains `mapping_drift` as a sub-reason of
`binding_conflict`, already noted).

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
| `blob.key` → object | Active Storage default: `key` is a random ~28-char token, stored **flat at the bucket root**. The object is `GET <bucket>/<key>`. No path structure, so no traversal surface from the key itself. |
| Credentials source | `ENV` only (Kamal secrets). **Not** Rails encrypted credentials. The current keys are full read/write on the bucket. |
| Object privacy | Private. The app serves photos through `rails_blob_path` redirects/proxy. |
| Variants / previews | `Photo` declares only `has_one_attached :image` — **no declared variants**. Derived thumbnails are regenerated D8N-side, **not migrated**. |
| Original bytes retrievable | Yes — `GET` the object by key returns the exact uploaded bytes. |
| Structurally-valid graph, missing object | **Possible.** The R2 object for a blob key can be absent (failed upload that still wrote the blob row, lifecycle deletion, manual ops). Pass 2 `HEAD`/`GET` is the authority; a missing object is a per-photo `source_unavailable`. |
| Checksum semantics | Rails `ActiveStorage::Blob#compute_checksum_in_chunks` → `OpenSSL::Digest::MD5` streamed → `.base64digest` (24-char base64, `Content-MD5` style). **Legacy Date9ja and D8N run the same Rails 8.1**, so `MediaObjectRef.checksum` is directly comparable to a freshly computed MD5-base64 of the transferred bytes. MD5 is a transit-integrity check, not a security control — structural decode validation is the real gate (§6). |

### `service_name` census — RUN, blocker CLOSED (2026-09-03)

Metadata-only census (no bytes, no `key`) against `date9ja_snapshot_sanitized`
(`postgresql://127.0.0.1:55432`):

| `service_name` | photo blob count |
|---|---:|
| `cloudflare` | 279 |

All 279 Date9ja photo blobs use the expected `cloudflare` Active Storage service.
**No `local` rows, no `amazon` rows, no `NULL` rows, no mixed-service corpus.**
The `service_name` evidence blocker is closed for this slice. Pass 2 still asserts
this invariant at run time against the final production snapshot and treats any
non-`cloudflare` value as a **global blocker** (§17). Recorded in `STATUS.md`,
`RECONCILIATION.md`, `SNAPSHOT-RUNBOOK.md`, `DECISIONS.md`.

---

## 3. Pass 2 architecture

```
Migration::MediaObjectRef (preflighted, per source blob)  ── source evidence ONLY
Migration::MediaAttachmentRef (per source attachment/use) ── source evidence ONLY
                                                             + per-attachment SERIALIZATION lock (§7c)
  │
  └─ Date9ja::Snapshot::MediaLocatorSource        # date9ja: source_blob_id -> {key, service_name}
  │     schema-guarded, column-allowlisted; locator read ONLY here, ONLY at
  │     transfer time, never persisted, never logged.
  │
  └─ Date9ja::Storage::SourceReader              # date9ja: HEAD/GET the source object
  │     S3-compatible, host-allowlisted, read-only, run-env creds, fail-closed (§5, §5b).
  │
  └─ Migration::MediaTransfer.call(...)          # SHARED, source-system-agnostic
  │     1. resolve locator (via injected locator + reader)
  │     2. stream source bytes -> 0600 temp file, size-capped mid-stream
  │     3. verify: size, MD5-base64, magic bytes, libvips decode probe   (§6)
  │     4. derive the FINAL destination key from the complete canonical
  │        identity via Migration::MediaTransfer::CanonicalKey.final_key   (§7)
  │     5. adopt-or-upload the destination ActiveStorage::Blob            (§7b)
  │        — every reuse path re-verifies the ACTUAL remote object bytes
  │     -> returns a persisted, object-backed ActiveStorage::Blob
  │
  └─ Date9ja::Import::PhotoTransfer              # date9ja orchestrator
  │     per owner, source Photo rows in planned order (§11):
  │     a. resolve owner Profile via Migration::ReferenceMap -> owner_not_imported if absent
  │     b. DB transaction:
  │          lock Migration::MediaAttachmentRef row (SELECT ... FOR UPDATE)   (§7c)
  │          re-read attachment ref / ReferenceMap / expected blob state / ProfilePhoto candidate
  │          blob = Migration::MediaTransfer.call(...)   (idempotent on the final key)
  │          Profiles::PhotoUpload.build_photo!(...)     (image.attach + save!, all on: :create validations)
  │          Migration::ReferenceMap.bind!(date9ja/photo/<Photo.id> -> ProfilePhoto)
  │     c. AFTER COMMIT: Media::ProcessProfilePhotoJob.perform_later(photo.id)   (§16)
  │     d. bounded drain: wait until processing_state ∈ {ready, failed}
  │
  └─ Date9ja::Import::PhotoOrderPlan             # date9ja: pure ordering function (§11)
  └─ Date9ja::Import::PhotoTransferReconciliation # date9ja: PII-free tally (§15)
```

Byte streaming, verification, final-key derivation, and Active Storage
adopt-or-upload are **shared** `Migration::` primitives. Everything that knows a
legacy table/column or the Date9ja brand stays in `Date9ja::`.

---

## 4. Class / module ownership

| Unit | Layer | Responsibility |
|---|---|---|
| `Migration::MediaTransfer` | shared migration | Given a `Migration::MediaObjectRef`, injected `source_reader` + `locator`, and a **complete key context** (§7): verify → adopt-or-upload (with real remote-byte verification on every reuse) → return a persisted object-backed `ActiveStorage::Blob`. No brand logic, no legacy-schema logic, no `ProfilePhoto` knowledge. |
| `Migration::MediaTransfer::CanonicalKey` | shared migration | Pure functions over the full 7-field `identity` (incl. `canonical_content_type`): `canonical_string(identity)` → the exact tuple string (§7); `object_uuid(identity)` → `Digest::UUID.uuid_v5(KEY_NAMESPACE, canonical_string)`; `final_key(identity)` → the full R2 object key (extension from `identity[:canonical_content_type]`). **The only place a migration destination key is produced.** |
| `Migration::MediaObjectRef` (exists, unchanged) | shared migration | Source blob identity + integrity metadata + preflight state. **No destination columns.** `transfer_state` is a **coarse denormalized hint only**, always re-derived and cross-checked; it must **never** override observed destination reality (§8). |
| `Migration::MediaAttachmentRef` (exists, unchanged) | shared migration | Source attachment/use identity. Its row is the **per-attachment serialization lock** for Pass 2 orchestration (§7c). Per-use discriminator for the destination object (§20). |
| `Date9ja::Storage::SourceReader` | date9ja adapter | `HEAD` + streamed `GET` against a configured S3-compatible endpoint (§5, §5b). Host-allowlisted, read-only, fail-closed. No `PUT`/`DELETE`/`COPY`/multipart-write method exists on the class. |
| `Date9ja::Snapshot::MediaLocatorSource` | date9ja adapter | `source_blob_id → { key, service_name }` from the restored snapshot's `active_storage_*` rows. Never persists the locator. |
| `Date9ja::Import::PhotoTransfer` | date9ja adapter | Pass-2 orchestrator: owner resolution, ordering, moderation mapping, per-attachment lock + transaction boundary, `ReferenceMap` binding, post-commit enqueue, drain, reconciliation. |
| `Date9ja::Import::PhotoOrderPlan` | date9ja adapter | Pure: `[owner's source Photo rows] → [{photo, destination_position}]` (§11). |
| `Date9ja::Import::PhotoTransferReconciliation` | date9ja adapter | PII-free tally (§15). |
| `Profiles::PhotoUpload.build_photo!` | **shared media (minimal internal extraction)** | The ProfilePhoto-build block factored out of `attach!`: `(profile:, user:, brand:, blob:, position:, status:, visibility:)` → build `ProfilePhoto`, `image.attach`, `save!` under the profile lock, capacity check, return it. **Internal domain helper — it owns `ProfilePhoto` domain invariants, not request authorization** (§23). |

**No new persistence model.** No new table, no new columns on any migration
model (§8, §13).

---

## 5. Source credential / access model — RESOLVED

**Confirmed (2026-09-03):** a dedicated **read-only, bucket-scoped Cloudflare R2
credential** is used for the controlled real-media rehearsal (L3) and cutover.
The pre-exported controlled media bundle remains the **fallback**.

- Present **only** in the migration run's environment —
  `DATE9JA_SOURCE_R2_ACCESS_KEY_ID` / `_SECRET_ACCESS_KEY` / `_BUCKET` /
  `_ACCOUNT_ID`. Never `config/`, `config/deploy.yml`, Rails encrypted
  credentials, a migration table, or logs.
- Source and destination (D8N R2) credentials are **fully separate** objects; the
  reader never sees destination creds, `MediaTransfer`'s upload path never sees
  source creds.
- The reader exposes **only** `HEAD` + streamed `GET`. No `PUT`/`DELETE`/`COPY`/
  multipart-write method exists on the class.
- Endpoint constructed as
  `https://<DATE9JA_SOURCE_R2_ACCOUNT_ID>.r2.cloudflarestorage.com`; **HTTPS
  only**; host must match the hard-coded allowlist
  (`*.r2.cloudflarestorage.com` + one explicit rehearsal host).
- Fail closed: config absent, host off-allowlist, or non-HTTPS → the reader
  raises at construction; the run aborts (global blocker) before any transfer.

**Remaining operator logistics (not a design blocker):** who mints and holds the
scoped token, and its rotation/retirement after cutover.

### 5b. `Date9ja::Storage::SourceReader` implementation security contract

Codex accepted the direction and asked for these to be written down as
**implementation requirements** (not reasons to redesign the adapter). The reader
MUST:

- **construct the exact expected Cloudflare R2 endpoint from trusted operator
  configuration only** (`_ACCOUNT_ID` → `https://<id>.r2.cloudflarestorage.com`);
- **reject any caller-provided endpoint / URL / host** — no endpoint string ever
  comes from a DB row, a snapshot row, an argument, or a redirect;
- **HTTPS only** — a non-`https` scheme raises at construction;
- **refuse redirects** — any `3xx` response → `source_unavailable` + security
  event; the `Location` header is never followed;
- **bucket-scoped, read-only credentials** — verified by contract, not by trust;
- **expose no write/delete/copy** — those methods do not exist on the class;
- **stream with a hard byte ceiling** — abort mid-download the moment the running
  count exceeds 8 MB (§6 step 3);
- **use a bounded `0600` temp file** under a migration-only root;
- **`unlink` the temp file in an `ensure`** on every path, including exceptions;
- **enforce image dimension / pixel ceilings before normal processing**
  (`Media::ImageProcessor` header probe — 12 000 px/edge, 40 MP);
- **bounded retry count + backoff** — a fixed small number of transient retries,
  then terminal;
- **redact provider exceptions** — never surface raw `aws-sdk` messages that may
  carry a bucket, key, or signed URL;
- **never log** credentials, bucket locators, object keys, signed URLs, or source
  checksums — transfer logs carry `source_blob_id` + disposition + a safe failure
  code only.

---

## 6. Byte-verification algorithm (exact order, streamed, bounded memory)

Per source blob, `Migration::MediaTransfer`:

1. **Expected values** from `MediaObjectRef`: `source_blob_id`, `byte_size`,
   `checksum` (MD5-base64), `content_type` (declared). A Pass-1 failure row
   (`byte_size` nil, `failure_code` present) is never transferred.
2. **`HEAD`/metadata** the source object. Missing → `source_unavailable`.
   Provider error / redirect / off-allowlist host → `source_unavailable` +
   security event (§19).
3. **Stream** the object to a private temp file (mode `0600`, migration-only
   root), in ≤ 5 MB chunks, **aborting the moment the running byte count exceeds
   8 MB** (Date9ja `Photo::MAX_FILE_SIZE` 8 MB vs D8N `ProfilePhoto::MAX_FILE_SIZE`
   10 MB — use the **lower**, 8 MB). Oversize → `validation_failed` (`oversize`).
4. **Actual byte count == `MediaObjectRef.byte_size`** — mismatch →
   `source_changed` (fail closed).
5. **MD5-base64 of the streamed bytes == `MediaObjectRef.checksum`** — mismatch →
   `source_changed`.
6. **Magic-byte signature** (`Profiles::PhotoUpload.detect_image_type` — the
   existing authority: `FF D8 FF` / `89 PNG…` / `RIFF…WEBP`). `nil` →
   `validation_failed` (`not_an_image`). The declared `content_type` is **never
   trusted**; the detected type wins and becomes the **canonical content type**
   for the key (§7) and the upload.
7. **Detected type ∈ {image/jpeg, image/png, image/webp}** — else
   `validation_failed` (`unsupported_content_type`).
8. **Decode-safety probe** — `Media::ImageProcessor` header read only
   (`MAX_SOURCE_DIMENSION` 12 000 px/edge, `MAX_SOURCE_PIXELS` 40 MP). Fails →
   `validation_failed` (`malformed_image`). **This is the real safety gate.**
9. **The verified bytes + `{md5, byte_size, canonical_content_type}` are now the
   expected identity `E`** for the adopt-or-upload step (§7b). `E` is what every
   reuse path is checked against — **including a real streamed re-read + re-hash
   of the actual remote destination object** (§7b cases 2 and 3). Active Storage
   metadata is never trusted on its own.

All checks stream; peak memory is one 5 MB chunk + libvips header state. The temp
file is `unlink`ed in an `ensure` on every path.

---

## 7. Migration storage-object key — pure function of immutable migration/storage identity (BLOCKER 1)

**Problem in Revision 3:** the key fed `Brand#slug` and `Profile#public_id` (via
`Media::ObjectKey.profile_photo_original`) into the path. The current D8N models
do **not** guarantee those immutable — a brand rename or a profile
re-provisioning would silently change where the migrated bytes are expected to
live. We do **not** fix this by imposing broad immutability constraints across
D8N, and we do **not** persist a destination key on `MediaObjectRef`. Instead the
**migration storage-object identity is simplified** to depend only on immutable
migration/storage facts.

**This is a migration storage key, not the normal HTTP-upload key.** The migrated
original object is therefore **not** routed through
`Media::ObjectKey.profile_photo_original` (that helper necessarily adds
user/profile/slug segments). A dedicated helper produces it. The resulting
`ActiveStorage::Blob` is still attached through the normal `ProfilePhoto` domain
seam (`Profiles::PhotoUpload.build_photo!`), and its D8N-side display derivative
still lands beside it (`Media::ObjectKey.derived_key` — see below).

### Complete canonical identity

```
identity = {
  version:                "migration-media-transfer:v3",
  source_system:          "date9ja",
  source_blob_id:         <legacy active_storage_blobs.id, as text>,        # traceability
  source_attachment_id:   <legacy active_storage_attachments.id, as text>,  # the migrated storage USE
  destination_purpose:    "profile_photo_original",
  destination_brand:      "date9ja",   # STABLE migration brand identity token (from the checked-in
                                       # Migration brand map) — NOT Brand#slug, NOT Brand#id lookups
  canonical_content_type: <verified canonical detected media type from §6 step 6>   # e.g. "image/jpeg"
}
```

**Not in the identity:** `destination_user_id`, `destination_profile_public_id`,
`Brand#slug`, any destination `Profile` mapping input. Those belong to a
**different identity layer** (ADR 0027): `Migration::ReferenceMap` separately
binds source `Photo → destination ProfilePhoto`. The storage object is tied to
the immutable **source attachment** identity; the domain row mapping is tied to
`ReferenceMap`.

`canonical_content_type` **is** an identity input — it is the verified detected
media type from §6 step 6 (a property of the immutable source bytes, never the
declared/destination type), and the trailing `original.<ext>` is derived from
this same value. Including it makes the final key a **total** function of the
declared canonical identity. A verified source content-type change between runs
is `source_changed` (see "Source content-type drift" below), never a silent
re-key.

### Exact canonical string

```
canonical =
  identity[:version] +
  "|source_system="          + identity[:source_system] +
  "|source_blob_id="         + identity[:source_blob_id] +
  "|source_attachment_id="   + identity[:source_attachment_id] +
  "|destination_purpose="    + identity[:destination_purpose] +
  "|destination_brand="      + identity[:destination_brand] +
  "|canonical_content_type=" + identity[:canonical_content_type]

# e.g.
# migration-media-transfer:v3|source_system=date9ja|source_blob_id=<id>|source_attachment_id=<id>
#   |destination_purpose=profile_photo_original|destination_brand=date9ja|canonical_content_type=image/jpeg
```

### Exact final key

```
object_uuid = Digest::UUID.uuid_v5(
  Migration::MediaTransfer::KEY_NAMESPACE,   # one fixed UUID constant, checked into shared migration code
  canonical
)

final_key =
  "migrations/media/v3/"           +
  identity[:destination_brand]     + "/" +   # "date9ja" — stable token, not a slug
  identity[:destination_purpose]   + "/" +   # "profile_photo_original"
  object_uuid                      + "/" +
  "original." + Media::ObjectKey.extension_for(identity[:canonical_content_type])

# => "migrations/media/v3/date9ja/profile_photo_original/<uuidv5>/original.<ext>"
```

Both the hashed segment (`object_uuid`) and the extension segment (`<ext>`)
derive from the **same** `canonical_content_type` already declared in
`canonical`. `Migration::MediaTransfer::CanonicalKey.final_key(identity)` is the
**only** code path that produces this key. Its `canonical_string` / `object_uuid`
sub-functions are pure. The final key is now a **total deterministic function of
the complete declared identity** — no undeclared input.

Properties:

- **total function of the complete declared canonical identity** — the seven
  identity fields (version, source_system, source_blob_id, source_attachment_id,
  destination_purpose, destination_brand, canonical_content_type) plus a fixed
  namespace; **no undeclared input** (the extension derives from
  `canonical_content_type`, which is in `canonical`);
- **no PII**, **no user id**, **no profile public id**, **no mutable slug
  dependency**, **no destination `Profile` mapping input**;
- **deterministic forever** for that migration identity — a rerun, a re-import of
  the owner, or a brand rename does not move it;
- **globally namespaced by source system** (`source_system` in `canonical`),
  **purpose-scoped**, **brand-scoped**, **attachment/use-scoped**;
- **compatible with private D8N Active Storage** — a flat opaque key on the
  private D8N service; `Media::StorageResolver.service_name(brand:)` still selects
  the service.

### Source content-type drift

`canonical_content_type` is the **verified** detected type (§6 step 6). If it
differs from what Pass 1 recorded / a prior run verified — i.e. the source bytes
themselves changed type — the run classifies **`source_changed`** (fail closed).
The importer does **not** derive or use a replacement key (with the new type in
`canonical`) as though it were the same source state; reconciliation surfaces the
drift as `source_size_mismatches` / `source_checksum_mismatches` /
`source_changed` for operator classification. A new `canonical_content_type`
would legitimately produce a new `final_key` only for a genuinely new
`source_blob_id` (interleaving N), which is a separate transfer.

### D8N-side display derivative

`Media::ProcessProfilePhotoJob` derives the safe display image with
`Media::ObjectKey.profile_photo_display(original_key)` →
`Media::ObjectKey.derived_key(final_key, "display.jpg")`. `derived_key` sees the
`original.` basename and swaps it, yielding
`migrations/media/v3/date9ja/profile_photo_original/<uuidv5>/display.jpg` on the
same private service. No native-upload key shape is required for this to work.

### Mapping drift (destination `Profile`/`User` remapping after pre-copy)

If the owner's `ReferenceMap(profile)` resolution changes between bulk pre-copy
and the final delta (re-provisioned profile, merged/split user, corrected
mapping):

- **Do NOT derive a new storage key.** The object stays at `final_key` — it is
  tied to the immutable source attachment identity, which did not change.
- Classify **`mapping_drift`** (a sub-reason of `binding_conflict`) and
  **reconcile explicitly**: the existing `ProfilePhoto` binding is re-validated
  against the new mapping; a genuine owner change is an operator/product
  decision, never a silent re-point or a silent re-upload.
- The disposition surfaces in reconciliation; cutover is gated on it being zero
  or a `reviewed_exception`.

### Destination `ProfilePhoto` integration path

1. `final_key` = `Migration::MediaTransfer::CanonicalKey.final_key(identity)`
   (`identity` already carries `canonical_content_type`).
2. **Adopt-or-upload** the `ActiveStorage::Blob` for `final_key` (§7b) with the
   **verified** bytes, explicit `content_type` (canonical), explicit `checksum`
   (computed), `identify: false`,
   `service_name: Media::StorageResolver.service_name(brand:)` — **in Phase A,
   outside the `MediaAttachmentRef` lock** (§7c).
3. **Phase B (short finalization transaction):** `Profiles::PhotoUpload.build_photo!(profile:, user:, brand:, blob:,
   position: <PhotoOrderPlan>, status: <moderation map>, visibility: <moderation map>)`.
4. `Migration::ReferenceMap.bind!` (§10) — **same Phase-B transaction** as step 3.
5. **Phase C — after commit**, `Media::ProcessProfilePhotoJob.perform_later(photo.id)` (§16).

### 7b. Active Storage idempotency / adoption rules — FINAL

`ActiveStorage::Blob` saves the blob **row** before the object is uploaded, `key`
is unique, and **Rails 8.1 exposes no supported "adopt an existing remote
object" API**. For destination key `K` (= `final_key`) and expected identity
`E = {md5, byte_size, canonical_content_type ∈ allowed, dest_service}`:

| Case | Blob row @ K | Object @ K | Content vs `E` | Action |
|---|---|---|---|---|
| **1** | absent | absent | — | **Phase A, no `MediaAttachmentRef` lock.** A tiny **blob-row coordination transaction** does `ActiveStorage::Blob.create_before_direct_upload!`-style row insert for `key: K` (no network) — or catches `RecordNotUnique` and reloads, deferring to case 2/3. **Outside any transaction:** upload the verified bytes (`blob.upload(io)` / `upload_without_unfurling`). Then **re-`HEAD`/stream + re-hash the resulting remote object** vs `E`. This blob-row transaction is **distinct from** the Phase-B `MediaAttachmentRef` finalization lock (§7c) — no network work runs inside either. |
| **2** | present | present | reuse **only** after: lock the blob row; `blob.key == K`; `blob.service_name == E.dest_service`; `blob.checksum == E.md5`; `blob.byte_size == E.byte_size`; `blob.content_type ∈ allowed`; **and** a real streamed re-read of the actual remote object → actual byte count == `E.byte_size`, actual MD5-base64 == `E.md5`, actual magic bytes / decode probe == the safe-media contract | **Safe reuse.** Attach this blob. Any check fails → case 5. |
| **3** | present | absent | orphan blob row | Lock the blob row. Prove `blob.key == K` **and** `blob.service_name == E.dest_service` **and** `blob.checksum == E.md5` **and** `blob.byte_size == E.byte_size` **and** `blob.content_type ∈ allowed`. Re-verify the **source** bytes (§6). Then `blob.upload_without_unfurling(io)` for the verified bytes. Then **re-stream + re-hash the resulting remote object** vs `E`. Any proof fails, or the post-upload verify fails → `binding_conflict` / quarantine. **Never upload to an existing key without all proofs.** |
| **4** | absent | present | — | **`remote_orphan`.** Rails 8.1 has no supported adopt API. **Do not** manufacture an `ActiveStorage::Blob` row. **Do not** overwrite the object. **Do not** delete it. Classify, report PII-free, require **explicit operator recovery outside normal importer execution**. Disposition `binding_conflict` (`remote_orphan`). |
| **5** | row and/or object exists | — | identity / content ≠ `E` (or any case-2/3 proof failed) | **`destination_collision`.** Quarantine → `binding_conflict`. **Never overwrite.** A genuine cross-source key collision is impossible (§7 tuple), so this means corruption or a bug — operator investigates. |
| **6** | a candidate `ProfilePhoto` for this source `Photo` is attached to a blob whose key ≠ `K`, **or** whose owner / brand / `ReferenceMap` state does not exactly match the expected chain | — | — | **Fail closed** → `binding_conflict`. Do not create a second blob, do not re-point the attachment. |

`upload_without_unfurling` / any direct `service.upload` is used **only** in
cases 1 and 3, both in **Phase A** (no `MediaAttachmentRef` lock), both followed
by a real remote-object re-verification. `service.upload` is **never** called for
a key with no committed blob row of matching identity.

### 7c. Attachment-level serialization — short lock, no network under it (BLOCKER 2)

**No R2 streaming, remote hashing, upload, or libvips work is ever done while
holding the `Migration::MediaAttachmentRef` `FOR UPDATE` lock.** The sequence per
source attachment:

**PHASE A — prepare / verify (NO `MediaAttachmentRef` lock held)**

1. load source metadata (`MediaObjectRef` + locator);
2. stream + verify source bytes (§6) → the expected identity `E`;
3. compute `final_key` (§7) and inspect destination object state
   (`ActiveStorage::Blob.find_by(key: K)`, `service.exist?(K)`);
4. perform the safe storage operation for case 1 / 2 / 3 as applicable —
   including the tiny **blob-row coordination transaction** (row insert only, no
   network) and the object upload **outside any transaction**;
5. re-`HEAD` / stream + re-hash the resulting destination object vs `E`;
6. prepare the exact `Blob` + `ProfilePhoto` plan (position from `PhotoOrderPlan`,
   status/visibility from the moderation map).

Two workers may run Phase A concurrently for the same attachment. That is safe
**only because** the deterministic storage identity (§7) plus adopt-or-upload
cases 1–5 (§7b) make every write either a no-op reuse of byte-identical content
or a fail-closed `binding_conflict` — **no unsafe overwrite is possible**. Phase
A performs no domain (`ProfilePhoto` / `ReferenceMap`) creation.

**PHASE B — short finalization transaction**

```
BEGIN
  SELECT Migration::MediaAttachmentRef ... FOR UPDATE          # (source_system, source_attachment_id)
  RECHECK authoritative state:
    - MediaAttachmentRef still maps to the expected MediaObjectRef
    - source expectation E has not drifted (fingerprint match)
    - Migration::ReferenceMap.resolve("date9ja","photo",Photo.id)
    - ActiveStorage::Blob @ K (present, key/service/checksum/byte_size/content_type)
    - the Phase-A remote-verification evidence for K is still applicable
    - candidate ProfilePhoto, if any
    - destination owner / profile / brand mapping
  IF another worker completed this attachment      -> return already_transferred / resume
  IF an existing Photo->ProfilePhoto binding is NOT this exact profile
     (destination_type == "ProfilePhoto" AND profile_id == current_resolved_profile.id
      AND user_id == …  AND brand_id == brand.id  -- same user + wrong profile
      still fails here)                            -> binding_conflict (mapping_drift) — never a silent reparent (review round 2, Finding 2)
  IF mapping changed                               -> binding_conflict (mapping_drift, §7)
  IF source state / E changed                      -> source_changed
  ELSE:
    - create (blob row already exists from Phase A) or reuse the valid Blob representation
    - Profiles::PhotoUpload.build_photo!(...)      # internal domain seam, runs on: :create validations
    - Migration::ReferenceMap.bind!(date9ja/photo/<Photo.id> -> ProfilePhoto)
    - persist required DB state
COMMIT
```

Phase B holds the lock only across in-memory rechecks and local DB writes — no
network, no libvips, no hashing. It **serializes DOMAIN creation/binding**:
exactly one worker creates the `ProfilePhoto` + `ReferenceMap` binding; the rest
observe it and return `already_transferred`.

**`Migration::ReferenceMap` uniqueness is defense-in-depth, not the primary
concurrency control** — the `MediaAttachmentRef` row lock is.

**PHASE C — after commit**

`Media::ProcessProfilePhotoJob.perform_later(photo.id)` (§16). Never enqueued
against a row that could still roll back.

Concurrency behaviour:

| Situation | Outcome |
|---|---|
| worker A + worker B, same attachment | both may run Phase A (safe — §7b); in Phase B, B blocks on the `MediaAttachmentRef` lock; on acquiring it B rechecks and sees A's committed `ProfilePhoto`/binding → `already_transferred`, or A's rollback → B finalizes. |
| worker A crashes mid Phase A | no lock held, no domain rows written; any uploaded object is a byte-verified case-2/3 input for the next attempt. |
| worker A crashes holding the Phase-B lock | DB releases the lock on connection drop; A's short transaction rolls back; B / rerun acquires and finalizes. |
| worker A commits Phase B before B acquires | B rechecks the full-success chain (§8) → `already_transferred`, zero writes. |
| worker A rolls back Phase B before B acquires | B acquires, rechecks: no binding, object present + re-hash == `E` → B finalizes → `transferred`. |

---

## 8. External side effect + DB — recovery design (no new table)

Storage upload is a non-transactional side effect. Every step is made
**idempotent and individually recoverable**; distributed atomicity is not
attempted.

### No new persistence model — destination state is inferred

| Fact | How it is determined (no new column) |
|---|---|
| `source_verified` | Re-computed **every run** (stream + hash + decode probe). Not persisted — re-verification is itself the `source_changed` gate. |
| `destination_object_present` | `blob.service.exist?(K)` **and** a streamed re-hash matching `E` for any reuse decision |
| `destination_blob_present` | `ActiveStorage::Blob.find_by(key: K)` |
| `profile_photo_present` | `Migration::ReferenceMap.resolve("date9ja","photo",Photo.id)` → `ProfilePhoto`; cross-check `photo.image.blob.key == K` |
| `reference_bound` | `Migration::ReferenceMap.resolve(...)` present |
| `processing_enqueued` / `processing_ready` | `ProfilePhoto.processing_state` (`pending` / `processing` / `ready` / `failed`) + display derivative attached |

Recovery is a pure function of
`(K, remote-object verification, ReferenceMap binding, ProfilePhoto.processing_state)`.
`MediaObjectRef.transfer_state` is a **coarse hint only** — recomputed and
written at the end of each attempt, **never** acted on without the inference
cross-check, and it **never overrides observed destination reality**.

If independent review still wants a durable per-attempt audit trail, the minimal
addition would be a standalone `migration_media_transfer_attempts` table keyed
`(source_system, source_attachment_id, destination_purpose, destination_brand)`
with `state`, `disposition`, `attempted_at`, `failure_code` — **proposed only if
review requires it; the recovery contract does not need it** (§13 verdict:
inference-based recovery is sufficient).

### Full-success condition

A photo is `transferred` only when **all** hold: source verified this run;
destination object present at `K` **and** a streamed re-hash matches `E`; a valid
`ActiveStorage::Blob` at `K`; a kept `ProfilePhoto` with `image` attached to that
blob; a `ReferenceMap` binding `date9ja/photo/<Photo.id> → that ProfilePhoto`;
`processing_state == ready` with the display derivative attached.

### Crash / concurrency interleaving resolution

| # | Interleaving | Detection | Retry behaviour | Terminal if unrecoverable | Mutation on detection | Operator? |
|---|---|---|---|---|---|---|
| A | transfer intent formed, upload never starts | no blob row, no object @ K | re-run: case 1 | — | none until upload | no |
| B | upload partially fails / provider error mid-`GET` or mid-`PUT` | object @ K absent or `HEAD` size ≠ `E` or re-hash ≠ `E` | re-run: case 1/3; re-stream + re-verify + re-upload | `destination_failed` after N transient retries | re-uploads exactly the verified bytes to K | no (yes if persistent) |
| C | upload succeeds, process dies before any DB write | blob row + object @ K, re-hash == `E`, no `ReferenceMap` | re-run under the attachment lock: case 2 (verified reuse) → build `ProfilePhoto` + bind | — | attaches existing blob, creates `ProfilePhoto` | no |
| D | blob row created, upload fails | case 3 (row present, object absent) | re-run: lock blob, prove identity, re-upload, re-verify | `destination_failed` | re-upload only | no (yes if persistent) |
| E | remote object exists, blob row absent | case 4 | **none — `remote_orphan`, quarantine** | `binding_conflict` (`remote_orphan`) | **none** — never adopt, never overwrite, never delete | **yes** (explicit operator recovery) |
| F | blob exists, `ProfilePhoto` create fails (validation/lock) | `ReferenceMap` absent, blob @ K present, re-hash == `E` | re-run under the attachment lock: re-attempt build under the profile lock | `destination_failed` (transient) / `quarantined` (persistent validation, e.g. capacity) | none (transaction rolls back) | yes if persistent |
| G | `ProfilePhoto` created, `ReferenceMap` bind fails | `ProfilePhoto` present (blob key == K), no binding | re-run under the attachment lock: **validate** the `ProfilePhoto` was ours (blob key == K, owner/brand/position/status/visibility == plan) → bind; mismatch → fail closed | `binding_conflict` | binds only after full validation | yes if mismatch |
| H | `ReferenceMap` binds, processing enqueue fails (after commit) | `ProfilePhoto` bound, `processing_state == pending`, no job | re-run / sweeper: enqueue (harmless if duplicated — §16b) | `processing_failed` after drain timeout | enqueue only | no |
| I | job enqueued **before** commit | **prohibited by design** (§16) — enqueue is post-commit only | n/a | n/a | n/a | n/a |
| J | processing job ends `failed` | `processing_state == failed` | re-enqueueable (bounded); persistent → terminal | `processing_failed` | none | yes (review the tail) |
| K | complete rerun of a fully-transferred photo | full-success condition holds | no-op | `already_transferred` | **none** | no |
| L | source bytes differ from Pass-1 expectation | step 4/5 mismatch | none — fail closed | `source_changed` | none | yes (classify) |
| M | destination key K has a blob/object with **wrong** bytes | case 5 (or a case-2/3 proof failed) | none — fail closed | `binding_conflict` (`destination_collision`) | none | yes |
| N | final-snapshot `Photo` points at a **different** `blob_id` than Pass-1 | Pass-1 delta records a new `MediaObjectRef`; `source_attachment_id` unchanged but `source_blob_id` changed → new canonical string → new K | transfer the new blob to the new K; old K's `ProfilePhoto` flagged | `source_changed` on the old ref; the new blob transfers normally | new object + new `ProfilePhoto`; old one **flagged, never auto-deleted** (§18) | yes (approve the swap) |
| O | worker A + worker B, same attachment, concurrent | B blocks on the `MediaAttachmentRef` `FOR UPDATE` lock | B re-reads on acquire → `already_transferred` (A committed) or fresh attempt (A rolled back) | — | none by B beyond what it legitimately resumes | no |
| P | worker A crashes holding the transaction lock | DB releases the lock on connection drop; A's txn rolls back | B / rerun acquires the lock and proceeds; any uploaded object is a case-2/3 input | — | none from the crash itself | no |
| Q | worker A commits before B acquires the lock | B re-reads full-success chain | `already_transferred`, zero writes | — | none | no |
| R | worker A rolls back before B acquires the lock | B re-reads: no binding, maybe an uploaded object | B resumes via case 2/3 → `transferred` | — | B's legitimate resume writes only | no |
| S | duplicate `ProcessProfilePhotoJob` for one `ProfilePhoto` | second job's CLAIM sees `processing` (recent `started_at`) or an already-attached valid derivative | second job returns `:in_progress` / `:already_ready`, does no work | — | none | no |
| T | worker claims, then crashes; row stuck `processing` | sweeper: `processing` && `processing_started_at < STALE_THRESHOLD.ago` | sweeper enqueues recovery; next job's CLAIM reclaims (new token + timestamp) | `processing_failed` after bounded retries | reclaim only (token + `started_at` rewritten) | no (yes if it keeps failing) |
| U | ABA — worker A stalls, claim goes stale, worker B reclaims, A wakes | A's FINALIZE/FAILURE: `processing_claim_token != my_token` | A discards its derivative, returns `:lost_claim`, **does not mutate `processing_state`**; B finalizes | — | none by A | no |

**Smallest reliable mechanism:** deterministic final key (§7) + per-attachment
serialization (§7c) + Active Storage adopt-or-upload cases with real
remote-byte verification (§7b) + validated idempotent bind + inference-based
recovery (§8) + concurrency-safe processing (§16b) + orphan detector (§22). No
saga, no 2PC, no outbox, no workflow engine, no new table.

---

## 9. Idempotency contract (Pass 2 rerun)

Per source `Photo`, exactly one terminal disposition (§15). Rerun rules:

| Prior state | Rerun result |
|---|---|
| full-success condition holds (§8) | `already_transferred`, **zero writes** |
| object + blob @ K (re-hash == `E`), no `ProfilePhoto` | resume: verified reuse → build → bind → (post-commit) enqueue |
| object @ K but re-hash ≠ `E`, or object without a matching blob row | `binding_conflict` (`destination_collision` / `remote_orphan`), fail closed |
| `ProfilePhoto` present, no binding | bind **only after** strict validation (blob key == K, owner/brand/position/status/visibility == plan); else `binding_conflict` |
| `ReferenceMap` binding present | validate the whole chain (§8); all good → `already_transferred`; gap → `binding_conflict` / `processing_failed` as applicable |
| destination drift (position/status/visibility ≠ plan, or blob replaced) | `binding_conflict`, fail closed — never silently re-mutate |
| source bytes changed since preflight | `source_changed`, fail closed |

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
fingerprint      = digest(source position, is_primary, moderation_status, source_blob_id, source_attachment_id)
```

Source **blob** ids and **attachment** ids are **never** bound to `ProfilePhoto`.
`ReferenceMap` remains the sole source→destination **domain** binding. Before
accepting an existing `photo` binding as complete, the orchestrator validates the
full-success chain (§8), inside the per-attachment lock (§7c).

---

## 11. Deterministic ordering algorithm (design only — NOT applied this checkpoint)

```
def plan(source_photos):
    ordered   = source_photos.sort_by { |p| [p.position, p.id] }   # deterministic, ties by id
    primaries = ordered.select(&:is_primary)
    raise MultiplePrimary if primaries.length > 1                  # -> quarantine, never guess
    if primaries.length == 1:
        primary = primaries.first
        result  = [primary] + ordered.reject { |p| p.id == primary.id }
    else:
        result  = ordered                                         # position 0 == effective primary
    result.each_with_index.map { |photo, i| { photo:, destination_position: i } }
```

Destination positions are `0..n-1`, contiguous, gap-free. The orchestrator
inserts an owner's photos in this order via
`Profiles::PhotoOrder.prepare_insert!(position: nil)` (append) so the shared
ordering invariant owns position assignment. Rehearsal expectation: 164 owners
one-primary, 2 zero-primary, 0 `MultiplePrimary`.

---

## 12. Moderation / visibility mapping — RESOLVED, no shared-model change

| Source `moderation_status` | `ProfilePhoto.status` | `ProfilePhoto.visibility` |
|---|---|---|
| `pending` (0) | `pending_review` | `visible` (Date9ja `:immediate` policy) |
| `approved` (1) | `approved` | `visible` |
| `rejected` (2) | `rejected` | `hidden` |
| anything else | — | **fail closed** (`moderation_unmapped`, quarantine) |

The migration sets `status`/`visibility` **explicitly** from this table, not via
`Media::PhotoPolicy.initial_state`.

---

## 13. Inference-based recovery — VERDICT

**The no-new-table design holds after Revision 4.** No migration transfer table
is required:

- The final key (§7) depends only on immutable migration/storage identity, so
  `destination_blob_present` / `destination_object_present` remain pure lookups
  that never move.
- Per-attachment serialization (§7c) uses an **existing** row
  (`MediaAttachmentRef`) — no new lock table.
- Case-4 is quarantine, not adoption — an operator, not a state row.
- Processing concurrency (§16b) is solved inside `ProcessProfilePhotoJob` using
  two **nullable columns on `ProfilePhoto`** (`processing_started_at`,
  `processing_claim_token`). These belong to the **`ProfilePhoto` processing
  lifecycle** and are reusable D8N processing hardening — they are **not**
  migration transfer identity and **not** a migration table.

Storage recovery is inferable from: `MediaAttachmentRef`, `MediaObjectRef`, the
canonical migration storage key (§7), `ActiveStorage::Blob`, the verified remote
object, `Migration::ReferenceMap`, `ProfilePhoto`, its processing
state/timestamp/token, and the display derivative. The coarse
`MediaObjectRef.transfer_state` remains a hint that never overrides observed
reality.

---

## 14. `owner_not_imported` / suspended-owner behaviour — RESOLVED

**`owner_not_imported` (3 photos in rehearsal):** no `ProfilePhoto`; preflight
evidence stays intact; blob not transferred; `transfer_state` stays
`not_started`; terminal disposition `owner_not_imported`; **revisitable** — a
later run transfers normally once the owner is imported.

**Suspended owners (3 in rehearsal):** retain photos **structurally**. Suspension
is not deletion. Pass 2 transfers their photos and creates `ProfilePhoto` rows
**normally** with the moderation-derived `status`/`visibility`. **No
photo-specific hiding** is added — public suppression stays the responsibility of
the existing suspended `Profile` / `BrandMembership`. Measured
(`owners_suspended`), not branched; not assumed equal to `owner_not_imported`.

---

## 15. Pass-2 transfer reconciliation contract (PII-free)

Terminal dispositions (mutually exclusive; every source `Photo` gets exactly one):

| Disposition | Meaning |
|---|---|
| `transferred` | verified + object-backed blob (re-hash == `E`) + `ProfilePhoto` + bound + processing `ready`, this run |
| `already_transferred` | rerun; full-success chain validated, nothing written |
| `owner_not_imported` | no Date9ja `Profile` destination; evidence kept, bytes not moved |
| `source_unavailable` | source object missing / unreadable / off-allowlist / redirect |
| `source_changed` | source size or MD5 ≠ `MediaObjectRef` (fail closed) |
| `validation_failed` | not an image / unsupported type / malformed / oversize |
| `destination_failed` | D8N upload or `ProfilePhoto` create failed (transient — retryable) |
| `binding_conflict` | `ReferenceMap` / `ProfilePhoto` / plan / destination-object mismatch, `destination_collision`, `remote_orphan`, or `mapping_drift` (owner `ReferenceMap(profile)` resolution changed after pre-copy — §7) — fail closed, reconcile explicitly |
| `processing_failed` | photo created + bound, safe-derivative job ended `failed` (or drain timeout) |
| `quarantined` | multiple-primary owner, moderation-unmapped, or another explicitly-flagged anomaly for product review |
| `explicitly_skipped` | reserved; a documented policy exclusion only |

**Invariant:** `photos_considered == Σ (exactly one terminal disposition)`.

**Every non-terminal-success disposition is additionally classified
`unexplained_failure` or `reviewed_exception`.** A run may reach cutover only when
`unexplained_failure == 0`.

Aggregate measures (counts only — no PII, no locator, no checksum value, no
per-row id): `total_source_photos`, `bytes_expected`, `bytes_transferred`,
`source_objects_fetched`, `destination_uploads_created`,
`destination_uploads_reused`, `destination_reuse_reverified` (streamed re-hash
count), `destination_orphan_blobs_recovered` (case 3),
`destination_remote_orphans` (case 4 — quarantined),
`destination_collisions` (case 5), `profile_photos_created`,
`profile_photos_reused`, `reference_map_bindings_created`, `processing_enqueued`,
`processing_succeeded`, `processing_failed`,
`processing_jobs_deduplicated` (§16b claim rejections),
`moderation_pending|approved|rejected`, `owners_ordered`, `owners_one_primary`,
`owners_zero_primary`, `owners_multiple_primary_quarantined`,
`owners_flagged_for_review` (§17), `attachment_lock_waits`,
`orphan_transfers_detected`, `missing_destination_objects`, `owner_not_imported`,
`source_checksum_mismatches`, `source_size_mismatches`, `binding_conflicts`,
`mapping_drift` (§7), `processing_stale_reclaims` (§16b),
`processing_claims_lost` (§16b ABA rejections),
`unexplained_failures`, `reviewed_exceptions`.

Rehearsal baseline (from Pass 1): 279 considered, 276 transfer-eligible, 3
`owner_not_imported`, 0 `owners_multiple_primary_quarantined`,
`profile_photos_created` 276 on a clean first run, 0 on rerun.

---

## 16. Processing strategy + post-commit enqueue boundary

**Enqueue the existing `Media::ProcessProfilePhotoJob`, then block the run on a
bounded drain loop** until every enqueued photo reaches `processing_state ∈
{ready, failed}` (timeout → `processing_failed`, not a hang).

**Enqueue boundary:** the `ProfilePhoto` build + `image.attach` +
`ReferenceMap.bind!` run in the **Phase-B short finalization transaction** (§7c),
holding the `MediaAttachmentRef` lock only across in-memory rechecks and local DB
writes — no network. `perform_later` is **Phase C**, called **after that
transaction commits** — from the orchestrator, explicitly, *not* from an
`after_commit` model callback. A job is **never** enqueued against a row that
later rolls back. If the enqueue itself fails post-commit, the `ProfilePhoto`
exists with `processing_state == pending` and no job; the sweeper re-enqueues it
(§16b — safe even if it double-enqueues).
Reconciliation distinguishes **`created/bound`** from **`processing_enqueued`**
from **`processing_ready`**; a photo is **not** `transferred` until
`processing_ready`.

### 16b. Concurrency-safe `Media::ProcessProfilePhotoJob` + stale-claim recovery (BLOCKER 3 — shared D8N hardening)

`processing_state == pending` does **not** prove no job is running, and
`processing` does **not** prove the owning worker is still alive (a crash after
the claim leaves the row stuck `processing` forever). Fix — the **smallest
durable claim**: two nullable columns on `ProfilePhoto`, no long transaction
across libvips, no distributed lease subsystem.

**Schema (shared processing hardening, a `ProfilePhoto` migration — NOT a
migration transfer table):**

```
add_column :profile_photos, :processing_started_at, :datetime, null: true
add_column :profile_photos, :processing_claim_token, :uuid,     null: true
```

The four `processing_state` values are unchanged: `pending` / `processing` /
`ready` / `failed`.

**CLAIM — short transaction**

```
my_token = SecureRandom.uuid
ProfilePhoto.transaction do
  photo = ProfilePhoto.lock.find(id)                              # SELECT ... FOR UPDATE

  return :verify_ready if photo.processing_ready?   # confirm OUTSIDE this lock — see below

  if photo.processing_pending? || (photo.processing_failed? && retryable?(photo))
    photo.update!(processing_state: :processing,
                  processing_started_at: Time.current,
                  processing_claim_token: my_token)               # claim / retry-claim
  elsif photo.processing_processing?
    if photo.processing_started_at && photo.processing_started_at > STALE_THRESHOLD.ago
      return :in_progress                                         # a live worker owns it
    else
      photo.update!(processing_started_at: Time.current,
                    processing_claim_token: my_token)             # RECLAIM a stale claim
    end
  else
    return :terminal                                              # non-retryable failed
  end
end
```

**VERIFY READY — outside any transaction** (review round 2, Finding 1)

```
# The ONLY proof of completion is the single authoritative contract:
#   Media::DisplayDerivative.valid?(photo:, expected_display_key:, expected_service:)
# a BOUNDED remote read of the exact deterministic display artifact —
# attachment ownership + exact key + service + content type + Blob.checksum
# integrity of the streamed bytes + JPEG decode. No metadata-only shortcut.
return if display_valid?(photo)                    # completed transfer confirmed — no-op
if photo.image.attached?                           # raw still present -> rebuild
  reclaim_for_repair!(photo); goto WORK
else                                               # raw already purged -> honest terminal failure
  mark_terminal_failure!(photo, "display_unrecoverable")
end
```

The exact `expected_display_key` is `Media::ObjectKey.profile_photo_display(raw_key)`
while the raw is attached, and after purge is re-derived from persisted
`ProfilePhoto#metadata` (`raw_object_key` / `display_object_key` /
`display_service_name` — the existing jsonb column, **not** a new table),
cross-checked against the deterministic relation.

**WORK — outside any transaction**

```
derivative = build_safe_derivative(photo)   # decode -> re-encode -> strip EXIF/GPS -> upload display blob
                                            # display key deterministic: Media::ObjectKey.profile_photo_display(final_key)
                                            #   -> find_by(key:) || create_and_upload!  (already idempotent)
```

**FINALIZE — short transaction**

```
ProfilePhoto.transaction do
  photo = ProfilePhoto.lock.find(id)
  unless photo.processing_processing? && photo.processing_claim_token == my_token
    discard_unattached(derivative); return :lost_claim            # someone reclaimed/finalized; DO NOT mutate state
  end
  if photo.display_image.attached?
    return :already_finalized if valid_display?(photo)            # valid D8N-owned display blob at the expected key
    raise ProcessingConflict                                     # conflicting non-D8N derivative -> fail closed
  end
  photo.display_image.attach(derivative)
  photo.update!(processing_state: :ready,
                processing_started_at: nil,
                processing_claim_token: nil)
  photo.image.purge_later                                        # raw purged ONLY after the valid derivative is attached
end
```

**FAILURE — short transaction**

```
ProfilePhoto.transaction do
  photo = ProfilePhoto.lock.find(id)
  return :lost_claim unless photo.processing_processing? && photo.processing_claim_token == my_token
  photo.update!(processing_state: :failed,             # retryable/non-retryable classification per the existing contract
                processing_started_at: nil,
                processing_claim_token: nil)
end
```

`retry_on TransientError, attempts: 5` is unchanged and remains the bounded-retry
mechanism.

**CRASH AFTER CLAIM:** no rescue code needs to run. The row stays
`processing` with an old `processing_started_at` and its now-orphaned
`processing_claim_token`. The sweeper later detects the stale `processing` and
re-enqueues; the next job's CLAIM reclaims it (new token, new timestamp).

### Claim ownership / ABA safety — the claim token is REQUIRED

`processing_started_at` **alone is not sufficient.** The ABA race:

1. Worker A claims (`started_at = t0`).
2. A stalls; the claim goes stale.
3. Worker B reclaims (`started_at = t1`).
4. A wakes and tries to finalize.

With only a timestamp, A's finalize would see `processing_state == processing`
and attach **A's** stale derivative over **B's** active claim. A `started_at`
comparison does not close this — A could read `started_at` before B writes `t1`
and still pass a naive check, and even a "started_at unchanged" check is a
value-equality (ABA) test, not an ownership test.

**Therefore: `processing_claim_token` (a fresh `SecureRandom.uuid` written on
every claim and reclaim).** The worker carries its token. FINALIZE and FAILURE
mutate state **only when** `processing_state == processing AND
processing_claim_token == my_token`. On mismatch the worker **discards its
derivative and does not mutate `processing_state`** (`:lost_claim`). On `ready`
or terminal `failed` the token and timestamp are cleared. This is a
timestamp + token pair — simple, durable, no lease service.

**Derivative attachment idempotency:** the display key is deterministic
(`Media::ObjectKey.profile_photo_display(final_key)`), so `find_by(key:) ||
create_and_upload!` never makes a duplicate object; the FINALIZE transaction
plus the token check guarantee exactly one execution attaches it.

### Sweeper — final contract

**Considers:** `pending` · retryable `failed` · **stale `processing`**
(`processing_started_at < STALE_THRESHOLD.ago`).

**Does NOT re-enqueue:** `ready` · non-retryable `failed` · recent/active
`processing` (`processing_started_at >= STALE_THRESHOLD.ago`).

For stale `processing` it enqueues a recovery job; that job's CLAIM atomically
reclaims via the timestamp + token contract. **Duplicate enqueue stays harmless**
— only the worker holding the current `processing_claim_token` can finalize.
Bounded retry uses the existing `retry_on ... attempts: 5` semantics; a photo
that exhausts retries lands in non-retryable `failed` and the sweeper leaves it
for review.

**`processing_started_at` / `processing_claim_token` belong to the `ProfilePhoto`
processing lifecycle**, not to migration transfer identity. Native D8N uploads
get the same crash-recovery for free.

**Regression tests required** — see §24.

**Operator tuning (not a design blocker):** `STALE_THRESHOLD` value; drain
timeout value.

---

## 17. Failure / quarantine model + publication policy — RESOLVED

**Global blockers (abort the whole run, transfer nothing):**
- Date9ja snapshot schema-signature (v2) failure.
- Source storage config unsafe/absent, endpoint host off-allowlist, or non-HTTPS.
- **Any photo blob on a `service_name` other than `cloudflare`** in the final
  snapshot (sanitized census found none — §2 — but the run re-asserts it).
- Destination `Media::StorageResolver` cannot resolve a private D8N service.
- Systemic checksum-algorithm mismatch (a sample of known objects all fail MD5).
- Wrong/inactive brand.

**Per-photo quarantine (run continues), disposition as in §15:**
- source object missing / redirect (`source_unavailable`)
- malformed / non-image / oversize / unsupported (`validation_failed`)
- source bytes changed since preflight (`source_changed`)
- multiple source primaries for one owner (`quarantined`)
- moderation value unmapped (`quarantined`)
- `ReferenceMap` / destination-object mismatch, `destination_collision`,
  `remote_orphan` (`binding_conflict`)

**Publication policy — RESOLVED:**
- A failed/quarantined **non-primary** photo does **not** automatically block an
  otherwise-valid profile. The other photos transfer; the profile publishes.
- The owning profile is **flagged for explicit review**
  (`owners_flagged_for_review`) when **either** (1) the failed/quarantined photo
  is the owner's **only** usable photo, **or** (2) a failed source **primary**
  prevents deterministic acceptable primary semantics.
- The migration **never silently selects a new source-semantic primary.**

---

## 18. Production cutover / media-delta strategy — RESOLVED shape

Model: **hybrid — bulk pre-copy → final authoritative snapshot → final delta →
reconciliation → cutover.**

1. **Bulk pre-copy (days before):** Pass 2 against a recent production restore
   into the pre-provisioned D8N private storage (or option C's export).
   Idempotent, re-runnable.
2. **Freeze window (short):** restore the final production snapshot. Re-run
   identity Pass + photo Pass 1 + photo Pass 2. Only the **delta** does real work.
3. **Final delta reconciliation:** the Pass-2 invariant is clean and
   `unexplained_failure == 0`, and the source↔destination diff is empty or fully
   covered by an approved `reviewed_exception` list, before cutover completes.

### Final delta algorithm (final snapshot is authoritative)

| Change | Detection | Action (NO automatic destructive cleanup) |
|---|---|---|
| **new** `Photo` row | no `ReferenceMap(photo)` binding | transfer normally → `transferred` |
| **removed** `Photo` row | binding exists, source row gone | **flag** `source_removed`; the D8N `ProfilePhoto` is **not auto-deleted**; explicit operator/product cleanup decision |
| changed **`blob_id`** on the attachment | Pass-1 delta records a new `MediaObjectRef`; `source_blob_id` in `canonical` changes → new K | transfer the new blob; old `ProfilePhoto` flagged for the swap (interleaving N) |
| changed **checksum** / **byte_size** / **content_type** (same `blob_id`) | step 4/5/6 mismatch vs `MediaObjectRef` | `source_changed`, fail closed, flag |
| changed **`moderation_status`** | mapped `status`/`visibility` ≠ bound `ProfilePhoto` | `binding_conflict` (drift) → re-apply is an explicit reviewed action |
| changed **`position`** / **`is_primary`** | `PhotoOrderPlan` result ≠ bound positions | `binding_conflict` (drift) → explicit reviewed re-order |
| owner **status** change (active↔suspended) | identity delta | structural only (§14); no photo action |
| owner **mapping** change (`ReferenceMap(profile)` now resolves differently) | identity delta | previously `owner_not_imported` → now transfers; a changed resolution for an already-transferred photo → **`mapping_drift`** (§7) — the storage object is **not** re-keyed (it is tied to the immutable source attachment); the `ProfilePhoto` binding is re-validated against the new mapping as an explicit operator/product decision, never a silent re-point or re-upload |

**Any candidate reused destination object during the final delta MUST undergo the
same actual-remote-byte verification as §7b case 2** (streamed re-read + re-hash
vs `E`) — a bulk-copy object is not trusted at cutover on metadata alone.

**`source_removed`:** auto-flag for review, never auto-delete the D8N
`ProfilePhoto`. Final source snapshot remains authoritative.

**Operator decision still open:** confirmation that the bulk-copy destination is a
real pre-provisioned D8N private prefix that becomes production, and the
acceptable freeze-window length.

---

## 19. Security review

| Concern | Design |
|---|---|
| SSRF / arbitrary endpoint | `SourceReader` accepts only `{bucket, key}`; the endpoint is **constructed from `_ACCOUNT_ID`**, never from a caller/DB/snapshot/argument (§5b); host must match a hard-coded allowlist. **Redirects refused.** HTTPS only. |
| Credential scoping | Source token read-only, bucket-scoped, run-environment-only (§5). Destination creds untouched and separate. No write/delete/copy method on `SourceReader`. |
| Private storage both ends | Source private R2; destination via `Media::StorageResolver.service_name` (private D8N R2). No public URL generated in Pass 2. |
| Key / path traversal | Legacy keys are opaque S3 object keys, never filesystem paths; the reader refuses absolute / `..` keys. The migration destination key is a fixed `migrations/media/v3/date9ja/profile_photo_original/<UUIDv5>/original.<ext>` shape (§7) — every segment is a constant, a stable token, or a hash of the canonical migration identity; no source-controlled string, no PII, no mutable slug. |
| Object-size limits | 8 MB hard ceiling enforced **while streaming** (abort mid-download), before any decode. |
| Decompression / image bombs | `Media::ImageProcessor` header probe (12 000 px/edge, 40 MP) before any full decode; the re-encode in `ProcessProfilePhotoJob` has the same guards. |
| Malformed image parsing | libvips selects the loader from bytes; a non-image/truncated file → terminal `validation_failed`, never retried. |
| Blind overwrite | §7b — an existing object whose content ≠ `E` is **never overwritten**; case 4 (`remote_orphan`) is quarantined, not adopted. |
| Log redaction | No storage key, credential, checksum value, signed URL, email, name, or per-row id logged. `source_blob_id` + disposition + safe failure code only. |
| Temp-file permissions / cleanup | `0600` under a migration-only root; `unlink` in `ensure` on every path including exceptions. |
| Crash / concurrency recovery | Inference-based (§8) + per-attachment row lock (§7c) + concurrency-safe processing (§16b); a crashed or double-run leaves only re-attemptable state, never a duplicate or a silent gap. No new plaintext-locator column. |
| Cross-brand isolation | `source_system = "date9ja"` on every migration row; `ReferenceMap.bind!` enforces `destination.brand_id == date9ja.brand.id`; the canonical string includes `destination_brand` + `destination_brand_slug`. |
| Source immutability | `SourceReader` issues only `HEAD` / streamed `GET`. |

### Security corrections carried / added in Revision 3

- **`SourceReader` implementation security contract** written down explicitly
  (§5b) — endpoint constructed from config only, caller endpoints rejected,
  HTTPS-only, redirects refused, no write/delete/copy, bounded `0600` temp files
  cleaned in `ensure`, dimension/pixel ceilings, bounded retry, redacted provider
  exceptions, no sensitive logging.
- **No remote-orphan adoption** (§7b case 4) — closes the "manufacture a blob row
  for an object we cannot prove we own" path.
- **Real remote-byte verification on every reuse** (§7b cases 2/3, §18) — closes
  "trust `ActiveStorage::Blob` metadata for a possibly-tampered object".
- Carried from Rev 2: no persisted locator column; HTTPS-only + endpoint
  construction; no `service.upload` for a key with no matching committed blob row.

---

## 20. Reused source blob → destination object contract

Pass 1 observed `blob_reuse_objects = 0`, but the contract must be correct for
future imports that do reuse blobs.

**General rule:** one source storage object → **one destination
`ActiveStorage::Blob` per destination attachment/use** (per `destination_purpose`
× `destination_brand` × `source_attachment_id`).

**Decision: Option B (copy per use), not sharing one D8N blob.** Verified in D8N
code: `Media::ProcessProfilePhotoJob` **purges the raw `image` blob**
(`purge_later`) once the safe derivative exists; `ProfilePhoto` attachment
lifecycle purges the blob on delete; `Profiles::PhotoUpload.attach!` **`raise
AlreadyAttached if blob.attachments.exists?`**.

**Deduplication happens only at the source-download layer:** within a run,
`Migration::MediaTransfer` may cache the verified bytes for a `source_blob_id` so
a reused blob is fetched + hashed + decode-probed **once**, then written to N
independent destination blobs (one per `source_attachment_id`). This is why the
canonical string (§7) discriminates on `source_attachment_id`.

---

## 21. Synthetic / sanitized media rehearsal design — DISTINCT ARTIFACT

> **STATUS 2026-09-03: L1 + L2 BUILT, GREEN, AND INDEPENDENTLY VERIFIED (Codex
> 2026-09-03: FINAL VERDICT ACCEPT — L2 review loop closed; not production /
> cutover ready; L3 not approved).** The
> artifact is a `CREATE DATABASE … TEMPLATE date9ja_snapshot_sanitized` copy on
> the isolated PG17 instance with only `active_storage_blobs.byte_size` /
> `checksum` rewritten on the 279 Photo image blobs. Generator / verifier /
> transport: `Date9ja::Snapshot::SyntheticMedia` (`render` — deterministic
> AES-CTR keystream pixels → libvips jpeg/png/webp; `Generator`; `Verifier` —
> 15 checks), `Date9ja::Snapshot::SanitizedParentConnection`,
> `Date9ja::Storage::LocalCorpusReader` (drop-in for `SourceReader`, local files,
> bounded, fail-closed). Shared key safety + path containment (symlink-escape
> aware): `Date9ja::Storage::SafeObjectKey` — read and write both depend on it,
> so the generator fails closed before writing any object on a key the reader
> would refuse, and every write is proven strictly under the corpus root. The
> verifier proves, schema-driven, that media_v2 changed ONLY
> `byte_size`/`checksum` and ONLY on the 279 authorized Photo blob rows (from the
> attachment graph, not the manifest) across the whole `active_storage_blobs`
> table, and that every manifest field binds field-for-field to its authoritative
> blob row (checks 16, 17). Check 16 types manifest `byte_size` strictly (a
> non-negative JSON integer only — no `.to_i` coercion of malformed text); check
> 17 compares column values null-safely (`db_value_equal?` — SQL NULL, `''`,
> `0` and `false` are all distinct), never via `.to_s`. Rake: `date9ja:build_media_v2`,
> `date9ja:verify_media_v2`, `date9ja:transfer_photos` (L2-wired via
> `DATE9JA_MEDIA_CORPUS_DIR`). Corpus:
> 279 objects (252 jpeg / 21 png / 6 webp), manifest fingerprint
> `ebcff28a796a230807fbdbfeb19ff63a…`, byte-identical across two runs. Full L2
> rehearsal results: `STATUS.md` "L2 rehearsal" and `RECONCILIATION.md` "Pass-2
> L2 synthetic-corpus rehearsal". L3 (scoped read-only R2 transport) remains
> **NOT YET READY**.

**`date9ja_snapshot_sanitized` is NOT rewritten or relabelled.** It remains valid
historical evidence — the verified sanitized *source* rehearsal artifact
(identity Pass, photo Pass 1). Revision 2's "regenerate its blob rows in place"
plan is **withdrawn**.

### New artifact: `date9ja_snapshot_sanitized_media_v2`

A **distinct, derived** synthetic-media transfer rehearsal artifact. Classified
separately:

| Artifact | Role |
|---|---|
| `date9ja_snapshot_sanitized` | verified sanitized **source** rehearsal artifact (identity + photo Pass 1). Unchanged. |
| `date9ja_snapshot_sanitized_media_v2` | derived **synthetic-media transfer** rehearsal artifact (photo Pass 2 L1/L2). New. |

`v2` is **not** a replacement for `v1` and `v2` synthetic evidence does **not**
supersede `v1`'s identity/Pass-1 evidence.

**Correct principle:** generate synthetic bytes → compute *their* real
MD5-base64, byte size, and magic-byte content type → those become the expected
values `MediaObjectRef` carries and the whole pipeline checks against. Synthetic
bytes **never** target production checksums.

**`v2` generation procedure (design — NOT run this turn):**

1. Start from the canonical sanitized source graph (`v1`): preserve
   `source_system`, `source_blob_id`, `source_attachment_id`, attachment
   topology, owner relationships, ordering, `moderation_status`, `is_primary`.
2. For each of the 279 photo blobs, a generator produces a procedural
   JPEG/PNG/WebP fixed by a `source_blob_id` seed (deterministic, reproducible).
3. **In the `v2` artifact only**, rewrite `active_storage_blobs`
   `checksum` / `byte_size` / `content_type` for the synthetic photo corpus to
   the generated files' **actual** values. The canonical `v1` snapshot and the
   canonical **production** snapshot are untouched.
4. Write the corpus to a local S3-compatible source (MinIO) or Active Storage
   `Disk` under a rehearsal root, keyed `source_blob_id → object`.
5. Pass 1 preflight against `v2` records self-consistent
   `MediaObjectRef.checksum/byte_size/content_type`; Pass 2 verification (§6)
   passes because the synthetic file genuinely has that size/MD5/signature and
   decodes. **The production transfer code path runs unchanged — no test-only
   branch.**

**`v2` must carry its own:** generation procedure, artifact manifest, artifact
checksum/fingerprint, schema fingerprint, synthetic-corpus fingerprint,
sanitizer/verifier result, Pass 1 rerun result, and reconciliation baseline —
all recorded in `SNAPSHOT-RUNBOOK.md` / `RECONCILIATION.md` when it is built.

### Staged rehearsal levels

| Level | Corpus | Proves |
|---|---|---|
| L1 — unit/synthetic | a handful of generated images + injected failures (missing object, truncated, wrong checksum, non-image, oversize, multi-primary, orphan blob row, remote orphan, collision, concurrent workers, duplicate processing job) | verification order, every disposition, all §7b cases, all §8 interleavings A–U, PII-free reconciliation |
| L2 — full `v2` rehearsal | all 279 synthetic objects, local source | end-to-end scale, ordering across 166 owners, invariant, rerun = zero duplicates, per-attachment serialization, processing drain, post-commit enqueue, concurrency-safe job |
| L3 — controlled real rehearsal (pre-cutover) | real production restore + real read-only source R2 (scoped token, §5) or an exported bundle, into pre-provisioned D8N private storage | real bytes transfer, real checksums match, real images decode; the only run touching real media; operator-only; evidence in `RECONCILIATION.md` |

**All 279 must be represented at L2 and L3.** A subset is acceptable only at L1.
The `v2` artifact is **not created in this design turn**.

---

## 22. Orphan model

Four distinct concepts, each with a **PII-free detector**, an **ownership proof**,
and a **quarantine/recovery** rule. **No auto-delete inside normal importer
execution.**

| Concept | Definition | Detector (PII-free) | Ownership proof required | Rule |
|---|---|---|---|---|
| **orphan blob row** | `ActiveStorage::Blob` row at a derivable K, destination object absent | for each `MediaAttachmentRef`, derive K; `Blob.find_by(key: K)` present && `service.exist?(K)` false | K == the canonical-string UUIDv5 for a known `date9ja` `MediaAttachmentRef` **and** `blob.key == K` **and** `blob.service_name == E.dest_service` **and** `blob.checksum == E.md5` **and** `blob.byte_size == E.byte_size` **and** `blob.content_type ∈ allowed` | lock the blob row, re-verify **source** bytes, `upload_without_unfurling`, re-verify the remote result (§7b case 3); any proof fails → quarantine |
| **remote orphan object** | destination object at K, no `ActiveStorage::Blob` row | `service.exist?(K)` true && `Blob.find_by(key: K)` nil | — (no supported adopt path exists) | **`remote_orphan` → quarantine / explicit operator recovery.** Never adopt, never overwrite, never delete inside the importer (§7b case 4). |
| **unattached imported blob** | blob + object at K exist (re-hash == `E`), no `ProfilePhoto` attached | K derivable from a `MediaAttachmentRef`; `blob.attachments.empty?` | K == the canonical UUIDv5 for that `MediaAttachmentRef` **and** streamed re-hash == `E` | resume under the per-attachment lock: build `ProfilePhoto` + bind (§9); if the owner is `owner_not_imported`, leave and record — do not delete |
| **unbound `ProfilePhoto`** | `ProfilePhoto` exists (blob key == some K), no `ReferenceMap(photo)` | `ProfilePhoto` whose `image.blob.key` matches a derivable K, `ReferenceMap.resolve` nil | blob key == canonical UUIDv5 for a known `MediaAttachmentRef` **and** owner/brand/position/status/visibility == the plan | bind (§9 strict validation) under the per-attachment lock; any mismatch → `binding_conflict`, fail closed |

**No object or row is ever deleted because its key merely matches a migration
prefix.** Deletion, if ever authorised, is a **separate, explicit, logged
operator path** that takes the specific `MediaAttachmentRef` id, re-proves
ownership, and acts on exactly that one object.

---

## 23. Shared media seam — FINAL (Codex selected the extraction)

Migration needs the same `ProfilePhoto` build that `Profiles::PhotoUpload.attach!`
performs, but with **explicit** `position` (source order) and **explicit**
`status`/`visibility` (moderation map). No lower-level seam exists today.

**Decision (FINAL — the Codex final review selected this; there is no A/B choice
left):** a **minimal internal extraction**, not a new top-level class.

- Factor the ProfilePhoto-build block (build + `image.attach` + `save!` under the
  profile lock + capacity check) into
  `Profiles::PhotoUpload.build_photo!(profile:, user:, brand:, blob:, position:,
  status:, visibility:)`.
- `attach!` calls it with policy-derived args (unchanged external behaviour).
- `Date9ja::Import::PhotoTransfer` calls it with explicit args, after its own
  `Migration::MediaTransfer` verification and inside the per-attachment lock.

**It is an INTERNAL DOMAIN helper, not a controller-facing API.** It owns
`ProfilePhoto` **domain invariants**:

- `ProfilePhoto` validity (all `on: :create` validations run);
- the owner / profile / brand relationship (`profile_matches_scope`);
- capacity constraints (`within_brand_photo_limit` / `ensure_capacity!`);
- attachment invariants (`image_is_attached`, content-type, size).

**It does NOT own request authorization.** The HTTP `attach!` path remains solely
responsible for authenticating the caller, authorizing the profile, and deriving
policy state (`Media::PhotoPolicy.initial_state`). Migration orchestration is
**trusted offline infrastructure** — it still must obey every domain invariant
`build_photo!` enforces, but there is no end-user request to authorize.

**Migration-specific behaviour stays out of `Profiles::PhotoUpload`:** source
reader, legacy ids, Date9ja ordering, moderation mapping, reconciliation,
retry/disposition/recovery state — all in `Date9ja::Import::*` /
`Migration::MediaTransfer`.

**Regression risk + required tests:** see §24. The extraction must leave
`attach!`'s external behaviour byte-identical; the standalone-duplication
fallback from Revision 3 is **withdrawn**.

---

## 24. Tests required before implementation is accepted

**`Migration::MediaTransfer::CanonicalKey` — KEY STABILITY (shared, unit):**
- **same complete canonical identity (including `canonical_content_type`) ⇒ same
  `final_key`**, always;
- **`image/jpeg` vs `image/png` ⇒ different canonical identity / `object_uuid` /
  `final_key`** (and different `<ext>`);
- **the `<ext>` always corresponds to `canonical_content_type`**
  (`Media::ObjectKey.extension_for`);
- **the final key has no undeclared identity input** — every path segment is a
  literal, the stable `destination_brand` token, `object_uuid`, or the
  `canonical_content_type`-derived extension, all present in `canonical`;
- **changing `Brand#slug` does NOT change the `final_key`**;
- **changing `Profile#public_id` does NOT change the `final_key`**;
- **destination `User`/`Profile` remapping does NOT derive another storage key**;
- each of the seven identity fields (`version`, `source_system`, `source_blob_id`,
  `source_attachment_id`, `destination_purpose`, `destination_brand`,
  `canonical_content_type`) changing ⇒ a different `final_key`;
- `final_key` matches `migrations/media/v3/date9ja/profile_photo_original/<uuidv5>/original.<ext>`;
- `object_uuid` is `Digest::UUID.uuid_v5(KEY_NAMESPACE, canonical_string)` exactly;
- **source content-type drift** (verified `canonical_content_type` differs from
  the recorded/prior value) ⇒ `source_changed`, surfaced in reconciliation —
  **no** replacement key is derived or used as the same source state;
- **mapping drift** (owner `ReferenceMap(profile)` resolution changes) ⇒
  `binding_conflict` (`mapping_drift`), **no** new key, **no** re-upload.

**`Migration::MediaTransfer` adopt-or-upload (shared, unit + integration):**
- case 1 upload then post-upload re-verify;
- case 2 reuse only after full metadata match **and** streamed re-hash; a
  tampered remote object (metadata matches, bytes differ) ⇒ `destination_collision`;
- case 3 orphan-row recovery: proofs enforced, `upload_without_unfurling`, remote
  re-verify; missing any proof ⇒ quarantine;
- case 4 `remote_orphan` ⇒ quarantine, **no** blob row created, object untouched;
- case 5 collision ⇒ never overwrite;
- case 6 wrong-key candidate `ProfilePhoto` ⇒ fail closed.

**LOCK SCOPE (`Date9ja::Import::PhotoTransfer`, integration):**
- **source read occurs with NO `MediaAttachmentRef` lock held** (asserted via a
  seam / instrumentation);
- **remote upload occurs with NO `MediaAttachmentRef` lock held**;
- **remote re-hash occurs with NO `MediaAttachmentRef` lock held**;
- **libvips work occurs with NO `MediaAttachmentRef` lock held**;
- the Phase-B short finalization transaction serializes two workers — exactly one
  `ProfilePhoto` + one `ReferenceMap` binding; the loser returns
  `already_transferred`;
- **two Phase-A workers converge to one `ProfilePhoto` / `ReferenceMap`** and one
  destination object;
- worker holding the Phase-B lock rolls back ⇒ next acquirer finalizes;
- worker commits Phase B ⇒ next acquirer no-ops;
- the tiny blob-row coordination transaction is distinct from the
  `MediaAttachmentRef` lock (a second Phase-A worker hitting `RecordNotUnique`
  falls to case 2/3, no error surfaced).

**Byte verification (`Migration::MediaTransfer`, unit):**
- size mismatch ⇒ `source_changed`; checksum mismatch ⇒ `source_changed`;
  non-image ⇒ `validation_failed`; oversize aborts mid-stream; 40 MP / 12 000 px
  ⇒ `validation_failed`; temp file `unlink`ed on every path including raises.

**`SourceReader` (date9ja, unit):**
- caller-supplied endpoint rejected; non-HTTPS rejected; `3xx` ⇒
  `source_unavailable` + security event, `Location` not followed; no
  `PUT`/`DELETE`/`COPY` method exists; off-allowlist host ⇒ raise; missing config
  ⇒ raise at construction; provider exception message redacted.

**PROCESSING — `Media::ProcessProfilePhotoJob` (shared, regression):**
- **worker dies after claim** ⇒ row stays `processing` with an old
  `processing_started_at`; no rescue code runs;
- **stale `processing` becomes reclaimable** (`started_at < STALE_THRESHOLD.ago`);
- **recent `processing` is NOT reclaimed** (`started_at >= STALE_THRESHOLD.ago`) ⇒
  second job returns `:in_progress`;
- **two workers race to reclaim the same stale photo** ⇒ exactly one wins the
  CLAIM transaction; the other sees the new token and returns `:in_progress`;
- **only one claim token wins** — the finalize/failure `UPDATE` is gated on
  `processing_state == processing AND processing_claim_token == my_token`;
- **old worker wakes after a newer claim and cannot finalize** ⇒ returns
  `:lost_claim`, discards its derivative, **does not mutate `processing_state`**
  (`processing_claims_lost`);
- **duplicate jobs produce exactly one valid attached derivative**;
- **`ready` is never reprocessed** (CLAIM returns `:already_ready`);
- **the original raw blob is purged only after a valid derivative is attached**;
- **retryable `failed` work clears the old claim** (`processing_started_at` /
  `processing_claim_token` → NULL on entry to `failed`);
- **non-retryable `failed` work is not swept**;
- **the sweeper reclaims stale `processing`** and does not touch `ready` /
  non-retryable `failed` / recent `processing`;
- claim + finalize + failure transactions are short — **no libvips inside a
  transaction** (asserted via a seam / instrumentation);
- **all existing `Media::ProcessProfilePhotoJob` tests stay green** (the new
  columns are nullable; the enum is unchanged).

**`Profiles::PhotoUpload.build_photo!` extraction (shared, regression):**
- all existing `Profiles::PhotoUpload` tests green unchanged;
- `build_photo!` direct: explicit position/status/visibility honoured; capacity
  boundary raises `LimitReached`; validation failures surface; profile lock held;
- `attach!` still produces `Media::PhotoPolicy` defaults (policy path unchanged);
- ordering of capacity check vs `prepare_insert!` unchanged.

**Reconciliation (`Date9ja::Import::PhotoTransferReconciliation`, unit):**
- `photos_considered == Σ dispositions`; every non-success disposition also
  `unexplained_failure` xor `reviewed_exception`; output carries no key,
  checksum value, email, name, or per-row id.

**L1 harness (integration):** every disposition and every interleaving A–U
reachable with injected fixtures; rerun ⇒ zero duplicate rows / objects.

All previously accepted (Revision 3) test requirements are retained.

---

## Resolved vs. open

### Closed / accepted — not reopened
ADR 0027; `MediaObjectRef` boundary (source-only, no destination columns);
`ReferenceMap` role; reused-blob model (one destination blob per source
attachment/use, no destination-checksum dedup); Active Storage cases 2/3/4;
remote-orphan quarantine; source verification; synthetic-artifact design
(`date9ja_snapshot_sanitized` untouched, distinct `_media_v2`); source-reader
security direction; `service_name` census (`cloudflare` = 279); Date9ja
moderation mapping; suspended owners retain media structurally; hybrid delta; no
destructive cleanup; inference-based recovery concept; **shared seam —
`Profiles::PhotoUpload.build_photo!` extraction (FINAL, Codex selected it)**.

### Resolved — architecture (Revision 4 — the three final blockers + identity correction)
- **Migration storage key** is a **total function of the complete declared
  canonical identity**: `version` + `source_system` + `source_blob_id` +
  `source_attachment_id` + `destination_purpose` + `destination_brand` +
  `canonical_content_type` (the seventh field — added in the FINAL
  acceptance-check correction because it drives `<ext>`). No user id, no profile
  public id, no mutable `Brand#slug`, no destination `Profile` mapping input, **no
  undeclared input**. A dedicated
  `Migration::MediaTransfer::CanonicalKey.final_key` helper produces
  `migrations/media/v3/date9ja/profile_photo_original/<uuidv5>/original.<ext>` and
  does **not** route through `Media::ObjectKey.profile_photo_original`. Mapping
  drift → `binding_conflict` (`mapping_drift`), no re-key; verified source
  content-type drift → `source_changed` (§7).
- **Short attachment lock** — Phase A (prepare/verify, no lock) / Phase B (short
  finalization transaction) / Phase C (after commit). No R2 streaming, hashing,
  upload, or libvips under the `MediaAttachmentRef` lock. The tiny blob-row
  coordination transaction is distinct from the finalization lock (§7c, §8).
- **Abandoned processing claim** — `ProfilePhoto.processing_started_at` +
  `processing_claim_token` (nullable; `ProfilePhoto` processing-lifecycle
  hardening, **not** a migration table). Claim / stale-reclaim / finalize /
  failure gate on `processing_state == processing AND claim_token == my_token`,
  defeating the ABA race; sweeper reclaims stale `processing` (§16b).

### Resolved — architecture (Revision 3, carried)
No remote-orphan adoption; real remote-byte verification on every reuse; case-3
locked/proven recovery; four-concept orphan model; post-commit enqueue; distinct
`_media_v2` artifact; explicit `SourceReader` security contract; all
crash/concurrency interleavings A–U resolved.

### Resolved — product / operator (unchanged)
`service_name` census; source access; quarantine/publication; cutover gate (zero
unexplained); suspended owners; `source_removed` at delta.

### Open — before implementation
1. **Operator logistics** (not an architecture/product decision): who
   mints/holds/retires the scoped R2 token; freeze-window length;
   `STALE_THRESHOLD` and drain-timeout values; confirmation the bulk-copy
   destination is the pre-provisioned production D8N private prefix. Needed for
   L3/cutover, not for the build or L1/L2.

**No unresolved architecture or product decision remains.** ADR 0028 is
**ACCEPTED**. The Codex FINAL acceptance check named the canonical-identity
defect (now fixed in §7) as the sole remaining blocker and accepted every other
reviewed contract.

---

## Implementation readiness

**PASS 2 IMPLEMENTATION: READY.** ADR 0028 is ACCEPTED; every Codex blocker from
Rev 1 → the FINAL acceptance check is closed. The `canonical_content_type`
correction makes the migration storage key a total function of the declared
identity.

- **L1 / L2: READY AFTER IMPLEMENTATION** — the synthetic corpus and the
  `date9ja_snapshot_sanitized_media_v2` artifact must be built first (§21).
- **L3 (real R2): NOT YET READY** — blocked on operator logistics (open #1):
  scoped read-only R2 token custody, `STALE_THRESHOLD` / drain-timeout values,
  freeze-window length, bulk-copy destination confirmation.

Profile-photo capability overall remains **PARTIAL — not `PARITY_ACCEPTED`, not
production-ready, not cutover-ready.**
