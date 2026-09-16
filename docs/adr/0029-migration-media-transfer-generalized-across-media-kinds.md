# ADR 0029: Migration media byte transfer — generalized across media kinds

## Status

**ACCEPTED (2026-09-03).**

[ADR 0028](0028-migration-media-byte-transfer.md) **remains the accepted,
historical Profile Photo (image) transfer architecture** and is not rewritten.
[ADR 0027](0027-migration-media-preflight-architecture.md) (media preflight)
remains Accepted. This ADR extends the *same* proven transfer architecture to
additional media kinds (starting with Date9ja Profile Video, Wave A slice 5)
**while preserving the existing image semantics exactly**.

**Not implemented.** Acceptance clears the design for implementation (Pass 2A →
2B → 2C); it does not mean bytes have moved. No L3, no real R2, no production.

## Context

Profile Video Pass 1 (media preflight) is VERIFIED (Codex 2026-09-03, ACCEPT
WITH SMALL FIX). Planning Pass 2 (byte transfer) found that
`Migration::MediaTransfer` — the byte-transfer spine ADR 0028 governs and Codex
verified for Profile Photo — is **image-coupled** at three points:

1. `Migration::MediaTransfer.verify_bytes!` calls
   `Profiles::PhotoUpload.detect_image_type`, checks an image-only
   `ALLOWED_CONTENT_TYPES`, and runs `Media::ImageProcessor`.
2. `Migration::MediaTransfer::AdoptOrUpload#verify_remote!` repeats the same
   three image operations on every destination reuse path.
3. `Migration::MediaTransfer::CanonicalKey::EXTENSIONS` maps image types only;
   `BYTE_CEILING` is a photo constant (8 MB).

A second consumer (Profile Video, and later chat-message video) needs a
different content-type set, extension map, byte ceiling, magic-byte detector and
**structural container validator** — but the same locking, canonical identity,
adopt-or-upload state machine, deterministic recovery, and `ReferenceMap`
semantics.

## Decision

**Generalize `Migration::MediaTransfer` through a small injected media-kind
strategy. Do not create a separate `Migration::VideoMediaTransfer` framework.**

### What the strategy parameterizes (genuinely media-specific)

A `Migration::MediaTransfer::MediaKind` value object supplies **only**:

| Concern | Image (`MediaKind::Image`) | Video (`MediaKind::Video`) |
|---|---|---|
| accepted canonical content types | `image/jpeg`, `image/png`, `image/webp` | `video/mp4`, `video/quicktime` |
| canonical extension for a type | `jpg` / `png` / `webp` | `mp4` / `mov` |
| byte ceiling | `8.megabytes` (unchanged) | `Media::VideoPolicy` max byte size |
| magic-byte type detector | `Profiles::PhotoUpload.detect_image_type` | ISO-BMFF `ftyp` sniff |
| structural / content validation | `Media::ImageProcessor.call` (decode) | `Media::VideoContainerValidator.call` (box-tree walk + codec gate) **and** authoritative duration derivation + policy check (see "Duration") |
| remote re-verification body | image decode | container re-validation |

`MediaKind::Image` reproduces today's behaviour **byte-for-byte**. The public
entry points (`MediaTransfer.call`, `AdoptOrUpload.call`) take `media_kind:`
defaulting to `MediaKind::Image`, so the Profile Photo call site and its Codex-
verified semantics are unchanged.

### What the strategy MUST NOT parameterize (invariant across media kinds)

- **Locking** — Phase A no lock; short `active_storage_blobs` `FOR UPDATE` only
  inside `AdoptOrUpload`; short `MediaAttachmentRef` `FOR UPDATE` +
  `ProfileVideo`/`ProfilePhoto` transaction in Phase B; `LockGuard` /
  `RemoteIOUnderLock` unchanged and still fatal.
- **Canonical identity structure** — `CanonicalKey::Identity` keeps its seven
  fields (`version`, `source_system`, `source_blob_id`, `source_attachment_id`,
  `destination_purpose`, `destination_brand`, `canonical_content_type`);
  `canonical_string`, `object_uuid`, `KEY_NAMESPACE`, `KEY_ROOT`,
  `VERSION = "migration-media-transfer:v3"` are unchanged. Only the
  `EXTENSIONS` map gains `video/mp4 → mp4`, `video/quicktime → mov` (values
  already present in `Media::ObjectKey::EXTENSIONS`).
- **`AdoptOrUpload` state machine** — cases 1–5, the A/B/C
  (snapshot → external op outside lock → authoritative recheck) shape,
  `remote_orphan` (never adopt/overwrite/delete), `destination_collision`
  fail-closed — unchanged.
- **Deterministic recovery** — inference from canonical key + `ReferenceMap` +
  destination `processing_state`; no new transfer table; no key-prefix
  inference; `already_transferred` = complete authoritative chain — unchanged.
- **`Migration::ReferenceMap` semantics** — sole source→destination domain
  binding, immutable once bound, `DestinationTypes` allowlist — unchanged.
- **Source / destination identity rules** — source object identified by
  `(source_system, source_blob_id)`; source use by
  `(source_system, source_attachment_id)`; one destination blob per source
  attachment/use; no destination-checksum dedup — unchanged.

### Duration (media-kind-specific, but a hard Phase-A gate for video)

For video, authoritative playable duration is a **structural acceptance
property**, not descriptive metadata. `MediaKind::Video` establishes it in
**Phase A, before any destination adoption/upload**, in this order, all outside
DB locks:

```
source bytes
  → bounded 0600 local temp file (byte ceiling enforced mid-stream)
  → byte-size == MediaObjectRef.byte_size            else source_changed
  → MD5-base64 == MediaObjectRef.checksum            else source_changed
  → detected ISO-BMFF type == preflighted type       else source_changed / validation_failed
  → Media::VideoContainerValidator.call(bytes)        else validation_failed / malformed_container
  → authoritative duration (ffprobe: Media::VideoProcessor.probe)
        unreadable                                   → FAIL CLOSED: quarantined / duration_unreadable
        > Media::VideoPolicy.max_duration_seconds     → FAIL CLOSED: quarantined / duration_over_limit
  → ONLY THEN CanonicalKey.final_key + AdoptOrUpload
```

On `duration_unreadable` or `duration_over_limit` Phase A stops: **no
destination `ActiveStorage::Blob`, no `ProfileVideo`, no `ReferenceMap` binding,
no processing job.** `Media::VideoPolicy` is not modified. The
grandfather / trim-reencode / quarantine-remove product decision
(`DECISIONS.md`) stays **evidence-gated** for the founder and is not chosen
here.

`Media::ProcessProfileVideoJob` continues to independently re-derive and
re-validate duration during destination processing as **defence in depth** (it
already does: container `mvhd` gate + ffprobe gate, both against the brand
limit).

### ffprobe as the authoritative Phase-A mechanism

Evidence gathered 2026-09-03:

- `ffmpeg` / `ffprobe` 9.0.1 are on `PATH` in local dev
  (`/usr/local/bin`, built with libx264/libx265/libvpx).
- The production image installs them: `Dockerfile` line 23
  (`apt-get install … ffmpeg …`), with an explicit comment that this provides
  `ffmpeg`/`ffprobe` for `Media::VideoProcessor`.
- `Media::VideoProcessor` already shells out to `ffprobe` (`-show_format
  -show_streams`) and `ffmpeg`; it has **no fallback** — `Errno::ENOENT` becomes
  `Media::VideoProcessor::Error`, which `ProcessProfileVideoJob` treats as a
  terminal `processing_state: :failed`. Its unit tests stub
  `Media::VideoProcessor.call`, so CI does not require the binaries.
- `Media::VideoContainerValidator`'s header comment ("without shelling out to
  ffmpeg/ffprobe — neither is available in this deployment image") is **stale**
  and contradicts the Dockerfile; a one-line comment correction is folded into
  Pass 2B.

**Decision:** Phase A derives authoritative duration via a new thin
**`Media::VideoProcessor.probe(bytes)`** (ffprobe-only, extracted from the
existing private `probe!` — no transcode), returning `format.duration` (+ codec
/ container / dimensions). `Media::VideoContainerValidator`'s `mvhd` duration is
best-effort corroboration only. If `probe` raises or yields no parseable
duration → `duration_unreadable` → fail closed.

## Consequences

- One transfer spine, one lock/recovery implementation, one Codex review surface
  for both media kinds. The image path keeps its accepted ADR 0028 semantics.
- A small, real generic addition in `domains/migration/` (`MediaKind` + two
  implementations), justified by ≥ 2 consumers (Profile Video now, chat-message
  video later). Not an "empire": no business rules, no brand knowledge, no
  Date9ja schema.
- New shared `domains/media/` primitive `Media::VideoProcessor.probe` and (Pass
  2B) `Media::PlaybackDerivative.valid?` + video processing claim-token
  hardening + `Media::ProfileVideoProcessingSweeper` — reusable by HookUs /
  DateZA profile video.
- Raw-original retention for migrated video follows existing D8N behaviour
  (`ProcessProfileVideoJob` purges the raw after `ready`); recovery re-derives
  deterministic keys from `ProfileVideo#metadata`. No policy change.
- Profile Video capability stays **PARTIAL**; `PARITY_ACCEPTED` stays **NO**.
  L3 remains a separate operational/security gate.

## Implementation slices (design only — not implemented)

- **Pass 2A** — `MediaKind` strategy (image path unchanged) + `MediaKind::Video`
  + `Media::VideoProcessor.probe` + `Date9ja::Snapshot::VideoLocatorSource` +
  `Date9ja::Import::VideoTransfer` Phase A + `VideoTransferReconciliation`.
  Output: source bytes → authoritative verification → authoritative duration →
  policy acceptance → deterministic destination adoption. **No `ProfileVideo`.**
- **Pass 2B** — `Profiles::VideoUpload.build_video!` + Phase B/C (`ProfileVideo`
  create + exact `ReferenceMap` binding + processing + playback/poster +
  `Media::PlaybackDerivative.valid?`) + video processing claim-token hardening +
  `Media::ProfileVideoProcessingSweeper` + recovery/idempotency state machine.
- **Pass 2C** — deterministic synthetic video artifact (ffmpeg-generated from
  fixed inputs; see `MEDIA-TRANSFER.md`) + verifier + full isolated L2
  rehearsal + interruption/adversarial evidence.

## Related

ADR 0023 (profile video as shared Media capability), ADR 0027 (media preflight),
ADR 0028 (Profile Photo byte transfer — historical), `MEDIA-TRANSFER.md`,
`RECONCILIATION.md`, `DECISIONS.md`.
