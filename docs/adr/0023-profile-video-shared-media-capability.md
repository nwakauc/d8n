# ADR 0023: Profile video as a shared D8N Media capability

## Status

**Accepted** (2026-09-02, independent review). Product owner has decided Date9ja
profile video is retained parity. Extends ADR 0011 (private media / verification
boundary). Implemented as a first bounded slice (owner CRUD + processing +
Date9ja config); public-profile delivery wiring and the legacy importer are
follow-up slices.

Review amendments applied:

- **Container support is MP4 + QuickTime (.mov) only.** WEBM/Matroska is
  excluded until `Media::VideoContainerValidator` can structurally walk it —
  a MIME/signature check is not structural validation, and D8N does not ship
  pretend validation for format breadth. iOS records .mov/H.264 and Android
  records .mp4/H.264, so this covers effectively all phone-recorded intro
  videos.
- **Structural validation + duration enforcement run in the async job**, against
  the whole downloaded object — matching `Messaging::MessageAttachmentUpload`.
  A bounded upload-time head cannot contain a non-faststart MP4's trailing
  `moov` box, so validating at attach would reject legitimate uploads. Attach
  does a cheap `ftyp`-at-offset-4 sniff + real-size bound only; a file that
  fails the full walk, codec gate, or the brand duration limit ends at
  `processing_state: failed`.

## Context

Date9ja ships a profile-introduction video: `ProfileVideo` (one per user,
`has_one_attached :video`), MP4/MOV/WEBM, ≤ 50 MB, ≤ 60 s, admin-reviewed
(`moderation_status` pending/approved/rejected), CRUD at
`/api/v1/profile/video`. It is distinct from the *mandatory RealMe verification
video* (that belongs to Verification — ADR 0024).

D8N already owns every primitive this needs:

- `Media::ObjectKey` — server-allocated PII-free R2 keys (already reserves a
  `videos/<uuid>/` shape and `playback.mp4` / `poster.jpg` basenames)
- `Media::VideoContainerValidator` — ISO-BMFF structural safety check
- `Media::VideoProcessor` — ffmpeg/ffprobe H.264/AAC playback rendition + poster,
  no-transcode-when-already-compatible (built for chat video attachments)
- `Media::StorageResolver` — per-brand private service selection
- `Media::PhotoPolicy` — per-brand initial visibility from the brand contract
- `Profiles::PhotoUpload` — control-plane/data-plane direct-to-R2 upload with
  server object allocation + real-object verification
- `Trust::ModerateProfilePhoto` — brand-scoped audited approve/reject

The trap is a `domains/date9ja/profile_video` fork or a `ProfileVideo` that
re-implements the photo pipeline. Neither is acceptable.

## Decision

### Profile video is a D8N Media capability, brand-enabled

New capability keys under the existing `media` namespace, mirroring
`media.profile_photo.*`:

```
media.profile_video.upload
media.profile_video.attach
media.profile_video.process
media.profile_video.deliver
media.profile_video.delete
media.profile_video.moderation
```

Plus a D8N Profile capability `profile.video` (the placement/CRUD surface,
mirroring `profile.photos`). All `available` — they map to real classes.

A brand enables profile video through its contract. Date9ja enables it; HookUs
and DateZA do not (no regression — they never had it). `media.video` stays
`planned` and is unrelated (it was a placeholder for generic video).

### Storage model follows ADR 0011 exactly

`ProfileVideo` is the **brand-profile-owned placement** (one per profile,
ordering is trivial — there is only one — but status, visibility, processing
state, and soft deletion live here). It carries:

- `video` attachment — the untrusted raw upload. Private, owner-only, **purged**
  once the safe playback rendition exists.
- `playback` attachment — D8N-owned H.264/AAC MP4 rendition (`Media::VideoProcessor`).
  The only representation delivered to other users.
- `poster` attachment — D8N-generated JPEG frame (re-encoded through
  `Media::ImageProcessor`, EXIF-stripped).
- `public_id` (opaque UUID), `status` (pending_review/approved/rejected),
  `visibility` (hidden/visible), `processing_state` (pending/processing/ready/failed),
  `duration_seconds`, `deleted_at` + deletion audit columns.

No separate Media asset table is introduced for video in this slice (ADR 0011's
Media-owned asset record remains a future consolidation for photos + video
together; introducing it now for video alone would fork the pattern). The raw
blob + derivative blobs on `ProfileVideo` are the storage records, exactly as
`ProfilePhoto` does it today.

### Uploads enter quarantine

`Profiles::VideoUpload` mirrors `Profiles::PhotoUpload` /
`Messaging::MessageAttachmentUpload`:

1. `create_intent` — validate declared content-type (`video/mp4`,
   `video/quicktime`), byte size (≤ brand max), checksum; allocate a
   `Media::ObjectKey.profile_video_original` key; return a short-lived presigned
   PUT. The client uploads bytes straight to private R2.
2. `attach!` — confirm the real object exists, is an ISO-BMFF container
   (`ftyp` box at offset 4), and is within the size limit; reconcile the blob;
   create the `pending_review` + policy-initial-visibility `ProfileVideo` with
   the raw blob (one per profile, DB-enforced); enqueue
   `Media::ProcessProfileVideoJob`.
3. `Media::ProcessProfileVideoJob` — download the whole object; run the full
   `Media::VideoContainerValidator` box-tree walk + codec gate; enforce the
   brand duration limit (container `mvhd`, then authoritative ffprobe);
   `Media::VideoProcessor` produces the playback rendition + poster; attach
   both; mark `processing: ready`; `purge_later` the raw. Any validation,
   codec, or duration failure is a terminal `processing_state: failed`.
   Idempotent, deletion-tolerant, transient-retry.

Duration is enforced from the **validated container / ffprobe result**, not the
client-declared value (Date9ja trusted the client field; D8N does not).

### Delivery is authorized and revocable

Same two paths as photos:

- Owner preview — rechecks brand/user/membership/profile lifecycle/undeleted
  video; may see poster + playback (never the raw).
- Public — only a `deliverable?` video (safe playback ready, visible, moderation
  policy eligible) attached to an otherwise-authorized public profile surface.
  Signed short-lived URLs for poster + playback; never bucket keys.
- Soft delete removes it from every surface immediately and invalidates new
  delivery authorization; storage purge runs async and idempotently.

### Brand policy

`BrandContract::MediaConfiguration` gains an optional `video:` sub-config
(`VideoConfiguration`: `initial_visibility`, `max_duration_seconds`,
`max_byte_size`). Absent → the brand does not enable profile video. Date9ja:
`initial_visibility: :immediate` (legacy behaviour — a pending video is
watchable; a rejected one is excluded), `max_duration_seconds: 60`,
`max_byte_size: 50.megabytes`. `Media::VideoPolicy` reads it, exactly as
`Media::PhotoPolicy` reads photo config; a brand with no video config fails
closed (no capability, no delivery).

### Moderation

Reuse the photo moderation pattern: a `Trust::ModerateProfileVideo` (or an
extension of `ModerateProfilePhoto` to a polymorphic target) records a
brand-scoped admin approve/reject audited via `SecurityEvent`. Rejected video is
never deliverable regardless of visibility. This slice ships the model states +
policy; the admin action reuses the existing enforcement surface.

### Migration parity

The importer (later slice, ADR 0022 mechanism) maps legacy `profile_videos` →
`ProfileVideo` via `LegacyReference`, preserving `moderation_status`,
`duration_seconds`, review metadata, and re-ingesting the raw object through the
D8N pipeline (or carrying the already-safe rendition if the source object is
trusted). Legacy `reviewed_by` (a Date9ja `User`) maps to a D8N admin actor or
is recorded as historical metadata.

## Consequences

- Profile video is available to any future brand by adding `video:` to its
  contract — no new controller, table, or pipeline.
- The chat-video and profile-video pipelines share `VideoProcessor` /
  `VideoContainerValidator` / `ObjectKey`; a fix to container safety fixes both.
- `BrandContract::MediaConfiguration` grows one optional field; existing HookUs /
  DateZA contracts and tests are unaffected (field is absent → no video).
- A future Media-owned asset record (ADR 0011) can absorb both `ProfilePhoto`
  and `ProfileVideo` blobs without another migration of product semantics.

## Alternatives considered

- **`domains/date9ja/profile_video`.** Rejected — backend fork.
- **Reuse `MessageAttachment` for profile video.** Rejected — different owner
  (profile placement vs conversation message), audience, and lifecycle.
- **Add a generic `media.video` capability and hang profile video off it.**
  Rejected — profile video is a Profile placement concern; `media.video` stays a
  future generic primitive.
- **Trust the client `duration_seconds` (as Date9ja does).** Rejected — enforce
  from the validated container.
