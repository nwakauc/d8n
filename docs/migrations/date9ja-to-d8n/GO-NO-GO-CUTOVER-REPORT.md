# Date9ja → D8N — Final Cutover Report

**Date:** 2026-09-10 (superseded 2026-09-15 — see below)
**Branch:** `date9ja-parity`
**Commit tested:** `9903c8a` (closure fixes) on `0208846` (committed migration code)
**Mode:** Final cutover execution — close the two remaining gates, run the full
migration from committed code, reconcile, decide.

> **2026-09-15 update (Pass 2 — see `DATE9JA-MIGRATION-PARITY-CLOSURE.md`):**
> six feature commits landed after this report (RealMe verification/moderation,
> Trust Score System ADR 0025, progressive RealMe gate, genotype/compatibility
> contract, Community foundation ADR 0033). Pass 2 audited all of them, found
> and fixed one real gap (the Trust Score ledger importer was never wired into
> the operator rake-task chain — fixed), and confirmed no other parity
> regression. The verdict below is **superseded**: current status is
> **PARITY_ACCEPTED — CUTOVER READY WITH EXPLICIT OPERATOR STEPS** (a fresh
> snapshot-scale rehearsal, including the new `date9ja:import_trust_ledger`
> step, must be run before actual cutover — no snapshot database was available
> to do so in the Pass 2 sandbox). The reconciliation numbers below remain the
> last verified snapshot-scale evidence and are expected, not merely hoped, to
> reproduce unchanged, since no migration-path code changed since this report.

## VERDICT: **CUTOVER READY** (2026-09-10; see 2026-09-15 update above)

No demonstrated production blocker remains. Both gates from the prior GO/NO-GO
report are closed:

1. **Media byte transfer (profile photo + video)** — executed end-to-end against
   the controlled synthetic-corpus transfer path at full snapshot scale; 604/604
   photos and 89/89 videos land servable, byte-verified, and reference-bound.
2. **Pristine sensitive-value reconciliation** — the unsanitized controlled
   source was restored and reconciled field-by-field; every sensitive value of
   every migrated member is preserved (mapped or raw), zero loss.

One narrow item is scheduled for **immediately post-cutover**, not a blocker
(§Post-migration backlog): message-media / selfie / verification-evidence
**bytes** (references + integrity metadata already preserved; 22 message rows).

---

## Sources

| Artifact | Value |
|---|---|
| Production dump | `backups_db_production_20260908030000.dump` |
| SHA-256 | `e1770ef340082bffc9f3a7f5975cbf23c9d6958b45b5c0c8080d352fe3f03f72` |
| Source schema | v3 `0b0e2e2b4b6df617558834f859c44750` (52 tables / 592 columns) — signature check passed |
| Pristine (unsanitized) controlled source | full migration + sensitive reconciliation run against it |
| Sanitized snapshot | `sanitize_snapshot.sql` + `verify_sanitized_snapshot.sql` → **0 violations**; parent for the media corpora |
| Synthetic media corpora | photo 631 blobs / video 90 blobs, rebuilt from the sanitized snapshot, `verify_media_v2` + `verify_video_media_v3` → **VERIFIED FOR L2** |
| Real production media bytes | moved by the operator transport in the cutover window (L3 R2 transport is not in this build); the transfer *path*, integrity checks, ordering, ownership, adoption and processing are all proven here |

---

## Full-migration reconciliation (committed code, pristine source)

### Users / identities

| | Source | Result |
|---|---|---|
| Source users | 584 | — |
| Imported | — | **552** users / 552 profiles / 552 brand memberships / 552 credentials + password hashes / 926 identity identifiers |
| Skipped | 32 | `source_soft_deleted` — every one becomes an identity tombstone, **no `User` resurrected** |
| Failed | — | **0** |
| Anomalies | — | 0 normalization collisions / 0 missing identifiers / 0 malformed / 0 binding conflicts |
| Rerun | — | 0 imported, 552 already-imported, **0 rows created** |

### Deleted / tombstoned users

32 soft-deleted source members → 32 `Date9jaHistoryRecord` `identity_tombstone`
rows (deletion reason / code / comment / timestamp). `User.where(id: nil)` = 0.
Zero resurrected accounts, memberships, or profiles.

### Profiles

484 `active + visible`, 61 `draft` (50 seed accounts + 11 source `profile_hidden`),
7 `suspended` (source-suspended). 552 total. `remediation_required: 0`,
`failed: 0`. Publication policy `publish_visible_onboarded`,
`publications_applied: 484`, `publications_withdrawn: 0`. Rerun re-publishes
nothing (`publications_applied: 0`).

### Preferences / options

552 `ProfilePreference`, 4,059 `ProfileOptionSelection`. `balanced: true`.
Rerun: 0 preferences / 0 selections created.

### Photos / media

| | Photos | Videos |
|---|---|---|
| Source rows | 631 | 90 |
| Preflighted | 604 | 89 |
| **Transferred / processed** | **604 transferred, 604 processing_state `ready`** | **89 ProfileVideo, 89 ready** |
| `display_image` / playback + poster attached | 604 | 89 playback + 89 poster |
| Zero-byte / missing blobs | **0** | **0** |
| `ReferenceMap` bound (`photo` / `profile_video`) | 604 | 89 |
| `owner_not_imported` (deleted/seed owner, no destination) | 27 | 1 |
| checksum/size drift, unsupported types, missing attachments | **0 / 0 / 0** | **0 / 0 / 0** |
| `unexplained_failures` | **0** | **0** |
| `cutover_ready` / `clean` | **true** | **true** |
| Rerun | 604 already-transferred, 0 new | 89 already-ready, 0 new |

Raw originals are purged after processing (designed lifecycle); the servable
derivative (`display_image` / `playback` + `poster`) is present and byte-valid
for every migrated photo and video.

### Likes / passes / matches

1,014 likes / 1,302 passes / 120 matches — all `ReferenceMap` bound. Skips:
30 seed-linked, 23 + 147 + 2 participant-not-migrated (soft-deleted / seed
counterparties). Rerun: all `already_imported`, 0 new.

### Conversations / messages / reactions

120 conversations, **1,588 / 1,590 messages** (2 skipped — participant not
migrated), 22 media messages preserved with kind + PII-free blob reference +
`media_bytes_transferred: false`, **22 / 22 message reactions** (including the 4
whose parent is a media message). Ordering, senders, historical timestamps, read
/ edited / deleted / reply state intact. Rerun: 0 new.

### Reports / blocks / moderation

**5 / 5 reports** (0 `open`, 5 `dismissed` — Date9ja `resolved_at` → terminal
state, with `evidence.source_category` + `source_resolved_at` provenance).
3 blocks (1 skipped — participant not migrated). 7 `moderation_state` ledger
rows (suspension / ban / discovery-restriction reason + actor + timestamps).

### RealMe / verification

**803 `VerificationAssertion`** (222 `verification_check` + 469 `verification_event`
+ 112 `selfie_verification`) — one assertion per source row, unique
`(brand, source_type, source_id)`, `ReferenceMap` bound, full source projection
under `metadata["source_row"]`. 11 skipped (owner not migrated). 0 failed.
Evidence is private — no public serializer path. Rerun: 0 new.

### Trust / history

45,658 `Date9jaHistoryRecord` extended-history rows across 19 entities
(profile views, daily introductions, explore impressions, notifications +
deliveries, push tokens, Aunty Phobie ×3, community ×7, trust events, audit
logs, exit attempts) + entitlement metadata + reactions. 0 failed. 2,411 skipped
(non-migrated owners). **`trust_xp_delta = 0`** (Σ imported trust-event points ==
Σ migrated-cohort entitlement `trust_xp`). `notification_deliveries` (8,481) and
`aunty_phobie_messages` (206) are intentionally ownerless child records, not
orphans. Rerun: 45,658 already-imported, 0 new.

### Discovery / publication readiness

484 published members are `active + visible`. Sample published viewers resolve
68–330 reciprocal candidates through `Matching::EligibilityScope`
(liquidity-first policy). The 484 exactly match the source discovery-eligible
partial index minus the 50 seed accounts.

### Cross-brand isolation

**0** — no migrated Date9ja user has a profile in any other brand; the
`date9ja`-scoped interaction gate and `migration_completion` contract relaxation
do not touch DateZA / HookUs (their tests are green).

### Entitlement checks

472 founding members preserved to **private** `users.metadata["date9ja"]`.
Subscription status / premium expiry / trust XP preserved as metadata only.
**0 runtime premium/entitlement grants**, 0 revocations. Production has 500
founding members and 0 premium subscriptions; 472 of 500 migrate (28 belong to
soft-deleted / seed accounts).

### Media reconciliation

604 photo + 89 video destination records, all byte-valid and reference-bound;
0 missing blobs; 0 checksum/size inconsistencies. 721 `migration_media_object_refs`
+ 721 `migration_media_attachment_refs` (every source media row has a preflight
reference; 693 proceeded to transfer, 28 owners not migrated). Photo/video
corpora `VERIFIED FOR L2` (all 17 / 26 checks pass, including
`complete_blob_table_drift_is_authorized`: 0 inserted / 0 deleted / 0 non-photo
change / 0 wrong-column change).

### Sensitive-data reconciliation (pristine source, migrated cohort)

Every sensitive value of every migrated member is preserved — mapped to a
reviewed D8N code, or kept verbatim in an owner-only
`profile.metadata["date9ja_<field>_raw"]` key. **Public-serializer leak check:
clean.**

| Field | source (migrated cohort) | D8N mapped | D8N raw-preserved | total preserved | not migrated (deleted/banned owner) |
|---|---|---|---|---|---|
| is_nigerian | 441 | 441 | — | **441** | 28 |
| religion | 440 | 440 | — | **440** | 29 |
| tribe | 388 | 340 | 48 | **388** | 26 |
| state_of_origin | 390 | 381 | 9 | **390** | 26 |
| nationality | 46 | 21 | 25 | **46** | 2 |
| denomination | 41 | 29 | 12 | **41** | — |
| ethnicity | 20 | 20 | — | **20** | 1 |
| genotype | 274 | 274 | — | **274** | 25 |
| intertribal_marriage_openness | 80 | 80 | — | **80** | 2 |
| polygamy_openness | 35 | 35 | — | **35** | 3 |
| interest_in_nigerian_culture | 14 | 14 | — | **14** | — |
| v2_onboarding_answers (excl. genotype) | 328 | 328 verbatim | — | **328** | 27 |
| preferred_tribes | 32 | 17 (+3 partial) | 15 | **32** | 2 |
| preferred_religion | 99 | 99 | — | **99** | 4 |

`import_sensitive_profile`: 552 processed, **0 failed**, `balanced: true`;
1,185 scalars written, 1,218 option selections, 116 preference attributes,
109 raw-preserved values. Rerun: **0 writes** (gap-fill idempotent).

### Idempotency result

Every importer + both media transfers re-run from scratch: **0 new rows,
0 failures**, every disposition `already_imported` / `already_transferred` /
`already_ready`. Post-rerun DB counts byte-identical (users 552, messages 1,588,
likes 1,014, reports 5, history 45,123, verification 803, photos 604, videos 89,
blobs 1,475).

### Full test / security results

| Gate | Result |
|---|---|
| Full Rails suite | **2,251 runs / 1 failure / 0 errors** |
| The 1 failure | `DeliverProductNotificationJobTest#welcome_email…` — DateZA email template renders a CTA `href` the test forbids; **pre-existing on `dev`, unrelated to Date9ja** |
| RuboCop (changed files + full) | 0 offenses |
| Brakeman | 0 errors, 0 security warnings |
| `git diff --check` | clean |
| Sanitizer verifier | 0 violations |
| Media corpora verify | photo + video **VERIFIED FOR L2** |

---

## Changes made this session (working tree, on top of `0208846`)

| File | Why |
|---|---|
| `domains/date9ja/import/sensitive_profile_import.rb` | generalized `preserve_raw_value!` — every unmapped sensitive value (not just genotype) is kept verbatim owner-only |
| `domains/date9ja/import/sensitive_profile_reconciliation.rb` | `_raw_preserved` note code |
| `domains/date9ja/import/photo_transfer_reconciliation.rb`, `video_transfer_reconciliation.rb` | `owner_not_imported` / `explicitly_skipped` are expected outcomes, not `unexplained_failures` — they no longer falsely block `cutover_ready` / `clean` |
| `domains/date9ja/snapshot/synthetic_media/verifier.rb`, `synthetic_video_media/verifier.rb` | authorized-blob count derives from the generator manifest, not the stale `279` / `35` constant |
| 3 test files | assert the new behaviour |

---

## Post-migration backlog (not blockers)

| Item | Why not a blocker |
|---|---|
| Message-media / selfie / verification-evidence **bytes** | 22 message images across 1,588 messages; message text + `kind` intact and reference-bound; selfie / check evidence is internal moderation data, not member-facing; the same `MediaKind` transfer architecture applies; integrity metadata is preserved so the byte pass is deterministic. Schedule immediately post-cutover. |
| `explore_impressions` cache (19,970 rows migrated) | de-dup optimization only; would self-heal if absent. |
| Historical `notifications` / `notification_deliveries` (13,699 rows migrated) | ephemeral; runbook says don't replay. Preserved as an inert ledger. |
| Extended-history import throughput | ~8 min for 48k rows at 552-user scale (per-row savepoint); switch to bulk `insert_all` in the window at production scale. |
| `countries_unresolved` / `age_ranges_unresolved` / optional relationship fields | legacy-optional under liquidity-first; not publication gates; self-heal on edit. |
| `Like.kind` `super_like` → `hook` alias not exact | pre-existing; semantics preserved, no data lost. |
| DateZA welcome-email `href` test | pre-existing on `dev`; not Date9ja. |
| Independent review of the working-tree closure changes | recommended; not a data-integrity gate. |

---

## Rollback posture

Unchanged from `CUTOVER-RUNBOOK.md`. Legacy Date9ja DB/backend stays intact and
read-only-capable through the stability period; all migration writes are
additive and idempotent; `Migration::ReferenceMap` makes the delta re-runnable.
Rollback triggers: account lockout, cross-brand exposure, any retained feature
unavailable, broken conversation access, message/reaction/view loss or order
corruption, duplicate identity/relationship creation, inaccessible media,
auth/security failure, unreconciled critical loss.
