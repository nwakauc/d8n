# Date9ja Profile & Preference Value Mapping Contract

**Authority.** This is the working contract for **Pass 2** of the Date9ja profile &
preference migration: how each legacy `users` value becomes a D8N value. It is
subordinate to `MASTER-PLAN.md` (phase model), `CAPABILITY-PARITY.md` (what must
work) and `DECISIONS.md` (the decision queue); it owns the *value-level* mapping
that none of those carry.

**Lifecycle: Pass 1 — evidence.** This pass adds the census that measures the
source and writes down the mapping problem. It migrates nothing, changes no
importer, and decides no mapping.

**Current lifecycle: IMPLEMENTED / SELF_VERIFIED. NOT VERIFIED. NOT
`PARITY_ACCEPTED`.** An independent Codex review of 2026-09-05 returned CHANGES
REQUIRED; the fix pass of 2026-09-06 closed those findings and is itself awaiting
a narrow independent confirmation. Pass 1 does not reach VERIFIED until that
confirmation lands, and profile/preference parity cannot reach
`PARITY_ACCEPTED` until Pass 2 migrates values.

**Evidence status: CENSUS RUN 2026-09-05, affected measures re-run 2026-09-06.**
Executed against `date9ja_snapshot_sanitized` and, for the PRISTINE-ONLY
sections, against `date9ja_snapshot_tmp`, both on the isolated PG17 instance
(`127.0.0.1:55432`). Schema signature `41a653a8d4c25621071fb76e6e59fbc0` OK on
both (51 tables, 574 columns). Measures 201 and 202 both returned `none`. The
2026-09-06 re-run covered the corrected `body_type` emitter (221, 225) and the
new migration-eligible / onboarding-cohort measures (259, 290-299); both
databases returned identical values for all of them. No value below is invented:
every number is a census output, and every enum meaning is quoted from Date9ja
source code. Row counts are the full 288-row snapshot unless a row says
otherwise.

**Legacy enum meanings are FACT, from `api/app/models/user.rb` in the Date9ja
repository** — they are not inferred from the distributions.

---

## 1. Why this exists

**FACT.** D8N discovery is a *reciprocal, exact-string* match
(`domains/matching/eligibility_scope.rb:39-40`):

```ruby
scope.where(gender: viewer_preference.interested_in)
     .where("profile_preferences.interested_in @> ?::jsonb", [ viewer.gender ].to_json)
```

and participation additionally requires a preference row with all three of
`min_age`, `max_age`, `interested_in` (`domains/matching/profile_participant.rb:10`).

**FACT.** `profiles.gender` is an unconstrained `string(40)` with no catalogue,
enum, or check constraint (`db/schema.rb:928`; `Profiles::FieldCatalog:168-171`).
There is therefore **no vocabulary in D8N to map onto** — the vocabulary is a
decision, and both sides of the reciprocal match must use the same one.

**FACT.** The Date9ja identity importer currently writes `gender` through
untouched — `gender: row["gender"]`
(`domains/date9ja/snapshot/user_record.rb:37`) into
`gender: clamp(record.gender, 40)`
(`domains/date9ja/import/field_mapping.rb:71`) — with no decode, and it creates
**no `ProfilePreference` and no `ProfileOptionSelection` at all**. Its own comment
states the reason: *"This slice has not imported photos, preferences, location, or
option selections"* (`field_mapping.rb:56-58`).

**FACT.** `SANITIZATION-CONTRACT.md:138` and `CAPABILITY-PARITY.md:25` both
classify legacy `users.gender` as an **integer enum code**. Every committed test
supplies the string `"woman"`/`"man"` instead
(e.g. `test/domains/date9ja/import/identity_import_test.rb:40,136-141`), so the
suite cannot detect an integer source.

**UNKNOWN — and the reason this pass exists.** Whether `users.gender` is stored as
an integer or as text, and what its values are. Census measure **200** settles the
type and **210** settles the values. Until that run, the reciprocal-compatibility
verdict in §5 is genuinely open, and nobody should write the transform.

`MIGRATION-MATRIX.md:12` already named this prerequisite for this exact row:
*"map enums/arrays into typed capabilities and stable options … **value census and
approvals**."*

---

## 2. How to produce the evidence

The census is an extension of the existing, VERIFIED
`scripts/date9ja/source_census.sql` — same read-only transaction, same v2
schema-signature guard, same allowlist/`OTHER` output convention. Pass-1 measures
occupy **ord 200-299**.

```
# sanitizer-faithful sections (everything except the two noted below)
psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized \
     -f scripts/date9ja/source_census.sql
```

### Which database each section needs

**FACT**, from `SANITIZATION-CONTRACT.md` §4.1 and `scripts/date9ja/sanitize_snapshot.sql`:

| Section | Ord | Database | Why |
|---|---|---|---|
| `source_types` | 200-202 | either | schema metadata only |
| `profile_values` | 210-224 | sanitized | all PRESERVE columns |
| `preference_validity` | 230-246 | sanitized | all PRESERVE columns |
| `gender_compat` | 250-258 | sanitized | `gender`/`looking_for` are PRESERVE |
| `profile_shape` | 260-261 | **PRISTINE ONLY** | sanitizer rewrites `full_name` → `'Snapshot User ' \|\| id` and `display_name` → `'Snapshot ' \|\| id` (`sanitize_snapshot.sql:129-130`) — against the sanitized copy these measure the *sanitizer* |
| `country` | 265-266 | sanitized | `country_of_residence` is untouched by the sanitizer |
| `publication` | 270-272 | sanitized | all PRESERVE columns |
| `arrays` — `languages_spoken`, `preferred_countries`, `relocation_preferences` | 283-285 | sanitized | untouched by the sanitizer |
| `arrays` — `interests`, `relationship_values`, `dealbreakers` | 280-282 | **PRISTINE ONLY** | sanitizer redacts all three to `'{}'` (`sanitize_snapshot.sql:190-192`) |

The pristine-only rows must be produced inside the isolated restore, with **only
the aggregate census output** leaving that environment. The measures emit counts
and shape classifications exclusively — no name, no element text, no location
string (see §2.1).

### 2.1 Output-safety contract

The Pass-1 emitter is deliberately tighter than "echo the column". A
`value:count` pair is emitted only when **all** of:

1. the column has **≤ 24 distinct non-NULL values** — above that only the distinct
   count and NULL count are emitted, never a value; **and**
2. the value is a plain integer (`^-?[0-9]{1,9}$`), **or**
3. the value is ≤ 40 chars and is **at most four space-separated tokens, each
   starting with a letter** (`^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$`),
   emitted lower-cased with spaces normalised to `_`.

Everything else folds to `OTHER`. The token rule is what separates an enum
*label* from free text: a sentence, a date, an address, a height or a phone
number all have either too many tokens or a token that does not start with a
letter.

**The bounded emitter is only sound for columns whose write path constrains the
value to a vocabulary.** It is *not* sound for free text, because a short
arbitrary phrase — a first name, a short health phrase — can satisfy rule 3.
`users.body_type` is free text (see §3.5), so measure 221 does **not** use the
grammar above: it uses a **closed allowlist** of the six documented historical
suggestions and folds every other value, at any cardinality, to `OTHER`.
Measure 225 reports the distinct count only. Any future free-text column must be
handled the same way; the grammar must never be widened to accommodate one.

Names, free text, coordinates, contact details and every `SENSITIVE_DENYLIST`
column are **never read** by these measures. Names and countries are reduced to
token-shape and classification counts; arrays to cardinality and vocabulary-shape
counts.

This is enforced by test, not by convention:
`test/scripts/date9ja/profile_value_census_test.rb` executes the **committed SQL
text** (read out of the script by `test/support/date9ja_census_sql.rb`) against a
synthetic table and includes a whole-section privacy sweep that fails if any
measure echoes seeded free-text content. That sweep already caught and forced the
tightening of rule 3.

---

## 3. Mapping table

All counts are census output from the 2026-09-05 run. Enum meanings are quoted
from `api/app/models/user.rb` (Date9ja repository) — **source-code fact, not
inference from the distribution.**

Population reference: **288** source rows · 8 soft-deleted · **280
migration-eligible** (census 290 — the importer's own rule: not soft-deleted, not
banned; see §5.3). Rows below are the full 288-row snapshot unless stated.

### 3.0 Storage types — settled (census 200)

`gender`, `looking_for`, `smoking`, `drinking`, `fitness`,
`relationship_intention`, `commitment_timeline`, `wants_children`,
`children_count`, `marital_status`, `education`,
`family_involvement_preference`, `height`, `preferred_age_min`,
`preferred_age_max`, `preferred_distance_km`, `profile_completeness_score` are
all **`integer/int4`**. `body_type`, `country_of_residence`, `full_name`,
`display_name` are `character_varying/varchar`. `interests`,
`relationship_values`, `dealbreakers`, `languages_spoken`,
`preferred_countries`, `relocation_preferences` are `ARRAY/_varchar`.
`profile_hidden` and `willing_to_relocate` are `boolean/bool`.
`onboarding_completed_at` is `timestamp_without_time_zone`.

`users.gender` is therefore **an integer enum, exactly as
`SANITIZATION-CONTRACT.md:138` and `CAPABILITY-PARITY.md:25` classified it.**

### 3.1 Discovery-critical (gender ↔ interested_in)

Legacy: `enum :gender, { man: 0, woman: 1 }` · `enum :looking_for, { man: 0, woman: 1 }`.
**One shared vocabulary of two values**, and Date9ja's own matching scope is
reciprocal in exactly D8N's shape:
`scope :matching_orientation, ->(viewer) { where(gender: viewer.looking_for, looking_for: viewer.gender) }`.

| Source capability | Source type | Observed | D8N destination | Proposed mapping | Status | Decision |
|---|---|---|---|---|---|---|
| `users.gender` | integer enum | `0:197 1:91`, **NULL 0**, distinct 2 | `profiles.gender` (string 40) | `0 → "man"`, `1 → "woman"` | **NEEDS_PRODUCT_DECISION** (naming only) | D-1 |
| `users.looking_for` | integer enum | `0:197 1:91`, **NULL 0**, distinct 2 | `profile_preferences.interested_in` (jsonb list) | `0 → ["man"]`, `1 → ["woman"]` | **NEEDS_PRODUCT_DECISION** (reliability — §5.3) | D-1, **D-9** |
| shared code space | — | intersect 2; gender-not-in-looking_for **0**; looking_for-not-in-gender **0** | both | no expansion rule needed | — | — |
| reciprocal-capable population | — | **280** with both present | — | — | — | — |

**The vocabulary maps without ambiguity.** Both columns are the same two-value
enum, neither is ever NULL, neither carries a code the other lacks, and there is
no "everyone/both" value to expand. `0 → "man"` / `1 → "woman"` is a total,
lossless, order-preserving mapping. Only the D8N *spelling* is open (D-1).

**The stored `looking_for` values are a separate question from the mapping, and
they are doubtful.** Historical Date9ja behaviour — an onboarding form that
pre-filled the control, and a field that did not filter candidates for most of
the product's life — creates substantial doubt about whether the stored values
reliably represent member intent, and D8N *does* enforce the field. The
measured cohort evidence, the source-code facts behind it, and the explicit
separation of FACT from INFERENCE are in **§5.3**; the decision is **D-9**.

### 3.2 Required Date9ja preference fields

| Source capability | Source type | Observed | D8N destination | Proposed mapping | Status | Decision |
|---|---|---|---|---|---|---|
| `users.preferred_age_min` | integer | NULL **222**; below 18: **0**; above 120: **0**; range 18..40 | `min_age` (18..120) | copy verbatim | MECHANICAL where present | — |
| `users.preferred_age_max` | integer | NULL **223**; below 18: **0**; above 120: **0**; range 23..60 | `max_age` (18..120) | copy verbatim | MECHANICAL where present | — |
| age-range ordering | — | inverted: **0**; valid pairs: **65** | `age_range_is_ordered` | — | MECHANICAL | — |
| `users.preferred_distance_km` | integer | **NULL for all 288**; ≤0: 0; >500: 0; valid: **0** | `max_distance_km` (1..500) | **impossible — no source data** | **NO_SOURCE** | **D-10** |
| eligible for a complete `ProfilePreference` | — | **0 of 280** | — | — | — | D-10 |
| lacking ≥1 required input | — | **280 of 280** | — | — | — | D-10 |

**Age data is clean.** Where present it is entirely inside D8N's ceilings: zero
below-18, zero above-120, zero inverted ranges. There is **no invalid-age policy
to decide** — the only issue is absence (222/223 NULL).

**`preferred_distance_km` has no source data whatsoever.** Every one of the 288
rows is NULL, so `max_distance_km` — a **required** Date9ja preference field —
cannot be migrated for anybody. This is the same class of problem as
`meeting_pace` (§4): a required D8N field with no legacy source. It is why the
eligible cohort is **0**.

### 3.3 Required Date9ja profile scalars not yet imported

Legacy: `enum :smoking/:drinking/:fitness, { never: 0, occasionally: 1, regularly: 2 }`.

| Source capability | Source type | Observed | D8N destination | Proposed mapping | Status | Decision |
|---|---|---|---|---|---|---|
| `users.smoking` | integer enum | `0:82 1:4 2:1` **NULL:201** | `profiles.smoking` (string 32) | `never / occasionally / regularly` | **NEEDS_PRODUCT_DECISION** (spelling) | D-3 |
| `users.drinking` | integer enum | `0:72 1:98 2:5` **NULL:113** | `profiles.drinking` (string 32) | `never / occasionally / regularly` | **NEEDS_PRODUCT_DECISION** (spelling) | D-3 |
| `users.country_of_residence` | varchar | NULL 0 · blank 0 · **iso2 0** · name_like **288** · distinct **23**; allowlist covers 268 (`nigeria:201 south_africa:35 united_kingdom:15 united_states:8 ghana:6 canada:2 uae:1`), **OTHER:20** | `profiles.country_code` (ISO alpha-2) | needs a 23-value name→ISO table | **NEEDS_ENGINEERING_CONTRACT** | E-1 |
| `users.full_name` | varchar | 1-token **26** · 2-token **250** · 3+-token **12** · null/blank 0 *(pristine)* | `first_name` + `last_name` | — | **NEEDS_PRODUCT_DECISION** | D-4 |
| `users.display_name` | varchar | 1-token **277** · 2-token 11 *(pristine)* | `profiles.display_name` | already imported, clamped to 80 | MECHANICAL | — |

**`smoking` and `drinking` are `NULL` for 201 and 113 members respectively**, yet
both are **required** Date9ja profile fields — so even a perfect vocabulary
mapping leaves those members unpublishable (D-11).

**No country is already ISO-2.** All 288 are spelled-out names across 23 distinct
values, so the importer's current `\A[A-Z]{2}\z` filter drops **100%** of them.

### 3.4 Required Date9ja option groups

Legacy: `relationship_intention { marriage: 0, courtship: 1, serious_relationship: 2, dating: 3, friendship: 4, activity_partner: 5 }` ·
`commitment_timeline { asap: 0, within_1_year: 1, one_to_two_years: 2, two_to_three_years: 3, not_sure: 4 }` ·
`wants_children { yes: 0, no: 1, open: 2 }` ·
**`children_count { none: 0, one: 1, two: 2, three_or_more: 3 }` — an ENUM, not a literal count.**

| Source capability | Observed | D8N destination | Proposed mapping | Status | Decision |
|---|---|---|---|---|---|
| `users.relationship_intention` | `0:108 1:27 2:70 3:7 4:1` **NULL:75** (no code 5 present) | group `relationship_intent` (5 D8N values) | 5 source values ↔ 5 differently-named D8N values; `courtship`/`activity_partner` have no D8N counterpart, `open_to_dating`/`still_figuring_it_out` have no source counterpart | **NEEDS_PRODUCT_DECISION** | D-5 |
| `users.commitment_timeline` | `0:25 1:46 2:12 3:11 4:116` **NULL:78** | **no D8N group** | — | **NEEDS_PRODUCT_DECISION** | D-5 |
| `users.wants_children` | `0:143 1:20 2:45` **NULL:80** | group `wants_children` | `yes / no / open` | **NEEDS_PRODUCT_DECISION** (spelling) | D-6 |
| `users.children_count` | `0:143 1:4 2:2` **NULL:139** (no code 3 present) | group `has_children` and/or `profiles.children_count` (integer 0..30) | **`3` means `three_or_more`, not the number 3** — a naive integer copy is wrong | **NEEDS_PRODUCT_DECISION** | D-6 |
| `meeting_pace` | **no source column** (§4) | group `meeting_pace` — **required** | none possible | **NO_SOURCE** | D-7 |

### 3.5 Enabled but not required

| Source capability | Observed | D8N destination | Status | Decision |
|---|---|---|---|---|
| `users.fitness` | `0:24 1:42 2:23` NULL:199 | `profiles.fitness` | NEEDS_PRODUCT_DECISION | D-3 |
| `users.education` (`secondary/ond_hnd/bsc/msc/phd`) | `0:21 1:15 2:30 3:13 4:10` NULL:199 | group `education_level` | NEEDS_PRODUCT_DECISION | D-6 |
| `users.body_type` | **free text, not an enum** (see below). Allowlisted buckets (census 221): `slim:63 regular:56 athletic:23 muscular:16 curvy:12 plus_size:11` · `OTHER:13` · `NULL:94`; **18 distinct non-blank values** (census 225), so 12 distinct spellings sit outside the six suggestions | `profiles.body_type` (string 80) | NEEDS_PRODUCT_DECISION | D-3 |
| `users.height` | NULL:100 present:188 **min:1 max:588** | `profiles.height_cm` | **INVALID_DATA_POLICY_REQUIRED** — 1 and 588 are not plausible heights in any unit | E-2 |
| `users.marital_status` (`single/divorced/widowed`) | `0:91 1:5 2:4` NULL:188 | **no D8N capability** | DEFERRED | — |
| `users.family_involvement_preference` (`low/medium/high`) | `0:45 1:122 2:38` NULL:83 | **no D8N capability** | DEFERRED | — |
| `users.willing_to_relocate` | `true:153 false:56` NULL:79 | **no D8N capability** | DEFERRED | — |
| `users.languages_spoken` | empty:200 nonempty:88 max_card:5 distinct:27 label-shaped:**25** | `profiles.languages` (structured) | NEEDS_ENGINEERING_CONTRACT | E-3 |
| `users.preferred_countries` | empty:236 nonempty:52 max_card:9 distinct:27 label-shaped:**27** | no D8N capability | DEFERRED | — |
| `users.relocation_preferences` | empty:115 nonempty:**173** max_card:5 distinct:18 label-shaped:17 | no D8N capability | DEFERRED | — |
| `users.interests` *(pristine)* | empty:208 nonempty:80 max_card:8 distinct:**68** label-shaped:**60** sentence-shaped:1 | group `interests` (31 curated codes) | NEEDS_ENGINEERING_CONTRACT | E-4 |
| `users.relationship_values` *(pristine)* | empty:242 nonempty:46 max_card:6 distinct:**34** label-shaped:**33** sentence-shaped:0 | no D8N capability | NEEDS_ENGINEERING_CONTRACT | E-4 |
| `users.dealbreakers` *(pristine)* | empty:239 nonempty:49 max_card:7 distinct:**33** label-shaped:**26** sentence-shaped:1 | no D8N capability | NEEDS_ENGINEERING_CONTRACT | E-4 |

**`users.body_type` is user-entered free text — FACT, from Date9ja source.** The
onboarding control is a plain `<input>` with a suggestion `datalist`
(`web/src/pages/AuthPages.js:1520-1528`), and the API's `normalize_body_type`
canonicalises a handful of spellings and otherwise **stores the raw value**
(`api/app/controllers/api/v1/me_controller.rb:84-99`, whose own test
`api/test/requests/api/v1/me_update_test.rb:21-25` asserts that
`"not-a-real-body-type"` round-trips unchanged). The census therefore measures it
with a **closed allowlist** of the six documented historical suggestions — the
same six in all three places the product defines them (`me_controller.rb:87-97`,
`web/src/pages/ProfilePage.js:61-68`, `AuthPages.js:1521-1528`) — and folds
everything else to `OTHER`. **No non-allowlisted `body_type` value has been
emitted, recorded or retained anywhere in this programme.**

**The three REVIEW_REQUIRED arrays are controlled-vocabulary-*shaped*, not free
prose**: 60/68, 33/34 and 26/33 distinct elements are short letter-initial labels,
with at most one sentence-shaped element each. They are mappable in principle;
whether the vocabularies align with D8N's 31 curated interest codes is E-4.

> **This shape evidence does NOT establish that the three arrays are safe to
> preserve in a shareable sanitized snapshot, and must not be read that way.**
> "Label-shaped" and "not personal" are different properties: a first name, a
> place, a religious community or a health word is also short and letter-initial,
> and the aggregate counts above deliberately cannot tell the difference because
> they never look at an element. Their `SANITIZATION-CONTRACT.md` classification
> is **unchanged by this pass** and stays REVIEW_REQUIRED / REDACT until a
> separate, explicitly approved privacy-safe vocabulary review is run (E-5).

### 3.6 Publication inputs

| Source capability | Observed | D8N destination | Status | Decision |
|---|---|---|---|---|
| `users.profile_hidden` | true **8** / false 280 | `profiles.visibility` | NEEDS_PRODUCT_DECISION | D-8 |
| `users.onboarding_completed_at` | NOT NULL **116** | no direct destination | NEEDS_PRODUCT_DECISION | D-8 |
| cohorts (`hidden` × `onboarded`) | `visible/not_onboarded:166` · `visible/onboarded:114` · `hidden/not_onboarded:6` · `hidden/onboarded:2` | — | — | D-8 |
| `users.profile_completeness_score` | **`000:288` — zero for every row** | none; D8N recomputes | MECHANICAL — do not migrate | — |
| candidate publish cohort | **109** (live + onboarded + not hidden) | `Profiles::Publication` | upper bound only | D-8 |

## 4. Meeting-pace source verdict

**NO LEGACY SOURCE FOUND — confirmed by operator evidence as well as repository
evidence.**

Repository evidence (unchanged from the Pass-1 charter):

1. Absent from `SNAPSHOT-RUNBOOK.md` §4's preserve / redact / drop / sensitive lists.
2. Absent from `UserSource::SELECTED_COLUMNS` and both `FieldMapping` constants.
3. A search of `docs/migrations/date9ja-to-d8n/`, `scripts/date9ja/` and
   `domains/date9ja/` for `meeting_pace`, `pace`, `chat_first`,
   `video_call_first`, `meet_soon` and `first_date` returns one hit —
   `BRAND-CONTRACT.md:21`, describing the **D8N-side** group.
4. `api/app/models/user.rb` in the Date9ja repository declares 16 enums; none is
   a meeting-pace concept. The nearest neighbour, `commitment_timeline`
   (`asap / within_1_year / one_to_two_years / two_to_three_years / not_sure`),
   is about *relationship* timeline, not how soon two people meet.

**Operator evidence (2026-09-05):** census measure **202** — every `users` column
present in the real source but not classified by the importer, the sensitive
denylist, this census, or the runbook — returned **`none`** against both
`date9ja_snapshot_sanitized` and `date9ja_snapshot_tmp`. There is no unclassified
column of any kind in the source, so there is no overlooked meeting-pace field.

`meeting_pace` is nonetheless a **required** Date9ja completion group, so with no
source it blocks publication for the entire migrated population. That is D-7. No
fallback is chosen here.

**A second field is now in the same position:** `preferred_distance_km` is a
**required** Date9ja preference field and is **NULL for all 288 source rows**.
It is tracked separately as D-10 because, unlike `meeting_pace`, the column
exists — it was simply never populated.

## 5. Gender / looking_for compatibility verdict

### 5.1 Can the two columns share one canonical reciprocal vocabulary? **YES, unambiguously.**

| Test | Result |
|---|---|
| `gender` storage type | `integer/int4` |
| `looking_for` storage type | `integer/int4` |
| Legacy definitions | `enum :gender, { man: 0, woman: 1 }` and `enum :looking_for, { man: 0, woman: 1 }` — **the same two-value vocabulary** |
| Distinct values | 2 and 2 |
| Values in both | 2 |
| `gender` codes absent from `looking_for` | **0** |
| `looking_for` codes absent from `gender` | **0** |
| NULLs | **0** and **0** |
| "everyone/both" code needing expansion | none exists |
| Legacy matching semantics | `where(gender: viewer.looking_for, looking_for: viewer.gender)` — **the same reciprocal shape as D8N's `EligibilityScope`** |

`0 → "man"`, `1 → "woman"` is total, lossless and order-preserving on both
columns. Only the D8N spelling is undecided (D-1), and D8N's own de-facto
convention is already `man` / `woman`
(`docs/api/openapi.yaml` gender-split buckets; the demo seeds).

### 5.2 Does the current importer produce a D8N-compatible `Profile.gender`? **NO.**

**FACT, now proven rather than suspected.** `users.gender` is `integer/int4`, and
`FieldMapping.profile_attributes` does `gender: clamp(record.gender, 40)` over the
raw value (`field_mapping.rb:71`, `user_record.rb:37`) with no decode. The
importer therefore writes the **strings `"0"` and `"1"`** into `profiles.gender`.

`Matching::EligibilityScope` compares `profiles.gender` to the strings inside
`profile_preferences.interested_in`. `"0"` matches nothing any human-readable
vocabulary would contain, so **a decode step is mandatory in Pass 2.**

The 280 profiles created by the VERIFIED identity-import rehearsal carry `"0"` /
`"1"` in `profiles.gender` today. That rehearsal remains valid for what it
asserted (row counts, idempotency, reconciliation balance) — it never asserted
value semantics.

Independently of gender, **no `ProfilePreference` row exists for any migrated
member**, so `Matching::ProfileParticipant` excludes all 280 from matching
regardless. Both halves must be fixed in Pass 2.

**The importer was not changed in this pass.**

### 5.3 How reliable are the stored `looking_for` values? **Doubtful — a policy decision is required.**

§5.1 settles that the two columns *map* unambiguously. It says nothing about
whether the stored values represent what members actually want. This section
separates what is measured from what is inferred.

**Population — taken from the importer, not invented for this evidence.**
`Date9ja::Import::IdentityImport#import_one`
(`domains/date9ja/import/identity_import.rb:63-64`) skips a source row when
`record.soft_deleted?` or `record.banned?`, and `Date9ja::Snapshot::UserRecord`
(`domains/date9ja/snapshot/user_record.rb:48,50`) defines those as
`deleted_at.present?` / `banned_at.present?`. The **migration-eligible
population** is therefore exactly `deleted_at IS NULL AND banned_at IS NULL`, the
same predicate measures 245/246 already use. The importer applies no seed or
admin exclusion, so neither does this evidence. Onboarding is **not** an
eligibility filter — it partitions the eligible population, because the two
cohorts reached the column through different write paths.

**FACT — what the database contains** (census 258, 259, 290-299; identical on the
sanitized copy and the pristine restore):

| Measure | Value |
|---|---|
| 258 — all-source `gender` × `looking_for` | `g0/l0:108 g0/l1:89 g1/l0:89 g1/l1:2` (288) |
| 290 — migration-eligible population | **280** |
| 259 — eligible `gender` × `looking_for` | `g0/l0:105 g0/l1:84 g1/l0:89 g1/l1:2` (280) |
| 291 — eligible **and onboarded** | **112** |
| 292 / 293 / 294 — same code / differing code / indeterminate | **79** / 33 / 0 |
| 295 — eligible **and never onboarded** | **168** |
| 296 / 297 / 298 — same code / differing code / indeterminate | **28** / 140 / 0 |
| 299 — partition proof | `eligible:280 onboarded:112=79+33+0 not_onboarded:168=28+140+0 **OK**` |

So **70.5 %** of the onboarded cohort (79/112) stores a `looking_for` equal to
its own `gender`, against **16.7 %** of the never-onboarded cohort (28/168).
There are no NULLs on either side, so no row is unclassified.

**FACT — what historical Date9ja code did.** Two independent behaviours, both
read directly from the Date9ja repository:

1. The onboarding form **pre-filled the control with a non-empty default** rather
   than leaving it unanswered — `web/src/pages/AuthPages.js:900`:
   `looking_for: user.looking_for || 'man'`.
2. `looking_for` **did not filter candidates** for most of the product's life.
   The `matching_orientation` scope that consumes it
   (`api/app/models/user.rb`, and the Phase 2.4 comment at lines 458-460)
   post-dates the data, so a wrong value had no visible consequence for the
   member who set it.

**INFERENCE — why those facts make the values doubtful.** A control that submits
a value the member never chose, on a field whose value the member could not
observe having any effect, is a control that can accumulate values reflecting the
default rather than the intent. The cohort split is consistent with that
mechanism — the cohort that passed through the pre-filled form is far more likely
to store its own gender than the cohort that never did — and the direction of the
difference matches the specific default the form supplied. **This is an
inference from mechanism plus distribution, not a measurement of intent.** The
census cannot establish that any individual stored value is wrong: some members
genuinely do seek their own gender, and the source contains no record of which
control state produced which value.

**PRODUCT DECISION — D-9, RESOLVED 2026-09-06: migrate every value exactly as
stored.**

Two reasons, both from Uchechi, and both binding on every later slice:

1. **Some Date9ja members are gay.** A high man→man count is not a symptom; it
   is members telling the product who they are interested in. A same-gender
   `looking_for` is a correct answer, and treating it as an error — flagging it,
   quarantining it, re-asking it, or "correcting" it — would be the migration
   overruling real people about their own orientation.
2. **Migration does not change anything a member has already chosen.** A stored
   answer is the member's, not ours to revise on the strength of an aggregate.

The cohort figures above stay on the record as *history* — they explain why the
distribution looks as it does, and they would matter if Date9ja ever wanted to
re-prompt members inside the product. They are **not** evidence about any
individual member, and the census could never have made them so. `interested_in`
is therefore written verbatim from `looking_for`, and
`Date9ja::Import::ValueMapping` gives same-code pairs no special status anywhere:
no flag, no reason code, no quarantine. A regression test asserts a migrated
same-gender pair is discoverable on exactly the same terms as any other.

## 6. Decision register

Regenerated from the 2026-09-05 census and revised by the 2026-09-06 review-fix
pass. The pre-run draft is superseded: evidence **closed** the invalid-age and
invalid-distance rows (neither condition exists) and **opened** D-9
(`looking_for` reliability), D-10 (absent distance) and D-11 (absent required
lifestyle values). The 2026-09-06 pass rewrote E-5 and added E-6.

**These are the current identifiers. There is no D-2** — that draft row was one
of the two the evidence closed, and nothing renumbered around it.

| Register | Current rows |
|---|---|
| Engineering contract (§6.1) | **E-1 … E-6** |
| Product / migration (§6.2) | **D-1, D-3, D-4, D-5, D-6, D-7, D-8, D-9, D-10, D-11, D-12** |

Affected counts are real census outputs.

A "recommended default" appears only where the evidence shows one option is
strictly non-lossy and the others discard or fabricate member data. **No
decision is made here.**

### 6.1 Engineering-contract decisions

| # | Decision | Affected | Why required | Options | Consequence | Recommended default |
|---|---|---:|---|---|---|---|
| **E-1** | Legacy country **name** → `profiles.country_code` (ISO alpha-2) | **288** (100%) | No source value is already ISO-2, so the importer's `\A[A-Z]{2}\z` filter drops every one; `country_code` is a **required** field, so today no migrated profile can complete | (a) build a 23-value name→ISO table; (b) leave NULL and re-ask each member; (c) relax the requirement | (a) 23 rows of mapping, nothing lost — 268/288 already fall in a 7-country allowlist, 20 need review; (b) 288 members blocked until they answer; (c) changes the Date9ja product | **(a)** — the vocabulary is 23 values, closed and inspectable; (b) and (c) both lose data or change the product for a purely mechanical gap |
| **E-2** | `users.height` data policy | 188 present | Observed range is **1 … 588** — not plausible in cm *or* inches, so the column carries junk alongside real values | (a) migrate only values inside a plausible band and drop the rest; (b) migrate verbatim; (c) do not migrate height | (a) needs an agreed band; (b) imports absurd heights into a live profile field; (c) loses a non-required field entirely | none — a band is a judgement about real member data |
| **E-3** | Flat `languages_spoken` → structured `profiles.languages` (`{code, proficiency, primary}`) | 88 | ADR 0017 deprecates the flat column, so the flat form is not a legitimate target; source has no proficiency or primary signal | (a) map code only, leave proficiency/primary null; (b) defer | (a) preserves the data with a documented gap; (b) loses 88 members' languages | **(a)** — non-lossy; the missing sub-fields were never collected |
| **E-4** | Whether `interests` / `relationship_values` / `dealbreakers` vocabularies align with D8N's 31 curated interest codes | 80 / 46 / 49 | All three are controlled-vocabulary-**shaped** (60/68, 33/34, 26/33 label-shaped elements; ≤1 sentence-shaped each), so they are mappable in principle — but only `interests` has a D8N destination | (a) map `interests` to the curated codes, unmapped → dropped or quarantined; (b) widen the D8N catalogue; (c) defer all three | (a) partial loss depending on overlap; (b) enlarges a shared catalogue for one brand; (c) loses all three | none until the element vocabularies are compared |
| **E-5** | How to conduct the privacy review that `SANITIZATION-CONTRACT.md` requires before `interests` / `relationship_values` / `dealbreakers` can be reclassified | 80 / 46 / 49 | The contract marks all three **REVIEW_REQUIRED**. Pass 1 measured their *shape* only, and shape is **not** evidence of safety: a first name, a place, a community or a health word is also short and letter-initial. The census deliberately never reads an element, so it cannot answer the question the contract is waiting on | (a) run a separately-approved privacy-safe vocabulary review inside the isolated environment (e.g. compare elements against a closed allowlist and emit only allowlist-hit / miss counts, exactly as measure 221 does for `body_type`); (b) leave all three REVIEW_REQUIRED / REDACT indefinitely | (a) can close the classification question without any element leaving the environment; (b) every future rehearsal needs pristine access for these columns | none — **Pass 1 does not recommend reclassification, and did not change the classification.** Deciding *how* to look at the values is itself a privacy decision |
| **E-6** | `SANITIZATION-CONTRACT.md` justifies PRESERVE-ing `users.body_type` on the grounds that it is "a small enum" (line 146) | 194 present | **That justification is factually wrong**: `body_type` is a free-text input (§3.5), and 18 distinct spellings are present against six documented suggestions. The *classification* may still be right, but the stated reason for it no longer supports it | (a) re-examine the PRESERVE classification against the correct facts and restate the justification; (b) restrict the column in the sanitizer | (a) may confirm PRESERVE with a sound reason, or change it; (b) costs a snapshot-fidelity guarantee that other measures rely on | none — **Pass 1 deliberately did not change the sanitizer contract.** This row records the contradiction so it is reviewed rather than inherited |

### 6.2 Product / migration-policy decisions — **Uchechi**

| # | Decision | Affected | Why required | Options | Consequence | Recommended default |
|---|---|---:|---|---|---|---|
| **D-1** | The D8N spelling of the gender vocabulary | 288 | `profiles.gender` has no catalogue; both sides of the reciprocal match must use identical strings | (a) `man` / `woman`; (b) other strings | (a) matches D8N's existing de-facto convention (openapi gender buckets, demo seeds); (b) needs every brand's data aligned | **RESOLVED 2026-09-06 — (a) `man` / `woman`.** Implemented in `Date9ja::Import::ValueMapping::GENDER` / `INTERESTED_IN`; both sides of the reciprocal match are asserted to use one vocabulary by test. |
| **D-9** | **Whether to migrate `looking_for` values as stored** | **280** eligible | Historical Date9ja behaviour (a pre-filled onboarding control, `AuthPages.js:900`; a field that did not filter candidates until Phase 2.4, `user.rb:458-460`) skews the *distribution*: same-code rate is **70.5 %** onboarded (79/112) vs **16.7 %** never-onboarded (28/168). D8N enforces the field. §5.3 | (a) migrate verbatim; (b) migrate only differing values, re-ask the rest; (c) re-ask everyone; (d) seed both codes | (a) highest fidelity, zero member friction; (b)/(c)/(d) each discard or override answers members actually gave | **RESOLVED 2026-09-06 — (a) migrate every value exactly as stored.** Two reasons from Uchechi: **some members are gay**, so a same-gender preference is an orientation and a correct answer — it must never be treated as an error, a defect, or a thing to "fix"; and **migration does not change anything a member has already chosen**. The skewed distribution stays recorded as history, but it is not evidence about any individual, and the importer gives same-code values no special status: no flag, no quarantine, no re-ask. |
| **D-10** | `preferred_distance_km` is **required** by the Date9ja catalogue and **NULL for all 288** | **280** (everyone) | Nothing can be migrated; this alone made the eligible-for-complete-preference cohort **0** | (a) drop `max_distance_km` from `REQUIRED_PREFERENCE_FIELDS`; (b) set a documented default; (c) keep required and re-ask | (a) changes the Date9ja product contract; (b) fabricates a preference the member never expressed; (c) blocks all 280 until answered | **RESOLVED 2026-09-06 — (a) relax.** `max_distance_km` stays **enabled** (still collected, still offered) but is no longer a publication gate. The importer never writes it. Side benefit: because neither side sets a distance, migrated members remain mutually discoverable before any location data exists (`EligibilityScope#without_viewer_location`). |
| **D-7** | `meeting_pace` is **required** with **no legacy source** (§4) | **280** (everyone) | Same shape as D-10 but the column never existed | (a) remove from `REQUIRED_OPTION_GROUPS`; (b) keep required and prompt on first login | (a) changes the Date9ja product; (b) blocks publication until answered | **RESOLVED 2026-09-06 — (a) relax.** The group is still installed and offered; it is simply not a publication gate. Nothing is ever fabricated for it, and every run records `meeting_pace_no_source` per member so the absence stays visible. |
| **D-11** | `smoking` (NULL for **201**) and `drinking` (NULL for **113**) are **required** profile fields | 201 / 113 | Even a perfect vocabulary mapping leaves these members incomplete | (a) relax to optional; (b) keep required and prompt | (a) changes the product; (b) blocks 201 members | **RESOLVED 2026-09-06 — (a) relax.** Both remain **enabled**, in their original position in the brand's enabled contract; only the REQUIRED list changed. |
| **D-3** | D8N spelling for `smoking` / `drinking` / `fitness` (`never/occasionally/regularly`) and what to do with free-text `body_type` | 87 / 175 / 89 / 194 | Destination columns are free strings; the legacy side is a clean 3-value enum — except `body_type`, which is **user-entered free text** (§3.5): 181 of 194 present values fall in the six documented suggestions and **13 do not**, across 18 distinct spellings | (a) carry the legacy labels verbatim; (b) rename; **body_type**: (i) migrate verbatim, (ii) map to a catalogue, (iii) drop | (a) zero-loss and self-documenting; body_type (i) carries compound self-descriptions into a live field, (ii) loses nuance, (iii) loses 194 members' answers | **(a)** for the three enums — they are already clean, human-readable labels. **body_type: none** — free text needs a real product call |
| **D-5** | `relationship_intention` → `relationship_intent`, and the fate of `commitment_timeline` | 213 / 210 | The D8N 5-value list was newly authored and does **not** correspond: `courtship` and `activity_partner` have no D8N counterpart; `open_to_dating` and `still_figuring_it_out` have no source counterpart. `commitment_timeline` has no D8N group at all | (a) extend the D8N list to cover the legacy values; (b) fold legacy values into the nearest D8N value; (c) drop the unmatched ones | (a) preserves every answer; (b) silently rewrites 34 members' stated intent; (c) loses them | **STILL OPEN.** The importer ships the three unambiguous codes (`marriage`, `serious_relationship`→`long_term_relationship`, `friendship`) and **fails closed** on `courtship` (27), `dating` (7) and `activity_partner` (1), recording `relationship_intent_unmapped`. Nothing is folded onto a near-enough option. Resolving D-5 makes those members complete on a re-run, which fills the gap without touching anyone who already has an answer. |
| **D-6** | Family/education vocabularies: `wants_children` (`yes/no/open`), `children_count`, `education` | 208 / 149 / 89 | **`children_count` is an enum, not a number** — `3` means `three_or_more` | (a) map `children_count` to the `has_children` group as a category; (b) copy 0/1/2 as integers and treat 3 specially; (c) defer | (a) preserves meaning, loses the exact number; (b) needs a rule for `three_or_more` | **PARTLY RESOLVED 2026-09-06.** `children_count` → **`has_children`** (a): every legacy code answers D8N's yes/no question exactly — `none` is an explicitly chosen value distinct from NULL, so it is a real "no", and the enum/integer trap disappears because nothing is copied into an integer column. `wants_children` `yes`/`no` map exactly. **Legacy `open` (45 members) is STILL OPEN** — D8N offers `maybe` and `open_to_partner_with_children`, which mean different things, and the legacy label does not say which; it fails closed. `education` is out of this slice. |
| **D-12** | `min_age` / `max_age` are **required** preference fields and absent for **217 of 280** | **217** | Discovered by the 2026-09-06 destination rehearsal, not by the census: with gender and distance solved, the age range is now the **only** thing keeping most migrated members out of matching. `Matching::ProfileParticipant` requires both bounds, so only **68** members participate and **33** have any candidate. Source shape: 216 both-NULL, 1 half-answered, 63 complete, **0 invalid, 0 inverted** | (a) relax `min_age`/`max_age` the way D-10 relaxed distance; (b) treat a missing range as "no age filter" and store the full allowed band (18-120); (c) keep required and prompt on first login | (a) members match without an age filter, but D8N's reciprocal age join still needs *both* sides to have a range, so this alone may not open matching; (b) is not obviously fabrication — a member who set no filter arguably meant "no filter" — but it does write a value they never typed; (c) blocks 217 members until they answer | none — (b) is defensible but still writes member data, and that has always been your call |
| **D-8** | Publication policy for migrated members | 109 candidates | Cohorts: `visible/onboarded:114`, `visible/not_onboarded:166`, `hidden/onboarded:2`, `hidden/not_onboarded:6`. Note `profile_completeness_score` is **0 for all 288**, so it carries no signal | (a) auto-publish anyone who completes `Profiles::Completion`; (b) start everyone hidden, publish on first login | (a) members reappear as they were; (b) nobody is exposed unexpectedly, but the brand looks empty at cutover | none — interacts with the already-RESOLVED photo-quarantine publication rule |
| **D-4** | `full_name` → `first_name` / `last_name` | 288 | Both are **required** identity fields; the importer sets neither. Shape: **250** two-token, **26** one-token, **12** three-or-more | (a) split on first whitespace; (b) `first_name` only, leave `last_name` null; (c) ask on first login; (d) relax the requirement | (a) works for 250, leaves 26 with no last name and guesses wrong on some of the 12; (b) fails the required-field check; (c) safest for correctness, costs a prompt; (d) changes the product | none — any split rule guesses at real people's names, and 38 of 288 do not fit the two-token assumption |

### 6.3 Decisions the evidence CLOSED

| Draft row | Outcome |
|---|---|
| Invalid **age** policy (below 18 / above 120 / inverted) | **Not needed.** Zero rows violate any age constraint; ages present are 18-40 / 23-60. Valid pairs migrate verbatim. |
| Invalid **distance** policy (≤0 / >500) | **Not needed** in that form — zero invalid values exist because **no** values exist. Superseded by D-10 (absence, not invalidity). |
| Whether `gender`/`looking_for` share one vocabulary | **Answered: yes, unambiguously** (§5.1). Not a decision. |
| Whether the REVIEW_REQUIRED arrays are *shaped* like free prose | **Answered: they are controlled-vocabulary-shaped**, not prose — 60/68, 33/34, 26/33 label-shaped elements. This closes the **shape** question and feeds E-4 (vocabulary alignment). It does **not** close the sanitizer-classification question, which needs a privacy review of the values themselves (E-5) and stays open. |
| `profile_completeness_score` handling | **Answered: do not migrate.** It is 0 for all 288 rows — it carries no information. |

### 6.4 Relationship to the existing decision queue

These rows are scoped to non-sensitive profile/preference **values**. They are
independent of, and do not resolve, the sensitive-field rows (tribe, ethnicity,
denomination, genotype, state_of_origin, preferred_tribes, preferred_religion),
which remain "Awaiting Uchechi" and were untouched by this pass.

## 7. What Pass 1 explicitly did not do

- No importer change. `FieldMapping`, `IdentityImport` and `UserRecord` are
  untouched.
- No `ProfilePreference` or `ProfileOptionSelection` created.
- No schema change, no migration.
- No change to `Profiles::FieldCatalog`, the profile-catalogue architecture
  (`931bb04`), discovery, or matching.
- No sensitive field read, mapped, or measured.
- No geography, verification, entitlement or notification-preference work.
- No mapping approved. Every "obvious" mapping above is recorded as a decision,
  not adopted — including `0 -> "man"` / `1 -> "woman"`, which the evidence shows
  is unambiguous but whose D8N spelling is still D-1.
- No change to `Migration::ReferenceMap` **in Pass 1**. The defect found while
  running this pass was recorded in `FOLLOWUP-REFERENCE-MAP-CLAIM.md` and fixed
  afterwards in its own slice (2026-09-06), separately from this evidence work.
- The isolated PG17 instance was started for the census run and stopped
  afterwards; both databases were read inside a `READ ONLY` transaction that
  always rolls back. Only aggregate output left the pristine environment. The
  same applies to the 2026-09-06 re-run of measures 221 / 225 / 259 / 290-299.
- **No sanitizer classification was changed.** `interests`, `relationship_values`
  and `dealbreakers` remain REVIEW_REQUIRED / REDACT, and `body_type` remains as
  the contract has it; E-5 and E-6 record what needs reviewing, not a change.
- **No non-allowlisted `body_type` value was emitted or retained.** The pre-fix
  distribution produced by the generic emitter was discarded and is not
  reproduced anywhere in this repository.
