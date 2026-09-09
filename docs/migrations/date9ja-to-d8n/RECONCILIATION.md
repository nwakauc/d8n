# Reconciliation Plan

## Authoritative rehearsal baseline — 2026-09-08

The current rehearsal source baseline is the aggregate-only evidence in
[`AUTHORITATIVE-SNAPSHOT-20260908.md`](AUTHORITATIVE-SNAPSHOT-20260908.md): 584
users, 552 identity-import eligible, 32 excluded/deleted, 631 photos, 90 profile
videos, and schema v3 `0b0e2e2b4b6df617558834f859c44750`. It is
**SELF_VERIFIED**, not independently VERIFIED, and is not the future cutover
snapshot. All older 288-user/279-photo values below are historical evidence and
must not be combined with this baseline in one reconciliation run.

## Historical graph/state migration — implementation evidence (2026-09-08)

`Date9ja::Snapshot::HistoricalGraphSource` normalizes Date9ja relationship rows
(`liker_id`/`liked_id`, `user_a_id`/`user_b_id`, `sender_id`/`match_id`, and
equivalent block/report columns) into the `Date9ja::Import::HistoricalGraphImport`
contract. Date9ja has no conversation table: `date9ja-match:<match_id>:conversation`
is the deterministic source identity used by both derived conversations and
messages. The importer processes rows in dependency order: likes/passes, matches,
conversations, messages, blocks, reports. Every
relationship participant is resolved through the Date9ja `profile`
`Migration::ReferenceMap` binding; missing or ineligible owners are counted as
`participant_not_migrated`. Each row runs in a savepoint and receives its own
source-entity reference binding. Existing bindings/records are reused, native
records are not rewritten, and writes use direct canonical persistence so no
runtime notifications, quotas, or current timestamps are generated. Message
content is currently accepted only for text rows; unsupported/blank historical
message types are quarantined. Profile views are not imported pending a product
retention decision.

Fixture evidence covers canonical graph creation, ordered text history, missing
participant quarantine, second-run zero growth, immutable reference reuse, and
zero `NotificationEvent` side effects. Only rows with explicit `created_at` are
imported; missing timestamps are quarantined as `missing_created_at`. Message
types are checked before body handling: text is supported, while media/voice/video
and other types are quarantined as `unsupported_message_type`, even with captions.
Reply links, read state, edited timestamps, and report free text/evidence remain
explicit parity items because they are not in the normalized source contract.
Reports use source identity bindings; destination uniqueness can still reject
duplicate open profile reports as `destination_conflict` rather than collapsing
them. Existing native tuple relationships may absorb a historical binding; native
lifecycle state wins. Full 546-like / 82-match / 1,025-message corpus totals
remain deferred to the approved whole-system rehearsal.

The historical HTTP journey is fixture-proven through the normal Date9ja
runtime (`test/controllers/api/v1/date9ja_historical_conversation_journey_test.rb`):
Date9ja-shaped source rows pass through the snapshot adapter and importer, and
the resulting canonical graph is then exercised only through the public Core
Dating Loop endpoints — the historical match lists, the derived conversation
resolves to the same record the importer bound, historical messages read back in
the API's canonical newest-first order with senders/bodies/timestamps intact, a
new native message is sent over HTTP, and the peer reads history plus that new
message. Rerunning the import afterwards produces no duplicate match,
conversation or message, leaves the native message and all reference bindings
byte-identical, and emits no `NotificationEvent` — while the native HTTP send
keeps its ordinary runtime notification behaviour. This is fixture evidence
through the real runtime, not a real-corpus rehearsal or production migration.

No production counts were collected in Phase 1 because production access remains out of scope. Run against the approved snapshot and staging/import output, recording snapshot/run IDs and timestamps.

## Source census

The source column is produced by `scripts/date9ja/source_census.sql` — a
read-only, schema-fingerprint-guarded script that emits one row per measure plus
the sub-state breakdowns an importer needs to make "equal after documented
exclusions" unambiguous. Run it against `date9ja_snapshot_sanitized` (row counts
are identical to the pristine restore — the sanitizer preserves every row):

```
psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized -f scripts/date9ja/source_census.sql
```

Paste the full output into the run record and fill the table below from it.

### Snapshot 2026-09-02 (rehearsal artifact) — headline source counts

Operator-verified after `sanitize → verify → pg_dump → pg_restore` into
`date9ja_snapshot_package_test`; all row counts survived the round trip.

| Measure | Source | Target | Acceptance |
|---|---:|---:|---|
| users/accounts | 288 | 280 (rehearsal 2026-09-03) | 288 = 280 imported + 8 skipped (`source_soft_deleted`) + 0 failed; idempotent on rerun |
| published profiles | pending (census: `onboarding_completed_at NOT NULL`) | pending | equal after state mapping; definition confirmed with product |
| photos | 279 | pending | equal; exceptions listed |
| profile videos | 35 | pending | equal; exceptions listed |
| active storage blobs | 443 | pending | every object preflights; checksum/size/type match |
| verified users | pending (census: `verification_tier > 0`) | pending | equal under approved definition |
| likes | 546 | pending | equal after valid mapping |
| passes | pending (census: `profile_passes`) | pending | equal or approved exclusion |
| matches | 82 | pending | equal canonical unique pairs |
| conversations | 82 (one container per match; Date9ja has no separate table) | pending | one per retained match |
| messages | 1025 | pending | equal per retention policy |
| profile views | 1627 | pending | equal per retention policy |
| blocks | 3 | pending | equal same-brand rows |
| reports | 3 | pending | equal retained reports |

Also reconcile profile videos, message reactions, profile views, verification records/status/history, trust records/status, notification preferences/deliveries, Community, Dating Hub, Aunty Phobie, subscription/entitlement state, and any other active capability in [CAPABILITY-PARITY.md](CAPABILITY-PARITY.md). For retained features, an “approved exclusion” is not a cutover pass: the feature must have a supported target or an explicitly approved transition that preserves user access.

Validate that every mapped user has exactly one D8N user and at most one Date9ja membership/profile; every relationship is same-brand, non-self, directional where applicable; every match is canonical and unique; every conversation has exactly two match participants; every message has a valid participant sender and same-conversation reply; and read state maps to the correct participant.

For media, verify every source blob/object exists, matches checksum/size/type, maps to a destination public ID, and is deliverable under D8N privacy rules. Missing or unsupported objects are exceptions, not skips.

Run the importer twice against the same snapshot: the second run must create zero users, profiles, relationships, conversations, or messages, and destination IDs/fingerprints must remain unchanged. Test interruption/resume as well.

## Migrated profile readiness contract — 2026-09-07

`Date9ja::Import::ProfileReadinessImport` is the migration-side bridge into the
existing shared completion/publication services. It persists one current,
PII-free `Migration::ProfileReadiness` row per eligible source member with one
disposition (`ready`, `intentionally_hidden`, `remediation_required`, `failed`)
and zero or more reason codes. Source names, city strings, emails and other PII
are not stored in the evidence row; only a source fingerprint is retained.

The run is accepted only when `eligible == sum(dispositions)`, technical failures
are zero, and a second run preserves destination IDs and member/operator/native
values. Reconciliation exposes source/mapped/preserved/unresolved measures for
names, country, location, ages and every required option group, plus completion
before/after and publication counts.

### Executable baseline — available isolated destination

Run 2026-09-07 against `d8n_date9ja_rehearsal_l2_20260903`, applying the current
Date9ja catalogue only inside a rolled-back transaction:

| Measure | Count |
|---|---:|
| Profiles | 280 |
| Complete before readiness | 0 |
| Missing first/last name | 280 / 280 |
| Missing country / location | 280 / 280 |
| Missing interested-in / min-age / max-age | 280 / 280 / 280 |
| Missing relationship-intent / has-children / wants-children | 280 / 280 / 280 |
| Missing city / bio | 280 / 74 |
| Missing publication-eligible photo | 125 |

This destination predates the completed profile-preference pass, so it is a real
baseline for the available identity+photo artifact, not the final readiness
rehearsal. It must not replace the later checked-in evidence of 63 valid age
pairs and 477 approved option selections.

### Sanitized source rehearsal — DEFERRED EVIDENCE

The established `date9ja_snapshot_sanitized` source database and
`DATE9JA_SNAPSHOT_DATABASE_URL` are absent from the current environment. No
source data was copied from unapproved local databases and no production system
was accessed. Therefore ready/hidden/remediation totals and deterministic mapping
counts for the 280-member cohort are not recorded here. Run
`date9ja:import_profile_readiness` twice in the approved isolated environment,
with the current brand catalogue installed and the identity, preference and
media passes already complete. Keep the default `classify_only` until D-8 is
explicitly approved.

### Recovery audit — 2026-09-07

The established recovery procedure was re-traced in `SNAPSHOT-RUNBOOK.md`:
restore an approved encrypted backup into isolated PostgreSQL 17 as
`date9ja_snapshot_tmp`, create the sanitized working copy
`date9ja_snapshot_sanitized`, run the sanitizer and verifier, then expose it
through `DATE9JA_SNAPSHOT_DATABASE_URL` (the prior rehearsal used local port
55432). The repository contains the source census, schema signature, sanitizer,
verifier, and recorded 288 → 280 → 8 evidence, but no dump/archive or approved
connection details are present in the current workspace. The local PostgreSQL
catalog was checked: it contains D8N rehearsal databases and unrelated or
ambiguously named databases; those were not opened or treated as Date9ja data.
A bounded home/workspace artifact search found no matching Date9ja dump. No
production access, export, restore, or source mutation was performed. The
readiness rehearsal remains blocked until the approved snapshot/database or its
encrypted restore artifact is supplied by an authorized operator.

## Profile & preference VALUE census contract (Pass 1 — PROFILE-VALUE-MAPPING.md)

Pass 1 is evidence only: it creates no destination row, so there is **no
destination reconciliation yet**. What it produces is the SOURCE side that the
later Pass-2 importer must balance against. Authority for the mapping itself is
[PROFILE-VALUE-MAPPING.md](PROFILE-VALUE-MAPPING.md).

Measures live in `scripts/date9ja/source_census.sql` at **ord 200-299**, under the
same READ ONLY transaction and v2 schema-signature guard as every other measure.

### Which database produces which section

Most sections are sanitizer-faithful. Two are not, and running them against the
sanitized copy measures the sanitizer rather than Date9ja — record which database
produced each number:

| Section | Ord | Database |
|---|---|---|
| `source_types` | 200-202 | either |
| `profile_values` | 210-225 | `date9ja_snapshot_sanitized` |
| `preference_validity` | 230-246 | `date9ja_snapshot_sanitized` |
| `gender_compat` | 250-259, 290-299 | `date9ja_snapshot_sanitized` |
| `profile_shape` (name token shape) | 260-261 | **pristine restore only** |
| `country` | 265-266 | `date9ja_snapshot_sanitized` |
| `publication` | 270-272 | `date9ja_snapshot_sanitized` |
| `arrays` — `languages_spoken` / `preferred_countries` / `relocation_preferences` | 283-285 | `date9ja_snapshot_sanitized` |
| `arrays` — `interests` / `relationship_values` / `dealbreakers` | 280-282 | **pristine restore only** |

Only the aggregate census output leaves the isolated environment. No measure in
this range emits a name, a free-text value, a location string, an array element,
or any row-level data — see PROFILE-VALUE-MAPPING.md section 2.1 for the emitter
contract and the test that enforces it.

### Source-side counts Pass 2 must balance against

**Run 2026-09-05; measures 221 / 225 / 259 / 290-299 re-run 2026-09-06** after an
independent review — `date9ja_snapshot_sanitized` (and `date9ja_snapshot_tmp` for
the PRISTINE-ONLY rows) on the isolated PG17 instance. Schema signature
`41a653a8d4c25621071fb76e6e59fbc0` OK on both; the re-run measures returned
identical values on both databases.

**Population — the importer's own rule, not one invented for reconciliation.**
`IdentityImport#import_one` skips `soft_deleted?` / `banned?`
(`identity_import.rb:63-64`, `user_record.rb:48,50`), so the migration-eligible
population is `deleted_at IS NULL AND banned_at IS NULL`: **288 source rows, 8
soft-deleted, 280 migration-eligible** (measure 290). The importer applies no
seed or admin exclusion, so neither does this table.

| Measure | Ord | Source | Target | Acceptance |
|---|---|---:|---:|---|
| users eligible for a complete `ProfilePreference` | 245 | **0** | pending | 0 expected while D-10 is open — `preferred_distance_km` is NULL for all 288 |
| users lacking >= 1 required preference input | 246 | **280** | pending | equals the whole live population; every one handled by the approved D-10/D-9 policy, none silently dropped |
| 245 + 246 partition check | — | **280** | — | must equal kept + not banned; enforced by test |
| `preferred_age_min` NULL | 230 | **222** | pending | accounted for by policy |
| `preferred_age_max` NULL | 231 | **223** | pending | accounted for by policy |
| both age preferences NULL | 232 | **222** | pending | accounted for by policy |
| age values outside 18..120 | 233-236 | **0 / 0 / 0 / 0** | 0 | no invalid-age policy needed |
| inverted age ranges | 237 | **0** | 0 | none exist |
| valid age pairs | 238 | **65** | 65 | migrate verbatim; equal |
| `preferred_distance_km` NULL | 240 | **288** | — | NO_SOURCE (D-10) |
| `preferred_distance_km` invalid (<=0 / >500) | 241, 242 | **0 / 0** | 0 | none exist |
| valid distances | 243 | **0** | 0 | none exist |
| reciprocal-capable population | 257 | **280** | pending | upper bound on discovery-eligible migrated profiles |
| `gender` NULL | 250 | **0** | 0 | every member has a candidate gender |
| `looking_for` NULL | 251 | **0** | 0 | every member has a stated preference (reliability is D-9) |
| gender codes with no `looking_for` counterpart | 255 | **0** | — | shared vocabulary confirmed |
| `looking_for` codes with no gender counterpart | 256 | **0** | — | shared vocabulary confirmed |
| gender x looking_for pairs (all 288) | 258 | `g0/l0:108 g0/l1:89 g1/l0:89 g1/l1:2` | pending | D-9 governs how many survive as `interested_in` |
| gender x looking_for pairs (migration-eligible) | 259 | `g0/l0:105 g0/l1:84 g1/l0:89 g1/l1:2` | pending | the 280 rows Pass 2 will actually see |
| migration-eligible population | 290 | **280** | 280 | importer skip rule; must equal 245 + 246 |
| eligible AND onboarded — total / same code / differing / indeterminate | 291-294 | **112 / 79 / 33 / 0** | — | D-9 evidence; 79/112 = 70.5 % same code |
| eligible AND never onboarded — total / same code / differing / indeterminate | 295-298 | **168 / 28 / 140 / 0** | — | D-9 evidence; 28/168 = 16.7 % same code |
| cohort partition proof | 299 | `eligible:280 onboarded:112=79+33+0 not_onboarded:168=28+140+0 **OK**` | OK | must read OK; enforced by test |
| `body_type` allowlisted buckets | 221 | `slim:63 regular:56 athletic:23 muscular:16 curvy:12 plus_size:11` · `OTHER:13` · `NULL:94` | pending | free text; **only the six documented suggestions are ever emitted** (D-3) |
| `body_type` distinct non-blank values | 225 | **18** | — | 12 spellings outside the six suggestions |
| expected `relationship_intent` selections | 215 | **213** (75 NULL) | pending | one selection per mapped member; unmapped codes fail closed |
| expected `wants_children` selections | 217 | **208** (80 NULL) | pending | as above |
| expected `has_children` selections | 223 | **149** (139 NULL) | pending | `children_count` is an ENUM — `3` = `three_or_more` |
| expected `education_level` selections | 219 | **89** (199 NULL) | pending | as above |
| expected `meeting_pace` selections | 202 | **NO_SOURCE — 0** | 0 | required group, never fabricated (D-7) |
| `smoking` present (required field) | 212 | **87** (201 NULL) | pending | D-11 cohort |
| `drinking` present (required field) | 213 | **175** (113 NULL) | pending | D-11 cohort |
| `country_of_residence` already ISO-2 | 265 | **0 of 288** | pending | every row needs E-1 |
| `country_of_residence` distinct names | 265 | **23** | — | size of the E-1 mapping table |
| `country_of_residence` outside the allowlist | 266 | **20** | pending | explicit review under E-1 |
| `full_name` token shape *(pristine)* | 260 | 1-token **26** / 2-token **250** / 3+ **12** | pending | quantifies D-4; no split performed |
| publication cohorts | 270 | `visible/not_onboarded:166` `visible/onboarded:114` `hidden/not_onboarded:6` `hidden/onboarded:2` | pending | equals the cohorts the approved D-8 policy publishes/hides |
| candidate publish cohort | 272 | **109** | pending | upper bound — D8N publication also requires `Profiles::Completion` |
| `profile_completeness_score` > 0 | 35 | **0** | — | carries no signal; do not migrate |
| unclassified `users` columns | 202 | **none** | — | invariant holds |
| expected value-census columns missing | 201 | **none** | — | invariant holds |

**Quarantinable / no-source rows for Pass 2:**

| Class | Count | Cause |
|---|---:|---|
| No `max_distance_km` source | **288** | column NULL for every row (D-10) |
| No `meeting_pace` source | **288** | column does not exist (D-7) |
| No `country_code` derivable without E-1 | **288** | zero rows are already ISO-2 |
| ~~`looking_for` of doubtful reliability~~ | **0 — not a quarantine class** | **D-9 RESOLVED (2026-09-06): every `looking_for` value migrates exactly as stored.** Nothing here is quarantined. A same-gender preference is an orientation, not a defect — some members are gay — and migration does not revise what a member already chose. The cohort figures (79/112 onboarded vs 28/168 not) remain in `PROFILE-VALUE-MAPPING.md` §5.3 as history about the *form*, never as a judgement about a person |
| `body_type` outside the six documented suggestions | **13** of 194 present | free-text column (D-3) |
| Missing required `smoking` | **201** | never answered (D-11) |
| Missing required `drinking` | **113** | never answered (D-11) |
| `full_name` not two-token | **38** | 26 one-token + 12 three-or-more (D-4) |
| `height` outside any plausible band | present:188, range **1..588** | junk values (E-2) |

### Pass-2 destination-side contract (profile & preference importer)

`Date9ja::Import::ProfilePreferenceReconciliation#to_h` is deterministic and
**PII-free** — counts and codes only, asserted by test. Every considered row
lands in exactly one disposition, so
`source_users_considered == sum(dispositions)` always holds (`balanced?`).

| Section | Keys |
|---|---|
| `dispositions` | `imported`, `already_imported`, `skipped`, `failed` |
| `created` | `preferences_created`, `option_selections_created`, `genders_decoded`, `legacy_references_created` |
| `anomalies` | `binding_conflicts`, `malformed_rows` |
| `reasons` | `source_soft_deleted`, `source_banned`, `profile_not_imported`, `already_imported`, `dangling_binding`, `binding_conflict`, `preference_invalid`, `option_selection_invalid`, `source_row_error` |
| `notes` | why a field was left unset on an otherwise successful import |

**`notes` are deliberately NOT dispositions.** A row can import successfully and
still leave a field unset — because the member never answered (`*_absent`) or
because its legacy code has no approved D8N destination yet (`*_unmapped`).
That is a partial import, not a failure, and counting it as one would misreport
the run. Expected source-side magnitudes, from the Pass-1 census:

| Note | Expected | Cause |
|---|---:|---|
| `max_distance_km_no_source` | **280** (every eligible row) | column NULL for all 288 (D-10 relaxed) |
| `meeting_pace_no_source` | **280** (every eligible row) | column never existed (D-7 relaxed) |
| `age_range_absent` | ~215 | `preferred_age_min`/`max` NULL for 222/223 |
| `age_range_invalid` | **0** | census found 0 out-of-range and 0 inverted |
| `relationship_intent_absent` | 75 | NULL |
| `relationship_intent_unmapped` | **35** | `courtship` 27 + `dating` 7 + `activity_partner` 1 (D-5) |
| `wants_children_unmapped` | **45** | legacy `open` (D-6) |
| `has_children_absent` | 139 | `children_count` NULL |
| `interested_in_unmapped` | **0** | both codes map; **same-gender values are ordinary, never unmapped** |
| `gender_unmapped` | **0** | both codes map, 0 NULL |

Acceptance for a Pass-2 run: `balanced?` true; `preferences_created + already_imported`
equals the eligible population (280); `anomalies` all zero; and every
`*_unmapped` count equals the census figure above — a *different* number means
the source drifted or a mapping table changed, and must be explained before the
run is accepted.

### Pass-2 destination rehearsal — RUN 2026-09-06

**Environment.** Isolated PG17 instance (`127.0.0.1:55432`) holding
`date9ja_snapshot_sanitized`, read through `Date9ja::Snapshot::Connection`
(fail-closed safety fences); destination a throwaway
`d8n_date9ja_rehearsal_pref_20260906` under `RAILS_ENV=test`. **No Date9ja
production system was contacted.** Dependency order: `db:schema:load` →
`Brands::Date9jaInstaller` (12 option groups / 86 options) →
`date9ja:import_identity` → `date9ja:import_profile_preferences`.

Identity import reproduced its VERIFIED baseline exactly: 288 considered → **280
imported / 8 skipped (`source_soft_deleted`) / 0 failed**, 1580 bindings.

**Staged starting state.** To exercise the gender repair path against the real
corpus, all 280 profiles were reset to the raw legacy code the *earlier*
rehearsal actually produced (`"0"` / `"1"`), and **5 profiles whose source says
`man` were given the member-chosen value `"woman"`** — non-legacy values the
importer must not touch.

#### Source (eligible cohort, `deleted_at IS NULL AND banned_at IS NULL` = 280) → destination

| Measure | Source | Destination | |
|---|---|---|---|
| eligible migrated members | 280 | 280 Profile rows found | ✅ |
| `gender` | `0:189 1:91` | `man:184` + `woman:96` — i.e. 189/91 with the 5 planted member choices moved | ✅ |
| raw `"0"`/`"1"` remaining | — | **0** | ✅ |
| genders decoded | 275 raw codes present | `genders_decoded: 275` | ✅ |
| member-chosen gender overwritten | — | **0 of 5** | ✅ |
| `looking_for` → `interested_in` | `0:194 1:86` | `["man"]:194` `["woman"]:86` | ✅ |
| gender × interested_in | census 259 `g0/l0:105 g0/l1:84 g1/l0:89 g1/l1:2` | `man→man:105` `man→woman:79` `woman→man:89` `woman→woman:7` — the 5 planted profiles moved from `man→` to `woman→` | ✅ |
| age pair valid | 63 | `min_age`+`max_age` set on **63** | ✅ |
| age both NULL | 216 | `age_range_absent: 216` | ✅ |
| age half-answered | 1 (min only) | `age_range_partial: 1` | ✅ |
| age inverted / out of range | **0 / 0** | `age_range_invalid: 0` | ✅ |
| `preferred_distance_km` | NULL for all 280 | `max_distance_km` NULL for **280**, set for **0** | ✅ |
| `ProfilePreference` created | — | **280** | ✅ |
| `profile_preference` bindings | — | **280**, 0 unbound, 0 duplicate | ✅ |

**`interested_in` is taken from `looking_for`, never inferred from gender** —
proven by the totals: 194/86 matches `looking_for`, not gender's 189/91.
**Same-gender preferences are carried across normally**: `man→man` is the single
largest bucket at 105, handled by exactly the same code path, with no flag,
reason code or quarantine.

#### Option selections — 477 created

| Group | Source populated | Mapped | Unresolved | NULL skipped | Created | Anomalies |
|---|---:|---:|---:|---:|---:|---:|
| `relationship_intent` ← `relationship_intention` | 208 | **175** | **33** | 72 | 175 | 0 |
| `wants_children` ← `wants_children` | 203 | **158** | **45** | 77 | 158 | 0 |
| `has_children` ← `children_count` | 144 | **144** | 0 | 136 | 144 | 0 |
| `meeting_pace` | **0 — no source column exists** | 0 | 0 | — | 0 | 0 |

Destination values: `relationship_intent` `marriage:106` `long_term_relationship:68`
`friendship:1`; `wants_children` `yes:139` `no:19`; `has_children` `no:138` `yes:6`.
Each equals its source code count exactly.

**Intentionally unresolved — no mapping was invented to improve these numbers:**

| Legacy value | Count | Why unresolved |
|---|---:|---|
| `relationship_intention: courtship` (1) | **26** | no D8N option means this (D-5) |
| `relationship_intention: dating` (3) | **7** | `casual_dating` and `open_to_dating` are different claims (D-5) |
| `relationship_intention: activity_partner` (5) | **0 present** | no D8N counterpart (D-5) |
| `wants_children: open` (2) | **45** | `maybe` and `open_to_partner_with_children` mean different things (D-6) |

`education`, `smoking` and `drinking` are **not in this slice's scope** — profile
scalars are a later slice; no selection or column was written for them.

#### Idempotency — second run, same source

`0 imported / 280 already_imported / 8 skipped / 0 failed`, balanced, and **every
creation counter zero**: 0 preferences, 0 option selections, 0 genders decoded, 0
bindings. Duplicate `LegacyReference` bindings **0**; duplicate preferences per
profile **0**; duplicate selections per group **0**; totals unchanged at
280 / 477 / 280.

#### Member-choice preservation — proven on the real corpus

Between the two runs, member-owned values were planted and the importer re-run:

| Planted | Result |
|---|---|
| 5 profiles with a member-chosen `gender` (`"woman"`, source says `man`) | **5/5 preserved, 0 overwritten** |
| 10 preferences changed (`interested_in` `["woman","man"]`, ages 21-55, `max_distance_km: 42`) | **10/10 preserved exactly**, including a distance the importer never writes and never cleared |
| 10 `wants_children` selections changed to `maybe` | **10/10 preserved** |

The gender repair fired on **exactly** the 275 profiles still holding a raw
legacy code and on none of the 5 member-owned values.

#### Discovery compatibility — bounded, nothing published

Run inside a transaction that was **rolled back**; publication state before and
after is identical (`draft:273 suspended:7`, `visibility hidden:280`). **No
migrated member was published or unhidden.**

| Viewer shape | Reciprocal gender match | …with an age range | Full `EligibilityScope` |
|---|---:|---:|---:|
| `man → man` (same-gender) | **104** | 16 | 0 |
| `man → woman` | 93 | 18 | **4** |
| `woman → man` | 84 | 42 | 0 |
| `woman → woman` (same-gender) | 84 | 42 | 0 |

The migrated `man`/`woman` strings are **compatible with
`Matching::EligibilityScope`**, and **same-gender values are treated identically
to opposite-gender ones** — `man→man` yields the *largest* reciprocal pool of any
shape (104). Unset `max_distance_km` does **not** eliminate the cohort: with no
viewer location and no distance on either side, `EligibilityScope#without_viewer_location`
keeps every candidate whose own `max_distance_km` is NULL, and all 4 candidates in
the working sample are exactly those.

**The remaining narrowing is age reciprocity, not gender and not distance.** Only
68 of 280 migrated members are matching participants, and 33 of those have at
least one candidate, because **217 members have no age range at all**. That is
the same absence-of-source shape as D-10 / D-7, and it is recorded as **D-12**;
no value was invented for it here.

### Standing invariants

- Measure **201** must read `none` — every column this census expects exists in
  the source.
- Measure **202** must read `none` — every column in the source is classified by
  the importer, the sensitive denylist, this census, or `SNAPSHOT-RUNBOOK.md` §4.
- No Pass-2 importer may default, clamp, or invent a value for an unmapped source
  code. Unmapped codes fail closed, consistent with the photo-moderation
  (ADR 0027) and video-duration (ADR 0029) precedents.

## Identity importer reconciliation contract (Wave A slice 3)

`Date9ja::Import::IdentityImport` (in the Date9ja adapter, `domains/date9ja/`)
emits `Date9ja::Import::Reconciliation#to_h` — deterministic and **PII-free**
(counts and reason codes only; no email, phone, bcrypt hash, or free text). Every
source row lands in exactly one disposition and every non-import carries a reason
code, so `source_users_considered == sum(dispositions)` always holds.

| Section | Keys |
|---|---|
| `dispositions` | `imported`, `already_imported`, `skipped`, `failed` |
| `created` | `users_created`, `identifiers_created`, `credentials_created`, `password_hashes_created`, `credentials_recovery_required`, `memberships_created`, `profiles_created`, `legacy_references_created` |
| `anomalies` | `normalization_collisions`, `missing_identifiers`, `malformed_rows`, `binding_conflicts` |
| `reason_codes` | only codes with a positive count |

Reason codes:

| Code | Disposition | Meaning |
|---|---|---|
| `source_soft_deleted` | skipped | `users.deleted_at` present — documented exclusion for this slice |
| `source_banned` | skipped | `users.banned_at` present — enforcement tombstone, not migrated here |
| `already_imported` | already_imported | the `user` `LegacyReference` resolves and all required identity, membership, and profile bindings are present and consistent; nothing created |
| `email_unparseable` | failed | `users.email` fails D8N canonical email normalization (required identifier) |
| `email_collision` | failed | the normalized email already exists on another D8N identity — **never merged**, row fails closed |
| `phone_unparseable` | (row still imported) | `users.phone` present but fails E.164 normalization — phone identifier skipped |
| `phone_collision` | (row still imported) | normalized phone already exists elsewhere — phone identifier skipped, never merged |
| `credential_hash_unusable` | failed | `encrypted_password` empty or not a 60-char bcrypt string **and** the row has no operable recovery channel (verified email; a verified phone alone does not count) — failed closed, no account created (never an unreachable account) |
| `credential_recovery_required` | (row still imported) | `encrypted_password` unusable **but** the row has a **verified email** (`FieldMapping.operable_recovery_channel?` — the identifier the password credential is bound to and the one the shared runtime can complete recovery through) → migrated as a recovery-required credential (active password credential, no `CredentialPasswordHash`); `credentials_recovery_required` bumps, first access is the signed-out recovery flow (`AUTH-TRANSITION.md`) |
| `credential_hash_corrupt` | failed | a resolvable prior import whose persisted `credential_password_hashes.password_hash` is present but not a supported bcrypt string (`BCRYPT_RE` + `BCrypt::Password.new`) — corrupt destination state, fail closed, `malformed_rows` anomaly. Never produced by the importer itself. |
| `profile_invalid` | failed | shared `Profile` validation rejected the mapped row (e.g. birthdate < 18) |
| `dangling_binding` | failed | a `user` reference exists but its destination row is gone — fail closed |
| `incomplete_binding` | failed | a prior `user` reference resolves, but one or more required downstream bindings/records are missing or inconsistent — never reported as complete |
| `binding_conflict` | failed | `Migration::ReferenceMap` reported an immutable-binding / destination conflict |
| `source_row_error` | failed | any other error inside the per-row transaction (nothing persisted) |

Each source row is imported inside its own savepointed transaction: a failed row
leaves nothing behind and is retried cleanly on the next run. Re-running is
idempotent — the second run reports every row as `already_imported` and creates
zero rows.

Operator rehearsal command (against the sanitized snapshot — validates structure,
mapping, idempotency, reference mapping, counts, collision handling and
reconciliation; it does **not** re-prove bcrypt auth, which is already VERIFIED):

```
createdb d8n_date9ja_rehearsal_20260903
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 bin/rails db:schema:load
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_API_HOST=date9ja.rehearsal.local bin/rails brands:install_date9ja
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_SNAPSHOT_DATABASE_URL=postgres://localhost:5432/date9ja_snapshot_sanitized \
  bin/rails date9ja:import_identity
```

### Wave A Slice 3 rehearsal result — VERIFIED (2026-09-03)

Source: `date9ja_snapshot_sanitized`. Schema preflight PASS (v2 signature
`41a653a8d4c25621071fb76e6e59fbc0`, 51 tables, 574 columns). Two full passes into
a throwaway D8N database.

| Reconciliation measure | First pass | Second pass |
|---|---:|---:|
| `source_users_considered` | 288 | 288 |
| dispositions: imported / already_imported / skipped / failed | 280 / 0 / 8 / 0 | 0 / 280 / 8 / 0 |
| eligible | 280 | 280 |
| users / credentials / password_hashes / memberships / profiles created | 280 | 0 |
| identifiers_created | 460 | 0 |
| legacy_references_created | 1580 | 0 |
| anomalies (normalization_collisions, missing_identifiers, malformed_rows, binding_conflicts) | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| reason_codes | `source_soft_deleted: 8` | `source_soft_deleted: 8`, `already_imported: 280` |

Source-census cross-check (authoritative `source_census.sql`): users total 288 =
users kept 280 + users soft-deleted 8. Distinct `lower(email)` 288 and distinct
`public_id` 288 → no identifier collisions, consistent with
`normalization_collisions: 0` / `missing_identifiers: 0`. No unexplained source
rows in either pass. Idempotency demonstrated: the second pass created nothing
and reported every kept row `already_imported`.

**This rehearsal validates structure, mapping, idempotency, reference mapping,
counts, collision handling and reconciliation. It does not re-prove bcrypt auth
(independently VERIFIED, `$2a$` cost 12, `$2a$ 12 PASS`, 2026-09-02). It is NOT
`PARITY_ACCEPTED`, NOT production-ready, NOT cutover-ready** — see the open
deferred decisions in `STATUS.md` (first/last-name mapping, country
normalization, sensitive profile fields, publication/completion semantics,
phone-collision policy, deleted/banned treatment, later migration domains).

## Auth transition check contract (Wave A Step 3 closeout)

`Date9ja::Import::AuthTransitionCheck#to_h` (`domains/date9ja/import/`) is a
deterministic, **PII-free** tally for one auth-transition verification run — the
broad companion to `scripts/date9ja/bcrypt_proof.rb`. It contains counts only: no
email, phone, bcrypt digest, recovery code, reset token, or free text.

| Section | Keys |
|---|---|
| `subjects_considered` | migrated accounts exercised |
| `lifecycles` | `active`, `suspended`, `recovery_required` counts |
| `checks` | per check (`lifecycle_supported`, `resolve`, `login_ok`, `wrong_password_rejected`, `legacy_hash_preserved`, `session_brand_scoped`, `cross_brand_rejected`, `logout_revokes_session`, `login_blocked`, `no_residual_session`, `recovery_unavailable_fails_closed`, `reactivation_roundtrip`, `recovery_roundtrip`, `recovery_revokes_sessions`, `old_password_rejected`, `recovered_password_logs_in`): `{pass, fail, skip}` |
| `failure_reasons` | distinct `check:reason` → count (e.g. `recovery_roundtrip:verify_invalid_code`) |
| `failures` / `all_passed` | total failed checks; boolean |

Every migrated account drives the **real** shared D8N services
(`Identity::PasswordLogin`, `Session`, `SessionAuthenticator`,
`RecoveryRequester`/`RecoveryVerifier`/`PasswordReset`,
`Accounts::DeactivateAccount`, `Identity::AccountReactivation`) — nothing
Date9ja-specific. `recovery_unavailable_fails_closed` covers a migrated account
with no verified channel (unverified email, no verified phone): signed-out reset
must fail closed (no code delivered) while the password still works (ADR 0012).

The operator tool `rake date9ja:verify_auth_transition` (manifest-driven,
secret-scrubbed) has a **throwaway-DB fence** (`Connection.assert_runtime_safe!`
— the accepted disposable-DB contract, refuses before any check) and **manifest
validation** (`AuthTransitionCheck.parse_manifest` rejects an empty manifest and
any lifecycle outside `AuthTransitionCheck::LIFECYCLES`, before any check, error
names the line and bad token only). `AuthTransitionCheck` records
`lifecycle_supported` per subject and a zero-subject run is not a pass.

Evidence: L1 rehearsal (`auth_transition_rehearsal_test.rb`); a **scaled 19-row
synthetic L2 rehearsal** (`auth_transition_l2_rehearsal_test.rb` — import →
reconciliation balance → pre-sign-in idempotency → full journey / 0 failures →
post-recovery re-run never clobbers a member-set password); the operator tool
proven against a compliant throwaway DB incl. its empty-manifest /
unknown-lifecycle / non-approved-DB refusals. The real-seed-account operator L2
(real cost-12 + real plaintexts) stays an operator task, like `bcrypt_proof.rb`.
It runs **after** `date9ja:import_identity` and mutates the accounts it
exercises. Full reference: `AUTH-TRANSITION.md`.

Note on `IdentityImport#credential_completeness` (rerun verdict): a
valid-source-digest credential is complete only with a **supported** bcrypt hash
(`BCRYPT_RE` + `BCrypt::Password.new`) — the verbatim legacy copy, or a valid
replacement the member set via recovery (never a byte match, so a re-run never
clobbers a member-set password). Missing hash → `incomplete_binding`;
unsupported hash → `credential_hash_corrupt` (fail closed). Recovery-required
rows are complete with no hash or with a supported one.

## Profile-photo MEDIA PREFLIGHT contract (Wave A, pass 1 — ADR 0027)

`Date9ja::Import::PhotoImport` emits `Date9ja::Import::PhotoReconciliation#to_h`
— deterministic, PII-free (counts + reason codes + aggregate measures only; no
storage key, filename, checksum value, email, name, or any per-row id). Pass 1
records `Migration::MediaObjectRef` / `Migration::MediaAttachmentRef` only — it
creates no `ProfilePhoto`, copies no bytes, binds no `ReferenceMap`.

**Invariant:** `photos_considered == preflighted + already_preflighted +
owner_not_imported + unavailable + malformed + failed + explicitly_skipped`.
On a clean first run `already_preflighted` is 0; `explicitly_skipped` is always 0
(no documented policy exclusion for photos).

| Disposition | Meaning |
|---|---|
| `preflighted` | blob + attachment recorded; owner profile resolved; fresh this run |
| `already_preflighted` | identical rerun — both refs unchanged |
| `owner_not_imported` | source `Photo.user_id` has no imported Date9ja `profile` `LegacyReference`; refs still recorded for a later pass |
| `unavailable` | `missing_attachment` (no `Photo`/`image` row) or `missing_blob` (attachment points at no blob) |
| `malformed` | `moderation_unmapped` — `moderation_status` outside `{0,1,2}` |
| `failed` | `duplicate_attachment`, `unsupported_content_type`, `checksum_size_inconsistent`, `blob_metadata_drift`, `attachment_drift` — evidence still recorded where a blob exists |
| `explicitly_skipped` | reserved; unused for photos |

| Reason code | Disposition | Meaning |
|---|---|---|
| `owner_not_imported` | owner_not_imported | owner profile not migrated |
| `source_suspended_owner` | (still preflighted) | owner imported but membership/profile suspended — classified, not excluded |
| `missing_attachment` | unavailable | no `record_type='Photo' AND name='image'` row for the Photo |
| `duplicate_attachment` | failed | >1 image attachment for one Photo (different blobs) |
| `missing_blob` | unavailable | attachment `blob_id` has no `active_storage_blobs` row |
| `unsupported_content_type` | failed | blob content type not JPEG/PNG/WebP |
| `checksum_size_inconsistent` | failed | blank checksum or non-positive byte size |
| `moderation_unmapped` | malformed | `moderation_status` not in the authoritative enum |
| `blob_metadata_drift` | failed | rerun sees changed checksum/size/type for the same source blob — fail closed |
| `attachment_drift` | failed | rerun sees the same source attachment id pointing at a different blob/record/name |

**Aggregate measures** (rehearsal acceptance baselines, not runtime truth):
`total_source_photos`, `moderation_pending|approved|rejected`,
`total_primary_rows`, `owners_total`, `owners_with_one_primary`,
`owners_with_zero_primary`, `owners_with_multiple_primary`, `owners_over_six`,
`max_photos_per_owner`, `owners_suspended`, `missing_attachments`,
`duplicate_attachments`, `missing_blobs`, `unsupported_content_types`,
`checksum_size_inconsistencies`, `malformed_moderation_values`,
`owner_not_imported`, `blob_reuse_objects`, `binding_conflicts`.

Primary-photo and >6-photo anomalies are **measured, never normalized** — pass 2
applies the primary-photo mapping and the photo-limit quarantine
(`DECISIONS.md`).

**Census baseline (2026-09-02, `date9ja_snapshot_sanitized`) — acceptance targets, not hard-coded:**
`total_source_photos` 279 · `moderation_pending` 2 · `moderation_approved` 266 ·
`moderation_rejected` 11 · `total_primary_rows` 164 · `active_storage_attachments` 428 ·
`active_storage_blobs` 443. Expected pass-1 result: every one of the 279 rows in
exactly one disposition, `preflighted` + `owner_not_imported` covering the rows
with a valid image attachment + blob, `already_preflighted` 0 on the first run.

Operator rehearsal command (no byte transfer, no `ProfilePhoto`):

```
createdb d8n_date9ja_rehearsal_20260903
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 bin/rails db:schema:load
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_API_HOST=date9ja.rehearsal.local bin/rails brands:install_date9ja
# identity pass first (photo owners must resolve):
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_SNAPSHOT_DATABASE_URL=postgres://localhost:55432/date9ja_snapshot_sanitized \
  bin/rails date9ja:import_identity
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_SNAPSHOT_DATABASE_URL=postgres://localhost:55432/date9ja_snapshot_sanitized \
  bin/rails date9ja:preflight_photos
```

### Pass-1 rehearsal result — VERIFIED (2026-09-03)

Source `date9ja_snapshot_sanitized`, schema preflight PASS, throwaway D8N DB,
run after the identity rehearsal. Two full passes.

| Reconciliation measure | first pass | second pass |
|---|---:|---:|
| `photos_considered` / `balanced` | 279 / true | 279 / true |
| `preflighted` | 276 | 0 |
| `already_preflighted` | 0 | 276 |
| `owner_not_imported` | 3 | 3 |
| `unavailable` / `malformed` / `failed` / `explicitly_skipped` | 0 | 0 |
| `MediaObjectRef` created | 279 | 0 |
| `MediaAttachmentRef` created | 279 | 0 |

Stable measures matched the census baseline: `total_source_photos` 279 ·
moderation 2 / 266 / 11 · `total_primary_rows` 164 · `owners_total` 166 ·
`owners_with_one_primary` 164 · `owners_with_zero_primary` 2 ·
`owners_with_multiple_primary` 0 · `owners_over_six` 0 · `max_photos_per_owner` 6 ·
`owners_suspended` 3 · every anomaly counter 0 · `blob_reuse_objects` 0.

Invariant closed both passes (`279 = 276 + 0 + 3 + 0` first; `279 = 0 + 276 + 3 + 0`
second). Idempotency demonstrated: zero refs created on the second pass. The 3
`owner_not_imported` photos are **not** proven to be the 3 `owners_suspended` —
aggregate output does not establish that.

**Lifecycle:** media preflight foundation VERIFIED · pass-1 implementation
VERIFIED · pass-1 sanitized rehearsal VERIFIED · profile-photo capability
overall **PARTIAL** (bytes/`ProfilePhoto`/processing/delivery/frontend/cutover
outstanding — pass 2, see `MEDIA-TRANSFER.md`). NOT `PARITY_ACCEPTED`.

## Profile-video MEDIA PREFLIGHT contract (Wave A, pass 1 — reuses ADR 0027)

The video analogue of the profile-photo pass-1 contract above. Same generic
`Migration::MediaObjectRef` / `MediaAttachmentRef` / `ReferenceMap` spine; no new
framework. Source: `profile_videos` + `record_type='ProfileVideo' AND
name='video'` attachments/blobs.

**Invariant:** `videos_considered == preflighted + already_preflighted +
owner_not_imported + unavailable + malformed + failed + explicitly_skipped`.

| Disposition | Meaning |
|---|---|
| `preflighted` | blob + `video` attachment recorded; owner profile resolved; fresh this run |
| `already_preflighted` | identical rerun — both refs unchanged |
| `owner_not_imported` | valid media graph; owner profile not (yet) imported — evidence kept for a later pass |
| `unavailable` | `missing_attachment` / `missing_blob` |
| `malformed` | `moderation_unmapped` (moderation enum outside 0/1/2) |
| `failed` | `duplicate_attachment` / `unsupported_content_type` / `checksum_size_inconsistent` / `multiple_videos_per_owner` / `blob_metadata_drift` / `attachment_drift` / `owner_binding_conflict` / `preflight_error` |
| `explicitly_skipped` | reserved — source has no soft-delete column, so always 0 |

**Duration is measured only.** `duration_present/missing/within_limit/over_limit/
invalid` are recorded against `Media::VideoPolicy.max_duration_seconds`; a row is
NEVER rejected for duration in pass 1. Pass 1 cannot prove a legacy video's
actual length — `profile_videos.duration_seconds` was client-supplied and is not
authoritative. **Pass 2 must derive and validate authoritative duration from the
actual media/container** (`Media::VideoProcessor` / `VideoContainerValidator`)
before accepting a migrated video; if the derived duration exceeds the limit,
stop and require the grandfather / trim-reencode / quarantine product decision
(`DECISIONS.md`).

**One video per owner:** the legacy table is 1:1 on `user_id` (UNIQUE index), so
`owners_with_multiple_videos` is structurally 0. The preflight still measures it
and, if ever > 0, fails that owner's rows closed (`multiple_videos_per_owner`)
rather than choosing one.

### Pass-1 rehearsal result — VERIFIED (Codex independent review, 2026-09-03: ACCEPT WITH SMALL FIX — duration wording corrected)

Source `date9ja_snapshot_sanitized`, schema preflight PASS, throwaway D8N DB, run
after the identity rehearsal (`bin/rails date9ja:preflight_videos`). Two passes.

| Reconciliation measure | first pass | second pass |
|---|---:|---:|
| `videos_considered` / `balanced` | 35 / true | 35 / true |
| `preflighted` | 35 | 0 |
| `already_preflighted` | 0 | 35 |
| `owner_not_imported` / `unavailable` / `malformed` / `failed` / `explicitly_skipped` | 0 | 0 |
| `MediaObjectRef` created | 35 | 0 |
| `MediaAttachmentRef` created | 35 | 0 |
| `ProfileVideo` / Active Storage rows created | 0 | 0 |

Stable measures matched the census baseline (measure 63 `profile_videos total` =
35; measure 64 `by moderation_status` = `0:35`): `total_source_videos` 35 ·
moderation 35 pending / 0 approved / 0 rejected · `owners_total` 35 ·
`owners_with_one_video` 35 · `owners_with_multiple_videos` 0 ·
`owners_suspended` 0 · `missing_attachments` / `duplicate_attachments` /
`missing_blobs` / `unsupported_content_types` / `checksum_size_inconsistencies` 0 ·
`blob_reuse_objects` 0 · `max_duration_limit_seconds` 60 · **`duration_missing`
35 / 35** · `duration_present` / `duration_within_limit` / `duration_over_limit`
/ `duration_invalid` all **0**.

Source content-type split (metadata census): 26 `video/mp4` + 9
`video/quicktime` — both in `ProfileVideo::ALLOWED_CONTENT_TYPES`, 0 unsupported.

Invariant closed both passes (`35 = 35 + 0` first; `35 = 0 + 35` second).
Idempotency demonstrated: zero refs, zero destination rows on the second pass.

**Duration finding.** All 35 source rows have a missing `duration_seconds`. No
source row is **known** to exceed the current D8N duration limit; actual duration
is **unproven** for every observed legacy video because Date9ja did not persist
it. This is not a "decision is moot" result — **pass 2 must inspect / derive
authoritative duration from the media bytes / container**, and if the actual
duration exceeds the limit, stop and require the existing grandfather /
trim-reencode / quarantine product decision (`DECISIONS.md`).

**Lifecycle:** video pass-1 implementation VERIFIED (Codex 2026-09-03: ACCEPT
WITH SMALL FIX — documentation correction completed) · sanitized rehearsal
VERIFIED · profile-video capability overall **PARTIAL** (pass-2 byte transfer +
L2 + reconciliation + frontend/cutover outstanding). NOT `PARITY_ACCEPTED`.

## Profile-video PASS 2A BYTE TRANSFER contract (Wave A, ADR 0029) — IMPLEMENTED / SELF_VERIFIED

Pass 2A is an **intermediate** slice. Its maximum success for a video is a
verified, duration-accepted destination ACTIVE STORAGE ORIGINAL BLOB —
lifecycle `SOURCE_ACCEPTED / DESTINATION_ADOPTED`. **It never reports
`transferred`**, which additionally requires Pass 2B (`ProfileVideo` + exact
`ReferenceMap` binding + processing + playback/poster derivative validation).

**Invariant:** `videos_considered == Σ (exactly one terminal disposition)`.

| Disposition | Meaning |
|---|---|
| `destination_adopted` | source verified + authoritative duration ≤ brand limit + deterministic destination original blob uploaded + remote-re-verified, this run |
| `already_destination_adopted` | rerun; the deterministic destination blob already exists and re-verifies — nothing uploaded |
| `owner_not_imported` | no Date9ja `Profile` destination for the owner; bytes not moved |
| `source_unavailable` | source object missing / unreadable / locator key off-grammar / transport refused |
| `source_changed` | source byte-size / MD5 / detected type ≠ `MediaObjectRef` (fail closed) |
| `validation_failed` | not a recognized video (`not_a_video`), unsupported type, or malformed ISO-BMFF container (`malformed_container`) |
| `quarantined` | `duration_unreadable` (ffprobe gave no parseable duration — fail closed) or `duration_over_limit` (authoritative duration > brand limit); OR `moderation_unmapped` / `multiple_videos_per_owner`. **No destination blob, `ProfileVideo`, binding, or job.** |
| `binding_conflict` | destination object/row mismatch — `destination_collision`, `remote_orphan` (never adopted/overwritten/deleted) |
| `destination_failed` | transient D8N upload / infra failure (`missing_preflight`, `transfer_error`) — retryable |
| `explicitly_skipped` | reserved; a documented policy exclusion only |

Aggregate measures (counts only — no key, checksum value, source URL, or per-row
id): `total_source_videos`, `owners_considered`, `owner_not_imported`,
`moderation_{pending,approved,rejected}`, `content_type_{mp4,quicktime}`,
`destination_uploads_created`, `destination_uploads_reused`, `duration_derived`,
`duration_within_limit`, `duration_over_limit`, `duration_unreadable`,
`container_invalid`, `source_changed`, `destination_failures`,
`binding_conflicts`, `destination_remote_orphans`, `destination_collisions`,
`unexplained_failures`, `reviewed_exceptions`.

**Zero-side-effect proof (tests):** Pass 2A creates **0 `ProfileVideo`, 0
`ProfileVideo` Active Storage attachments, 0 `profile_video` `ReferenceMap`
bindings, 0 `Media::ProcessProfileVideoJob`**. A second identical run is a
full classify-only no-op (same deterministic key, same blob, zero uploads).

**Rehearsal status:** L1 automated only (real ffmpeg/ffprobe-generated fixtures,
distinct from source-census evidence). The full 35-video **source-byte**
rehearsal is **deferred to Pass 2C synthetic L2** — the current sanitized
snapshot does not contain the media bodies. No 35/35 source-byte claim is made.

**Lifecycle:** IMPLEMENTED / SELF_VERIFIED (2026-09-04). NOT `VERIFIED`, NOT
`PARITY_ACCEPTED`. PD-2 (grandfather / trim-reencode / quarantine-remove) OPEN.

## Profile-video PASS 2B DOMAIN MIGRATION contract (Wave A, ADR 0029) — IMPLEMENTED / SELF_VERIFIED

Pass 2B completes the DOMAIN side of a successfully adopted Pass-2A video.
`Date9ja::Import::VideoTransfer.call(stage: :domain)` — RESOLVE (idempotent
existing-chain check) → Phase A (2A verify + adopt) → Phase B (short
`LockGuard`-held txn: re-lock `MediaAttachmentRef`, re-resolve owner, re-prove
the deterministic blob, one-live-video invariant, moderation map →
`Profiles::VideoUpload.build_video!` → `Migration::ReferenceMap.bind!`) → Phase C
(`Media::ProcessProfileVideoJob` → `Media::PlaybackDerivative.valid?` playback +
poster → `ready` → existing raw purge). No remote I/O under any DB lock;
`RemoteIOUnderLock` stays fatal.

**Invariant:** `videos_considered == Σ (exactly one terminal disposition)`.
`VideoTransferReconciliation.new(stage: :domain)` — `to_h` reports
`stage: "domain"`, `lifecycle: PROFILE_VIDEO_DOMAIN_MIGRATED (pass 2B) — …`, and
**never emits `transferred`**. Pass 2A remains `DESTINATION_ADOPTED`, not
`transferred`; Pass 2B `ready` is the first point a single video is fully
domain-migrated (ProfileVideo + exact owner + exact original attachment + exact
`ReferenceMap` binding + processing + validated playback + validated poster +
ready + existing raw-purge).

| Disposition | Meaning |
|---|---|
| `ready` | ProfileVideo built + bound this run, processed, playback + poster validated (`Media::PlaybackDerivative`), `processing_ready`, raw purge scheduled |
| `already_ready` | rerun; the full chain re-validated with bounded remote reads — nothing built/processed |
| `owner_not_imported` | no Date9ja `Profile` destination for the owner |
| `source_unavailable` / `source_changed` / `validation_failed` / `quarantined` | as Pass 2A (adoption failed before any domain object) — `quarantined` also covers `duration_over_limit` / `duration_unreadable` / `moderation_unmapped` / `multiple_videos_per_owner` |
| `binding_conflict` | owner `mapping_drift`, `one_video_invariant` (a live ProfileVideo already exists for the profile), `conflicting_profile_video` / `conflicting_binding` / `binding_immutable`, `chain_mismatch`, `playback_invalid` on an existing corrupt ready video, `remote_orphan` / `destination_collision` (Pass-2A blob) — fail closed, never rewrite a binding |
| `processing_failed` | ProfileVideo + binding exist, `Media::ProcessProfileVideoJob` ended `failed` (`processing_job_failed`) or the async drain timed out (`processing_drain_timeout`) |
| `derivative_validation_failed` | job reported `processing_ready` but the actual playback/poster derivatives do not validate (`playback_invalid`) — **never `ready`** |
| `destination_failed` | transient infra / `record_invalid` / `missing_preflight` — retryable |
| `explicitly_skipped` | reserved |

Measures: `profile_videos_created` / `_reused`, `reference_map_bindings_created`
/ `_reused`, `processing_attempts` / `_succeeded` / `_failures`,
`playback_validated`, `poster_validated`, `ready`, `already_ready`,
`originals_purged`, `processing_stale_reclaims`, plus all Pass-2A measures,
`unexplained_failures`, `reviewed_exceptions`.

**Zero-duplicate proof (tests):** two complete runs → same ProfileVideo, same
`ReferenceMap` binding, same playback/poster blobs, 0 duplicate
ProfileVideo/attachment/binding, no reprocessing, no raw recreation after a
correct purge. Interruption windows A–J (ADR 0029 §15) covered or proven
structurally impossible (B, C are one Phase-B transaction).

**Shared runtime hardening:** `20260904120000_add_processing_claim_to_profile_videos`
(claim-token + `metadata` jsonb, mirrors the photo migration — already scoped
into Pass 2B by ADR 0029), `ProfileVideo` claim/sweepable helpers,
`Media::ProcessProfileVideoJob` claim-token concurrency,
`Media::ProfileVideoProcessingSweeper`, `Media::PlaybackDerivative`.

**Rehearsal status:** L1 automated only. Full 35-video synthetic-corpus L2
rehearsal is **Pass 2C** — not done. No 35/35 claim.

**Lifecycle:** IMPLEMENTED / SELF_VERIFIED (2026-09-04). NOT `VERIFIED`, NOT
`PARITY_ACCEPTED`. PD-2 OPEN.

## Profile-video PASS 2C — SYNTHETIC L2 REHEARSAL evidence (ADR 0029) — IMPLEMENTED / SELF_VERIFIED

Full write-up: **[`VIDEO-L2.md`](VIDEO-L2.md)**. Key derived-from-execution results
(35-record self-contained rehearsal, `video_l2_rehearsal_test.rb`):

| Stage | Result |
|---|---|
| Corpus | 35 objects · 26 `video/mp4` + 9 `video/quicktime` · all ≤ 60 s · documentable fingerprint `5fbcc9dac1d7…6433c378` (fixed seed) · byte-identical across two clean generations |
| Pass 1 | 35 considered / 35 preflighted / 35+35 refs / 0 D8N media |
| Pass 2A (`:adopt`) | 35 `destination_adopted` · 35 duration derived + within-limit · 26 mp4 / 9 mov · **0 `ProfileVideo`** · 35 original blobs |
| Pass 2B (`:domain`) | 35 `ready` · 35 PV + bindings + playback + poster validated + originals purged · never `transferred` |
| Destination verifier | one PV + one binding per source · no cross-brand · moderation preserved · bounded remote playback+poster validation |
| Rerun | 35 `already_ready` · zero growth · raw not recreated |
| Interruption | windows A / B-E / C / F-G recovered; B & C structurally impossible; bounded process-kill → deterministic stale-reclaim recovery |
| Adversarial (separate) | over-limit → `quarantined`/`duration_over_limit`; unreadable → `quarantined`/`duration_unreadable`; malformed → `malformed_container`; spoofed → `not_a_video`; drift → `source_changed`; collision/orphan → `binding_conflict` (orphan never adopted); invalid playback rendition / tampered existing derivative → fail closed, **never `ready`**, raw not purged |

**Evidence rule:** 35 legacy `ProfileVideo` records exist (source census fact);
35 synthetic bodies were built for engineering rehearsal (synthetic L2 fact);
the real videos' duration/codec/container are **UNKNOWN** (real-media fact).
Never merged. **PD-2 NOT chosen — real over-limit count UNKNOWN.**

**Feature-boundary review (Codex BLOCKED — fixes applied 2026-09-04):**
Finding 1 (BLOCKER) — `Media::ProcessProfileVideoJob#finalize!` now independently
validates every candidate playback/poster blob's actual remote bytes (new
`Media::PlaybackDerivative.playback_blob_valid?` / `poster_blob_valid?`) OUTSIDE
all DB locks before attaching, with an ABA fingerprint recheck; deterministic
key identity alone is never sufficient; a validation-failing candidate is never
attached, never marks ready, never purges the raw. Finding 4 —
`ProfileVideo#safe_derivative_ready?` requires both derivatives. Findings 2 & 3 —
verifier checks 24 (manifest key path-containment), 27 (full
`active_storage_attachments` byte-identical), 28 (unrelated table row counts).
Retest: 546 runs / 0 failures; Profile Photo regression 125 / 0.

**Lifecycle:** IMPLEMENTED / SELF_VERIFIED. NOT `VERIFIED`, NOT `PARITY_ACCEPTED`.
Independent CODE review ACCEPTED (Codex, with doc fix).

### Operator L2 run — 2026-09-04 (committed `47362bb`)

Full evidence: **[`VIDEO-L2.md`](VIDEO-L2.md) §12**. Sanitized / synthetic L2
only — no production, no real R2, no real video bytes, no L3. `media_v3`
`TEMPLATE`-copied from `date9ja_snapshot_sanitized` (`127.0.0.1:55432`);
throwaway D8N DB `d8n_date9ja_rehearsal_opl2_20260904`.

| Stage | Actual |
|---|---|
| `build_video_media_v3` | 35 objects (26 mp4 / 9 mov) · 35 blob rows patched (`byte_size`/`checksum` only) · fingerprint `e134ed15b8327617929831569b633cc4b03dc0de3bb0b9b12f0101f1eb29e503` (real ids, `DEFAULT_SEED`) · byte-identical across two builds |
| `verify_video_media_v3` | **all checks `ok: true`** (incl. 17 `authorized_changed=35 non_video_change=0`, 27 `changed=0`, 28 row-counts-only, 24 keys safe, 15 deterministic) → `VERIFIED FOR L2` |
| `import_identity` | 280 imported / 8 skipped / 0 failed |
| `preflight_videos` | 35 preflighted · 35+35 refs · moderation 35 pending · `duration_missing` 35/35 |
| `transfer_videos_phase_a` | 35 `destination_adopted` · duration 35 derived + within-limit · 26/9 · 0 quarantined · **0 `ProfileVideo` / 0 binding / 0 processing** |
| `transfer_videos` (`:domain`) | **35 `ready`** · 35 PV + 35 bindings · 35 processing_succeeded · 35 playback + 35 poster validated · 35 originals_purged · never `transferred` |
| Destination verifier | 35 PV all `deliverable?` · exact owner · 0 cross-brand · 35 resolvable bindings · **35/35 playback + 35/35 poster independently re-validated** (bounded remote read + MD5 + container/decode) · 35 distinct playback + 35 distinct poster keys · moderation pending→visible |
| Raw purge | attachment detached synchronously; blob/file GC is the standard async `ActiveStorage::PurgeJob` (drained explicitly here: 105 → 70 blobs, 0 orphans, originals not recreated). `originals_purged` = "scheduled + detached". Not a defect. |
| Rerun | 35 `already_ready`, zero growth, originals not recreated. Minor wart: standalone `transfer_videos_phase_a` after domain+purge re-uploads 35 raw blobs (no domain-object dup). |
| Step 9 — real forked-worker SIGKILL | worker CLAIMed (token `6893cf7a…`) → `kill -9` (shell `wait` rc 137) → durable `processing` + killed token + unchanged `started_at`, no FINALIZE → aged claim stale → operator restart: `processing_stale_reclaims 1`, `ready 1`, new token → validated READY, raw purged, killed token cannot own claim (ABA). Post-recovery rerun: 35 `already_ready`. |

**Real-media boundary unchanged:** synthetic bodies, not user media; real
duration/codec/container **UNKNOWN**; **PD-2 OPEN**.

**Lifecycle after operator L2:** OPERATOR_L2_COMPLETE /
READY_FOR_FINAL_INDEPENDENT_REVIEW. Still **PARTIAL**, still **NOT
`PARITY_ACCEPTED`** — final `VERIFIED` needs independent review of this operator
evidence.

### Pass-2 `service_name` census — RUN 2026-09-03

Metadata-only census (no bytes, no `key`) against `date9ja_snapshot_sanitized`
(`postgresql://127.0.0.1:55432`):

| `service_name` | photo blob count |
|---|---:|
| `cloudflare` | 279 |

No `local`, no `amazon`, no `NULL`, no mixed-service corpus. The Pass-1 gap
(`MediaObjectRef` did not record `service_name`) is closed for this slice. Pass 2
re-asserts the single-service invariant against the final production snapshot at
run time and treats any non-`cloudflare` value as a global blocker.

### Pass-2 L2 synthetic-corpus rehearsal — VERIFIED (Codex independent review, 2026-09-03)

Full 279-row rehearsal against `date9ja_snapshot_sanitized_media_v2` + the
deterministic synthetic corpus (`Date9ja::Snapshot::SyntheticMedia`), read
through `Date9ja::Storage::LocalCorpusReader`. No real R2, no production.

| Measure | First run | Rerun (raw present) | Rerun (raw purged) |
|---|--:|--:|--:|
| `photos_considered` / `balanced` | 279 / true | 279 / true | 279 / true |
| `transferred` | 276 | 0 | 0 |
| `already_transferred` | 0 | 276 | 276 |
| `owner_not_imported` | 3 | 3 | 3 |
| all other dispositions | 0 | 0 | 0 |
| `profile_photos_created` | 276 | 0 | 0 |
| `reference_map_bindings_created` | 276 | 0 | 0 |
| `destination_uploads_created` | 276 | 0 | 0 |
| `processing_succeeded` | 276 | 0 | 0 |
| `binding_conflicts` / `mapping_drift` | 0 / 0 | 0 / 0 | 0 / 0 |
| `unexplained_failures` | 3 | 3 | 3 |
| `cutover_ready` | false | false | false |

Invariant `photos_considered == Σ dispositions` holds every run
(`279 = 276 + 0 + 3` first; `279 = 0 + 276 + 3` reruns). `cutover_ready` is
false only because the 3 known `owner_not_imported` (suspended source owners)
count as `unexplained_failures` — there is no reviewed-exception workflow in this
build. Destination state after the first run: 276 `ProfilePhoto` all
`processing_ready` with a validated deterministic display derivative;
moderation `pending_review`→visible 2 / `approved`→visible 263 /
`rejected`→hidden 11; every owner exactly one `position 0`; per-owner 1–6, no
truncation. 276 detached original blobs purge cleanly and every ProfilePhoto
stays `ready` + `Media::DisplayDerivative.valid?` afterwards. An interrupted run
(two `SIGKILL`s) converged with zero duplicates; one claim-held photo was
reclaimed by `Media::ProfilePhotoProcessingSweeper` after the stale window and
completed on the next run (276/276). Output is PII-free (no storage key,
checksum, email, or per-row id). **Codex independent review 2026-09-03: FINAL
VERDICT ACCEPT — L2 review loop closed. Still NOT `PARITY_ACCEPTED` /
cutover-ready / L3-ready.**

### Pass-2 transfer reconciliation contract

Defined in [`MEDIA-TRANSFER.md`](MEDIA-TRANSFER.md) §15 (design checkpoint —
Revision 4, not implemented; `binding_conflict` covers `remote_orphan`,
`destination_collision`, and `mapping_drift` (destination `ReferenceMap(profile)`
resolution changed after pre-copy — the storage object is never re-keyed), and
every reused destination object is re-verified by a real streamed re-hash).
Terminal dispositions: `transferred`,
`already_transferred`, `owner_not_imported`, `source_unavailable`,
`source_changed`, `validation_failed`, `destination_failed`, `binding_conflict`,
`processing_failed`, `quarantined`, `explicitly_skipped`. Invariant
`photos_considered == Σ dispositions`. Every non-success disposition is
additionally `unexplained_failure` or `reviewed_exception`; cutover requires
`unexplained_failure == 0`. PII-free; no storage locator or checksum value in
output. Baseline: 276 transfer-eligible, 3 `owner_not_imported`,
`profile_photos_created` 276 on a clean first run / 0 on rerun.

```text
Snapshot <id> / run <id>
Users <source> → <target> ✓
Profiles <source> → <target> ✓
Photos <source> → <target> ✓
Likes <source> → <target> ✓
Matches <source> → <target> ✓
Conversations <source> → <target> ✓
Messages <source> → <target> ✓
Blocks <source> → <target> ✓
Reports <source> → <target> ✓
Orphans 0 ✓ / Duplicate identities 0 ✓ / Broken media 0 ✓
Unmapped records 0 or approved exception list
```
