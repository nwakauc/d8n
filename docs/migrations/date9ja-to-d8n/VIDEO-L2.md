# Date9ja → D8N — Profile Video L2 synthetic rehearsal evidence (ADR 0029 Pass 2C)

**Status: IMPLEMENTED / SELF_VERIFIED + OPERATOR_L2_COMPLETE (2026-09-04).
Independent CODE review ACCEPTED (Codex, with doc fix). Operator L2 evidence
(§12) NOT yet independently reviewed. NOT `VERIFIED`. Profile Video capability:
PARTIAL. `PARITY_ACCEPTED`: NO.**

Architecture authority: [ADR 0029](../../adr/0029-migration-media-transfer-generalized-across-media-kinds.md)
(+ ADR 0027 preflight, ADR 0028 photo byte transfer). Pass 2A / 2B evidence:
`STATUS.md`, `RECONCILIATION.md`, `MEDIA-TRANSFER.md`.

---

## NON-NEGOTIABLE EVIDENCE RULE

The sanitized snapshot holds **metadata** for the legacy `ProfileVideo` records
but **not** their media bodies. Keep these separate and never merge them:

| Concept | Statement |
|---|---|
| **SOURCE CENSUS FACT** | 35 legacy `ProfileVideo` records exist (26 `video/mp4` + 9 `video/quicktime`, per `RECONCILIATION.md` "Profile-video MEDIA PREFLIGHT"). |
| **SYNTHETIC L2 FACT** | 35 deterministic ffmpeg-rendered synthetic bodies were constructed for engineering rehearsal, mirroring that metadata topology. |
| **REAL-MEDIA FACT** | Authoritative duration / codec / container of the **real** 35 source videos remains **UNKNOWN** until an authorized real-media rehearsal. Nothing here changes that. |

This corpus proves the **migration machinery** against the real metadata shape.
It does **not** prove the real videos are ≤ 60 s, are H.264, or are any
container.

---

## 1. Synthetic artifact

| | |
|---|---|
| Synthetic DB artifact | `date9ja_snapshot_sanitized_media_v3` (disposable; operator-derived copy of the parent) |
| Parent sanitized artifact | `date9ja_snapshot_sanitized` (verified, PII-stripped, **never modified**) |
| Generator | `Date9ja::Snapshot::SyntheticVideoMedia` + `SyntheticVideoMedia::Generator` (`GENERATOR_VERSION = "date9ja-synthetic-video-media-v1"`) |
| Verifier | `Date9ja::Snapshot::SyntheticVideoMedia::Verifier` (independent — re-renders, walks containers, runs ffprobe, DB drift) |
| Rehearsal transport | `Date9ja::Storage::LocalCorpusReader` + `Date9ja::Storage::SafeObjectKey` (unchanged; shared with the photo L2) |
| Rake tasks | `date9ja:build_video_media_v3`, `date9ja:verify_video_media_v3`, `date9ja:transfer_videos` (stage `:domain`), `date9ja:transfer_videos_phase_a` (stage `:adopt`) |

**What the generator changes on `media_v3` vs its parent:** ONLY `byte_size` and
`checksum` on the 35 authorized `ProfileVideo` `video` blob rows. Everything else
— video / attachment / blob / owner ids, moderation, storage key, `service_name`,
`content_type`, and every non-video blob row — is preserved byte-for-byte
(verifier checks 09–12, 09b, 17).

---

## 2. Corpus

| Fact | Value |
|---|---|
| Corpus count | **35** (derived from execution — `L2: 35-record census` test) |
| MP4 / MOV distribution | **26 `video/mp4` + 9 `video/quicktime`** (mirrors the census metadata) |
| Codec distribution | **35 × H.264 (`avc1`)** on the happy path. HEVC is **not** in the census — no HEVC in the happy-path corpus. `Media::VideoContainerValidator` still accepts `hvc1`/`hev1`; a compatibility fixture is out of scope for 2C. |
| Synthetic duration design | Deterministic per-object duration in **2–8 s** (`SyntheticVideoMedia::HAPPY_PATH_DURATION_RANGE`), always ≤ the Date9ja 60 s limit, so the whole pipeline runs. **This does NOT imply the real videos are ≤ 60 s.** |
| Per-object variation | duration / dimensions (176×144 … 320×240) / frame rate (10/12/15) / GOP / tone frequency are a pure function of `SHA256(generator_version \| seed \| source_blob_id \| canonical_content_type)`. |
| Byte ceiling | `Media::VideoPolicy::DEFAULT_MAX_BYTE_SIZE` (50 MB); actual bodies ≈ 100–400 KB. |
| Encoding | ffmpeg argv-array (never a shell string), `-fflags +bitexact`, `-flags:v/-flags:a +bitexact`, `-x264-params bitexact=1`, `-map_metadata -1`, `-movflags +faststart`, `-preset ultrafast`, `yuv420p`, AAC 64 k. |

### Generator determinism

Two clean generations into separate directories produce a **byte-identical**
corpus and an **identical manifest fingerprint** (test:
`L2: fixed census-shaped corpus has a stable, reproducible fingerprint`, and the
per-run second-generation check inside the 35-record test).

**Documented constraint:** byte-identity holds for a **fixed ffmpeg/libx264
build** (verified with ffmpeg 9.0.1 in this environment). Cross-environment
byte-identity is pinned to the encoder build; the verifier mitigates this by
**re-rendering every body in the target environment and comparing** (check 13,
15) rather than trusting a stored fingerprint alone.

### Corpus fingerprint

`SyntheticVideoMedia::Generator.fingerprint_of` = `SHA256` over the reproducible
manifest slice (`generator_version`, `seed`, `object_count`, `objects`), i.e. it
changes if any body's identity mapping, byte size, checksum, container,
dimensions or expected duration changes.

- **Documentable machinery fingerprint** (fixed seed `date9ja-video-media-v3-doc-2026-09-04`,
  fixed census-shaped blob ids 1…35):

  ```
  5fbcc9dac1d7334859c5753b3c5b347589898af0ce3302e15cc117366433c378
  ```

  Regression-locked in `VideoL2RehearsalTest::DOC_FINGERPRINT`; reproduced across
  two clean generations.

- The **canonical fingerprint for the real `date9ja_snapshot_sanitized_media_v3`
  artifact** (real 35 source blob ids, `DEFAULT_SEED`) is produced by the
  operator `date9ja:build_video_media_v3` run and recorded there — it is not
  derivable here without the real blob ids.

---

## 3. Manifest

`manifest.json` per object (PII-free — no name/email/phone/bio/URL/credential):
`source_blob_id`, `source_key`, `service_name`, `canonical_content_type`,
`byte_size` (JSON integer), `checksum` (MD5-base64), `container`,
`expected_duration_seconds`, `width`, `height`, `frame_rate`, `video_codec`,
`generator_version`, `seed`, `deterministic_identity`. Plus artifact/parent
names, `evidence_rule`, `lineage_note`, `happy_path_max_duration_seconds`, and a
`generated_at_utc` (excluded from the fingerprint).

---

## 4. Independent corpus verifier — checks

| # | Check |
|---|---|
| 01 / 02 | every required `video` attachment resolves to a manifest object / no unexpected objects |
| 03 / 04 | every object present, a regular file (no symlink), bounded (< 50 MB) |
| 05 / 06 | stored bytes match the manifest `checksum` / `byte_size` exactly |
| 13 | every stored body is a **byte-exact re-render** of the checked-in generator (no production media bytes) |
| 15 | generator is deterministic (second corpus, or in-memory re-render) |
| 18 | `Migration::MediaTransfer::MediaKind::Video.detect_type` (ISO-BMFF `ftyp`) matches the recorded canonical type |
| 19 | `Media::VideoContainerValidator` structurally validates the container + codec |
| 20 / 21 | `Media::VideoProcessor.probe` (ffprobe) succeeds / yields a **positive** duration |
| 22 | ffprobe duration is within ±0.75 s of the manifest `expected_duration_seconds` |
| 23 | **happy-path** duration ≤ 60 s (brand limit) |
| 09 / 10 / 11 / 12 / 09b | no source identity / attachment-blob graph / ownership / moderation drift vs the parent; only integrity metadata rewritten |
| 16 | every manifest field binds, field-for-field, to the **authoritative** `media_v3` blob row (the `ProfileVideo` attachment graph defines the authorized set, not the manifest); exact integer `byte_size` typing; no duplicate / unexpected `source_blob_id`; `manifest count == authorized count` |
| 17 | schema-driven full-`active_storage_blobs` proof: only `byte_size`/`checksum` changed, only on the 35 authorized rows; NULL-safe, type-preserving; 0 inserted / 0 deleted |
| **24** | **every manifest `source_key` satisfies the shared opaque-object-key grammar (no absolute / `..` / backslash / `%` / whitespace) and does not resolve through a symlink out of the corpus root — checked BEFORE any file read (`Date9ja::Storage::SafeObjectKey`; review Finding 3)** |
| **27** | **full `active_storage_attachments` table byte-identical to the parent — every column, every row, NULL-safe; 0 inserted / deleted / changed (review Finding 2)** |
| **28** | **row counts for a fixed allowlist of unrelated tables (users, profiles, brand_memberships, profile_videos, photos, active_storage_variant_records, likes, matches, messages, blocks, reports, profile_views, credentials) match the parent (review Finding 2)** |
| 14 | no production endpoint / credential token in the manifest or the media bytes |

What the checks prove, precisely:

- **`active_storage_blobs` (check 17):** content-identical to the parent
  artifact except `byte_size` / `checksum` on the 35 authorized `ProfileVideo`
  blob rows; NULL-safe, type-preserving; 0 rows inserted / deleted; no other
  column on any row changed.
- **`active_storage_attachments` (check 27):** the **complete** table is
  content-identical to the parent — every column, every row, NULL-safe; 0
  inserted / deleted / changed.
- **Other unrelated tables (check 28):** **row counts** are proven identical to
  the parent. Check 28 does **not** compare row contents. Full content
  immutability of these tables rests on this row-count equality **plus** code
  inspection of `SyntheticVideoMedia::Generator#patch_metadata!`, whose only DML
  is one `UPDATE active_storage_blobs SET byte_size = <int>, checksum = <quoted>`
  per object inside a transaction — there is no other write statement anywhere
  in `SyntheticVideoMedia`.

Generator ↔ verifier do **not** share a "generate the expected answer / compare
to self" path: the verifier re-derives bytes from the checked-in render function
and inspects them through the **shared production runtime**
(`VideoContainerValidator`, `VideoProcessor.probe`, `MediaKind::Video`).

L1 coverage: `test/domains/date9ja/snapshot/synthetic_video_media_test.rb`
(26 runs — generator determinism / path safety / patch scope; verifier pass +
each failure mode incl. the check-24 path-safety adversarials and check-27/28
drift).

---

## 5. Full isolated rehearsal — `L2: 35-record census -> Pass 1 -> 2A -> 2B -> verify -> rerun`

Self-contained: builds the 35-record source topology (35 owners, one video each,
moderation cycled pending/approved/rejected), generates the corpus, drives the
whole pipeline. All counts **derived from execution** (569 assertions, 0
failures, ~53 s).

### Pass 1 (preflight)

| Measure | Result |
|---|---|
| `videos_considered` / `balanced` | 35 / true |
| `preflighted` | 35 |
| `media_object_refs_created` / `media_attachment_refs_created` | 35 / 35 |
| moderation pending + approved + rejected | 35 |
| `ProfileVideo` / Active Storage rows | 0 / 0 |

### Pass 2A (`stage: :adopt`) — no domain artifacts

| Measure | Result |
|---|---|
| `videos_considered` / `balanced` | 35 / true |
| `destination_adopted` | 35 |
| `duration_derived` / `duration_within_limit` | 35 / 35 |
| `content_type_mp4` / `content_type_quicktime` | 26 / 9 |
| `quarantined` | 0 |
| `ProfileVideo` created | **0** |
| destination original blobs at `migrations/media/v3/date9ja/profile_video_original/…` | 35 |

### Pass 2B (`stage: :domain`) — interruption window A (adopted, no ProfileVideo)

| Measure | Result |
|---|---|
| `videos_considered` / `balanced` | 35 / true |
| `ready` | **35** |
| `profile_videos_created` / `reference_map_bindings_created` | 35 / 35 |
| `processing_attempts` / `processing_succeeded` | 35 / 35 |
| `playback_validated` / `poster_validated` | 35 / 35 |
| `originals_purged` | 35 |
| `stage` | `"domain"` |
| `transferred` disposition present? | **no** |

### Independent destination verifier (not reconciliation)

For all 35: exactly one `ProfileVideo` per source video; `ReferenceMap` resolves
exactly once (`source_entity: "profile_video"`); `brand_id == date9ja` (no
cross-brand binding); exact owner `profile_id` / `user_id`; `processing_ready`;
`playback` + `poster` attached at the deterministic
`Media::ObjectKey.profile_video_{playback,poster}` keys; **raw purged**;
`Migration::MediaTransfer.valid_accepted_playback?` (bounded remote re-read of
both derivatives) true; moderation preserved (pending→visible, approved→visible,
rejected→hidden); 0 unexpected `ProfileVideo` rows; 0 cross-brand rows.

### Rerun / idempotency

Second `stage: :domain` run: `already_ready` 35, `ready` 0,
`processing_succeeded` 0; `ProfileVideo` / `Blob` / `LegacyReference` counts
**unchanged**; `ProfileVideo` `video` (raw) attachments **still 0** — the purged
originals are not recreated.

---

## 6. Interruption / recovery rehearsal

| Window | Test | Result |
|---|---|---|
| A — adopted, no ProfileVideo | (the 35-record run) | `stage: :domain` RESOLVE `:absent` → Phase A reuse → Phase B build → ready |
| **B, C (attach / bind)** | — | **structurally impossible** — `build_video!` + `ReferenceMap.bind!` are one Phase-B transaction (savepoint-nested profile lock rolls back with it) |
| B/E — crash during processing | `L2 interruption B/E` | bound + not-ready + raw present → restart RESOLVE `:resume_processing` → job → ready; `ProfileVideo.count` unchanged (resumed, not rebuilt) |
| C — stale processing claim | `L2 interruption C` | bound, `processing` + stale token, raw present → `processing_stale_reclaims` 1, job CLAIM reclaims → ready |
| F/G — ready, raw purged, restart | `L2 interruption F/G` | RESOLVE `:complete` (metadata-key path) → `already_ready`; raw **not** recreated |

### Process-kill boundary evidence

**A true SIGKILL of a forked processing worker is NOT safely automatable here:**
minitest wraps each test in a rolled-back transaction, so a forked child shares
the parent's uncommitted transactional connection and a kill mid-savepoint
corrupts the shared fixture state.

The bounded alternative (`L2 process-kill boundary` test): reproduce the **exact
durable state** a SIGKILLed worker leaves — `processing_state = processing` +
`processing_claim_token` + `processing_started_at`, with **no** FINALIZE /
FAILURE / `ensure` having run — then prove deterministic recovery: the operator
restart re-runs the migration, the stale claim is reclaimed (new token), and the
video reaches `ready` with validated playback + poster and the raw purged
(`processing_claim_token` cleared, ≠ the killed token). The ABA guarantee (a
foreign token cannot finalize / mutate state) is proven separately in
`Media::ProcessProfileVideoJobClaimTest`.

**Done in the operator L2 run (§12, step 9):** a real forked-worker `SIGKILL`
against a `date9ja_snapshot_sanitized_media_v3` restore (a non-transactional
throwaway D8N DB) — worker CLAIMed, `kill -9` (shell `wait` rc 137), durable
state left `processing` + killed token + unchanged `processing_started_at`, no
FINALIZE/FAILURE; operator restart reclaimed the stale claim (new token) and the
video reached validated READY with the raw purged; the killed token could not
own the claim (ABA).

---

## 7. Adversarial suite (separate from the 35-record census)

| Fixture | Result |
|---|---|
| Genuine H.264 MP4, duration 64 s (`SyntheticVideoMedia.render_over_limit`) | `quarantined` / `duration_over_limit`; **0** `ProfileVideo`, **0** binding |
| Valid container, no ffprobe duration (`build_test_mp4_bytes`) | `quarantined` / `duration_unreadable`; **0** domain artifacts |
| Truncated container (`render`d body minus 80 bytes) | `validation_failed` / `malformed_container` |
| Image bytes declared `video/mp4` | `validation_failed` / `not_a_video` |
| Checksum drift | `source_changed` / `source_checksum_mismatch` |
| Byte-size drift | `source_changed` / `source_size_mismatch` |
| Content-type drift (declared mp4, actual mov) | `source_changed` / `content_type_drift` |
| Destination collision (adopted object overwritten, rerun) | `binding_conflict` / `destination_collision`, fail closed |
| Remote orphan (object at the deterministic key, no blob row) | `binding_conflict` / `remote_orphan`; object never adopted; **0** `ProfileVideo` |
| Invalid playback rendition (job "succeeds", writes a non-container) | fail closed (`processing_failed` after retry exhaustion, or `derivative_validation_failed`); **never `ready`**, raw not purged — the job's `finalize!` validates the candidate before attaching (review Finding 1) |
| Tampered poster (non-decodable / non-JPEG) | fail closed; **never `ready`** |
| **Existing deterministic-key playback blob with tampered remote bytes** | `finalize!` candidate validation fails → never attached, never ready, raw not purged (review Finding 1) |
| **Existing playback blob: checksum/size mismatch, wrong container, or wrong service** | fail closed (Finding 1) |
| **A validated candidate swapped before attach (ABA)** | fingerprint recheck under the lock rejects it → `derivative_conflict` terminal, never ready (Finding 1) |
| **Existing CORRECT deterministic-key derivatives** | independently re-validated → safely reused, no duplicate blob (Finding 1) |

None of these are mixed into the 35-record census counts. The
existing-blob-reuse cases are covered by
`test/domains/media/process_profile_video_job_derivative_integrity_test.rb`
(each FAILS on the pre-review implementation).

---

## 8. PD-2

**PD-2 remains OPEN / evidence-gated.** What should happen to **real** legacy
videos whose authoritative duration exceeds 60 s — (A) grandfather, (B)
trim/re-encode, (C) quarantine/remove — is **not** chosen here.

**Real over-limit count = UNKNOWN.** The happy-path synthetic corpus is
deliberately all ≤ 60 s and says nothing about the real distribution. The
adversarial > 60 s fixture only proves the current fail-closed policy works
(`quarantined` / `duration_over_limit`, no destination adoption or domain
artifacts).

---

## 9. Real-media limitations

- No real Date9ja R2, no production credentials, no production DB, no L3, no
  cutover.
- The corpus bodies are engineering rehearsal material — not the users' videos.
- Real duration / codec / container of the 35 source videos: **UNKNOWN**.
- Cross-environment byte-identity of the ffmpeg renders is pinned to the
  encoder build (mitigated by verifier re-render, §2).
- The full operator L2 (restore `date9ja_snapshot_sanitized_media_v3`, run the
  rake pipeline against all 35 real blob ids, real forked-worker SIGKILL) is the
  remaining step — same builder/operator split as the Profile Photo L2, which
  was completed and Codex-reviewed.

---

## 10. Feature-boundary review — Codex BLOCKED — fixes applied (2026-09-04)

Codex reviewed the completed 2A→2B→2C feature. PASSED: D8N/shared architecture,
Profile Photo regression, 2A validation/duration gate, 2B domain binding,
brand/tenant isolation, the DB migration, privacy. **BLOCKED** on three findings,
now fixed without redesigning the feature. Full detail in `STATUS.md`
"Feature-boundary review — fixes applied"; summary:

- **Finding 1 (BLOCKER) — derivative reuse could mark invalid media ready.**
  `Media::ProcessProfileVideoJob#finalize!` now validates every candidate
  playback/poster blob's **actual remote bytes** (new
  `Media::PlaybackDerivative.playback_blob_valid?` / `poster_blob_valid?` —
  exact key + service + content type + positive size + remote object exists +
  byte-size match + checksum/body-identity match + real container walk / image
  decode) **outside all DB locks**, before attaching, and re-proves the exact
  validated blob rows are still at the keys under the finalize lock (ABA guard).
  A validation-failing candidate is never attached, never marks ready, never
  purges the raw. Regression:
  `test/domains/media/process_profile_video_job_derivative_integrity_test.rb`.
- **Finding 4 — `deliverable?`.** `ProfileVideo#safe_derivative_ready?` now
  requires both `playback` and `poster` attached, so READY is never stronger
  than public deliverability.
- **Finding 2 — L2 DB drift.** Verifier checks **27** (full
  `active_storage_attachments` byte-identical) + **28** (unrelated table row
  counts) added — see §4.
- **Finding 3 — verifier path safety.** `Verifier#object_path` resolves every
  manifest `source_key` through `Date9ja::Storage::SafeObjectKey`; check **24**
  validates all keys before any file read — see §4.

**Retest (post-fix):** 546 runs / 2516 assertions / 0 failures across
`test/domains/{date9ja,migration,media,profiles}` + `test/jobs/media` +
profile-video/photo/message-attachment models + video controller (incl. the full
35-record L2 rehearsal). Profile Photo + photo-L2 regression 125 / 0. RuboCop /
Zeitwerk / Brakeman clean; `git diff --check` clean. `DOC_FINGERPRINT` unchanged
(generator/manifest untouched).

## 11. Lifecycle

| Slice | Lifecycle |
|---|---|
| Pass 2A | IMPLEMENTED / SELF_VERIFIED |
| Pass 2B | IMPLEMENTED / SELF_VERIFIED |
| Pass 2C (this) | IMPLEMENTED / SELF_VERIFIED |
| Operator L2 rehearsal (§12) | **OPERATOR_L2_COMPLETE / READY_FOR_FINAL_INDEPENDENT_REVIEW** |
| Profile Video capability overall | **PARTIAL** |
| `PARITY_ACCEPTED` | **NO** |

Independent CODE review is ACCEPTED (Codex). The operator L2 evidence below is
the builder/operator maximum; the final `VERIFIED` transition requires
independent review of this operator evidence.

---

## 12. Operator L2 rehearsal — RUN 2026-09-04 (committed `47362bb`)

Sanitized / synthetic L2. **No production, no real R2, no real user video
bytes, no L3, no cutover.** Isolated PG17 snapshot cluster `127.0.0.1:55432`;
throwaway D8N DB `d8n_date9ja_rehearsal_opl2_20260904` (`RAILS_ENV=test`,
ActiveStorage Disk service). Working tree clean before and after (only this
file + `RECONCILIATION.md` + `STATUS.md` changed).

### Artifact + corpus

| | |
|---|---|
| Commit tested | `47362bb` "feat: implement Date9ja profile video migration" |
| Parent artifact | `date9ja_snapshot_sanitized` (never modified) |
| media_v3 artifact | `date9ja_snapshot_sanitized_media_v3` (`CREATE DATABASE … TEMPLATE date9ja_snapshot_sanitized`) |
| Corpus / manifest | scratch `opL2/corpus1/` — `manifest.json` + `manifest.fingerprint` + `objects/` |
| Corpus count | **35** (26 `video/mp4` + 9 `video/quicktime`) — matches the source census |
| Corpus bytes | 7,283,823 |
| Patched source blob rows | **35** (`byte_size` + `checksum` only) |
| Manifest fingerprint (real blob ids, `DEFAULT_SEED`) | `e134ed15b8327617929831569b633cc4b03dc0de3bb0b9b12f0101f1eb29e503` |
| Determinism | second independent build into `corpus2/` → object bodies + fingerprint **byte-identical**; only `generated_at_utc` differs (excluded from the fingerprint by design) |

### `date9ja:verify_video_media_v3` — all checks `ok: true`

`object_count 35`; checks 01/02 (attachment↔manifest bijection), 24 (manifest
keys safe — `bad_grammar=0 path_escapes=0`, before any read), 03/04/05/06
(present / regular file / bounded / checksum / byte_size), 13 (byte-exact
re-render — no production bytes), 18 (ISO-BMFF type), 19 (container + codec),
20/21/22/23 (ffprobe succeeds / positive / ±0.75 s of expected / ≤ 60 s),
09/10/11/12/09b (no identity / attachment-graph / ownership / moderation drift),
16 (`authorized=35 manifest=35 field_mismatch={}`), 17
(`rows_v3=443 rows_parent=443 inserted=0 deleted=0 authorized_changed=35
wrong_column_change=0 non_video_change=0`), 27
(`active_storage_attachments` `rows_v3=428 rows_parent=428 inserted=0 deleted=0
changed=0`), 28 (`checked=11` unrelated tables, `mismatches=` none — **row
counts only**, per §4), 14 (no endpoint/credential), 15 (`fingerprint_match=true
bytes_match=true`). → `MEDIA_V3 VIDEO ARTIFACT: VERIFIED FOR L2`.

### Fresh destination + Pass 1

| Step | Result |
|---|---|
| `db:schema:load` + `date9ja` brand | baseline 0 users / 0 ProfileVideo / 0 blobs |
| `date9ja:import_identity` | 288 considered → **280 imported / 8 skipped (`source_soft_deleted`) / 0 failed** |
| `date9ja:preflight_videos` | 35 considered / `balanced` true / **35 preflighted** / 35 `MediaObjectRef` + 35 `MediaAttachmentRef` / moderation **35 pending, 0 approved, 0 rejected** (real sanitized shape) / **`duration_missing` 35 / 35** / `owner_not_imported` 0 |

### Pass 2A — `date9ja:transfer_videos_phase_a` (`stage: :adopt`)

35 `destination_adopted` · `duration_derived` 35 · `duration_within_limit` 35 ·
`duration_over_limit` 0 · `duration_unreadable` 0 · `container_invalid` 0 ·
`content_type_mp4` 26 / `content_type_quicktime` 9 · `quarantined` 0 ·
`source_changed` 0.
Independent check: `profile_videos` **0**, `ProfileVideo` `video`/playback/poster
attachments **0**, `profile_video` `LegacyReference` **0**, 35 destination
original blobs under
`migrations/media/v3/date9ja/profile_video_original/<uuidv5>/original.{mp4,mov}`.
**Phase A created no domain completion.**

### Pass 2B — `date9ja:transfer_videos` (`stage: :domain`)

`ready` **35** · `profile_videos_created` 35 · `reference_map_bindings_created`
35 · `processing_attempts` 35 · `processing_succeeded` 35 · `playback_validated`
35 · `poster_validated` 35 · `originals_purged` 35 · **no `transferred`
disposition**.

Independent destination verification (not the migration's own reconciliation):

| Property | Result |
|---|---|
| `ProfileVideo` rows | 35, all `processing_ready`, all `deliverable?` |
| Owner | exact imported `profile_id` / `user_id`; all `profiles.brand_id = date9ja`; **0 cross-brand** |
| `LegacyReference` (`source_entity: "profile_video"`) | 35, all `resolvable?`, all `brand_id = date9ja` |
| playback / poster attachments | 35 / 35; **raw `video` attachments 0**; 35 distinct playback keys, 35 distinct poster keys (no dup blob) |
| Independent derivative re-read (`Media::PlaybackDerivative.playback_valid?` / `poster_valid?` — bounded remote download + byte-size + MD5 + container walk / JPEG decode) | **35 / 35 playback, 35 / 35 poster** |
| Moderation | 35 `pending_review` → `visible` (pending maps to visible) |
| Claim tokens after ready | all cleared |

### Raw-original purge — behaviour note (NOT a defect)

`Media::ProcessProfileVideoJob` marks READY then calls the standard async
`video.video.purge_later`. The raw **attachment** row is removed synchronously
(`ProfileVideo#video.attached?` → false, deliverability unaffected); the raw
**blob row + Disk object** are deleted by the enqueued `ActiveStorage::PurgeJob`,
which runs under a live queue worker. In this `RAILS_ENV=test` rehearsal the
`TestAdapter` does not auto-run that job, so 35 detached raw blobs + files linger
until drained. Draining `ActiveStorage::PurgeJob` explicitly (exactly what a
production worker does): blobs 105 → **70** (35 playback + 35 poster), **0
orphan blobs / 0 orphan files**, all 35 playback + 35 poster still independently
valid, originals **not recreated**. The `originals_purged` reconciliation key
therefore means "raw purge scheduled + attachment detached", not "blob GC'd
in-process".

### Rerun / idempotency

- `date9ja:transfer_videos` rerun (before purge drain): `already_ready` 35,
  `ready` 0, `profile_videos_created` 0, bindings 0, `processing_attempts` 0,
  blob / attachment / `LegacyReference` counts unchanged.
- `date9ja:transfer_videos` rerun (after full purge drain): `already_ready` 35,
  blobs stay 70, **0 orphan blobs**, raw originals **not recreated**, 35
  `deliverable?`.
- **Idempotency wart (minor):** re-running `date9ja:transfer_videos_phase_a`
  standalone *after* a completed domain migration + purge re-uploads the 35 raw
  original blobs (they are gone, and Phase A's contract is "the adopted original
  exists"). It creates **no** duplicate `ProfileVideo` / binding / attachment /
  derivative. The documented operator sequence is `phase_a → domain → domain`;
  the canonical rerun path (`transfer_videos`) is fully clean.

### Step 9 — real forked-worker SIGKILL

One `ProfileVideo` reset to durable pre-processing state (bound, raw attached,
`processing_state: pending`, no claim). A **separate OS process**
(`bin/rails runner`) ran `Media::ProcessProfileVideoJob.perform_now`; a
test-only prepend widened the WORK window (no implementation code changed).

| Step | Evidence |
|---|---|
| A. pre-kill | `processing_state=0` (pending), token `NULL`, `started_at NULL`, raw attached |
| B/C. worker CLAIMed | after ~1.8 s: `processing_state=1`, `processing_claim_token = 6893cf7a-f6e7-46d6-b56d-6c7bc7d27fec` (the killed token) |
| D. kill | `kill -9 <worker pid>` |
| E. termination | shell `wait` rc **137** (128 + 9 = SIGKILL); process gone; `child.log` shows no "FINISHED" line |
| F. durable state after kill | `processing_state=1` · token == killed token · `processing_started_at` unchanged · playback 0 · poster 0 · raw `video` 1 · **no FINALIZE / FAILURE / `ensure` ran** |
| G. operator-safe reclaim | aged `processing_started_at` past `STALE_PROCESSING_AFTER` (15 min) → `processing_claim_stale? = true`, `ProfileVideo.processing_sweepable` includes it, killed token still present |
| H/I/J. operator restart | `date9ja:transfer_videos` → `processing_stale_reclaims: 1` · `processing_succeeded: 1` · `ready: 1` · `already_ready: 34` · `originals_purged: 1` · 0 new `ProfileVideo` / binding |
| K. old token cannot finalize | a job instance holding the killed token: `owns_claim? → false` (video is `ready`, token differs) — ABA safe |
| L. exactly one derivative identity | 1 playback + 1 poster at the deterministic keys; both independently valid |
| M. valid READY | `processing_ready?` + `deliverable?` true; `processing_claim_token` now `nil` (≠ killed token) |
| N. raw purge after finalization only | raw `video` attachment gone *after* READY, never before |
| O. post-recovery rerun | `date9ja:transfer_videos` → 35 `already_ready`, 0 reclaims, zero growth |

Final terminal state (after purge drain): 35 `ProfileVideo` / 35
`LegacyReference` / 35 `ready` / 35 `deliverable?` / 0 raw attached / 35 + 35
derivative attachments / 35 + 35 independently valid / 70 blobs / 0 orphans / 0
cross-brand.

### Real-media boundary (unchanged by this run)

35 legacy `ProfileVideo` records exist (census fact); 35 deterministic synthetic
bodies were built for this rehearsal (synthetic L2 fact); the **real** videos'
duration / codec / container remain **UNKNOWN** (real-media fact). This run does
**not** show "all 35 real videos migrated" or "all real videos ≤ 60 s" or any
real codec/container distribution. **PD-2 stays OPEN — real over-limit count
UNKNOWN.**

### `git diff --check`

Clean. `git status --short`: only `docs/migrations/date9ja-to-d8n/VIDEO-L2.md`,
`RECONCILIATION.md`, `STATUS.md` (evidence docs). No implementation code changed.
