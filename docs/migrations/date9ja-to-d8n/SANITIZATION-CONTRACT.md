# Date9ja Snapshot Sanitization Contract

Status: **Sanitizer executed and verified 2026-09-02 under schema guard v1;
schema-signature contract strengthened to v2 (2026-09-02) after independent
review. Census tooling SELF_VERIFIED.** No production access occurred.

This contract governs `scripts/date9ja/sanitize_snapshot.sql`,
`scripts/date9ja/verify_sanitized_snapshot.sql`, `scripts/date9ja/source_census.sql`,
and the shared `scripts/date9ja/schema_signature.sql`. It is the classification
authority for every column in the Date9ja production schema as restored locally
by the operator on 2026-09-02 (`~/date9ja-snapshot-work/schema/`).

It is subordinate to [`SNAPSHOT-RUNBOOK.md`](SNAPSHOT-RUNBOOK.md) (why a snapshot
exists, transfer/storage/deletion) and to `DECISIONS.md` (product/privacy gates).
It does **not** make any product decision about permanent field migration.

## 1. What the sanitized snapshot is for

A local engineering/migration **rehearsal** dataset that preserves enough
structure and state to build and test:

- deterministic legacy-ID mapping (`Migration::ReferenceMap`) and reconciliation
- user / profile / membership migration and profile completeness/state
- the bcrypt/session/recovery *mechanism* (not the production-hash proof — §6)
- photo / profile-video / Active Storage relationship and count reconciliation
- verification status, trust ledger structure, founding/premium entitlement state
- likes / passes / matches / conversation+message graph / profile views
- blocks / reports / notification+preference *shape*
- Community, Dating Hub, Aunty Phobie structural relationships
- attribution shape

It must contain **no** production secrets, usable credentials, direct
identifiers, raw private communication, precise coordinates, or unnecessary
sensitive UGC.

## 2. Classifications

| Class | Meaning |
|---|---|
| **PRESERVE** | Copied unchanged. Non-identifying structural/state/enumeration data a rehearsal capability needs. |
| **PSEUDONYMIZE** | Replaced with a deterministic synthetic value derived from an immutable legacy id. Format, uniqueness, and NOT NULL preserved; the real value does not survive. |
| **GENERALIZE** | Reduced to a coarser value (year-only date, 1-dp coordinate, hashed low-cardinality bucket). Null/non-null preserved. |
| **REDACT** | Free text / UGC replaced with a fixed placeholder (`[redacted]`) or `{}` / `'{}'`. Null/non-null preserved where the column is nullable; NOT NULL columns get the placeholder. |
| **DESTROY** | Set to NULL (or a fixed inert non-unique sentinel where NOT NULL). Live auth/secret material; no rehearsal capability may depend on the value. |
| **REVIEW_REQUIRED** | A defensible default is applied now (always the safe/fail-closed one), but the operator/reviewer should confirm whether a richer treatment is warranted for a later batch. |

**Default rule:** any column *not* named in §4 is **PRESERVE**. The sanitizer
refuses to run unless the live schema's `(table, column)` fingerprint matches the
constant recorded in the script (§3), so a new/renamed/dropped column forces this
contract to be revisited before the sanitizer can run again — nothing is silently
ignored.

## 3. Schema-signature guard — canonical contract (v2)

**One** definition, `scripts/date9ja/schema_signature.sql`, included verbatim
(`\ir`) by the sanitizer, the verifier and the census. Any structural drift
`RAISE`s and (inside the sanitizer's transaction) rolls back.

### v1 → v2

v1 hashed only `table_name.column_name`, so a **type-only, nullability-only or
ordinal-position-only** change to the classified schema could pass. v2 makes the
guard a real structural-compatibility contract.

### What v2 asserts

1. Exactly **51** public base tables, **exact name set** (no missing, no extra).
2. Exactly **574** public columns.
3. `md5` of, per column, ordered by `table_name COLLATE "C", ordinal_position`,
   `'\n'`-joined:
   `table_schema | table_name | ordinal_position | column_name | data_type |
   udt_name | is_nullable | character_maximum_length | numeric_precision |
   numeric_scale | datetime_precision | column_default`
   where sequence defaults (`nextval('…'::regclass)`) are normalised to `SEQ`
   (a column either is or is not serial; the sequence name is table-derived and
   its rendering varies by PG version / dump style).

Deliberately **excluded** as unstable/irrelevant: `udt_catalog` (database name),
`collation_name`, `dtd_identifier`, comments, storage/TOAST, index/constraint
metadata (structural integrity is enforced by the DB and reconciled separately).

### Expected v2 signature

Computed from the schema-only artifact
(`~/date9ja-snapshot-work/schema/date9ja-production-schema.sql`); **no raw
production database accessed**:

| | value |
|---|---|
| v2 signature | **`41a653a8d4c25621071fb76e6e59fbc0`** |
| base tables | 51 (exact set) |
| columns | 574 |
| superseded v1 fingerprint | `a317e7fb66f0d304e6273a4ee2473172` (name-only; retained here only for provenance) |

The v2 value was computed with `information_schema` on PostgreSQL 14; its inputs
(`data_type`, `udt_name`, precisions) render identically on PG 14–17 and
sequence defaults are normalised, so it is expected to hold on the operator's
PG17 snapshot. On the **first v2 run** the operator confirms it read-only by running
`schema_signature.sql` standalone against `date9ja_snapshot_sanitized`
(`SNAPSHOT-RUNBOOK.md` §3): it prints `... signature OK (v2 41a653a8…)` on a
match, or `SCHEMA DRIFT: … signature <X> != expected` showing the observed value.
If PG17 legitimately renders a non-sequence default differently, pin `<X>` in
`schema_signature.sql` (`v_expect_sig`) and record the one-line diff here —
never weaken the contract to make it pass.

## 4. Column treatments

Legend for the four integrity columns: **Null** = null/non-null pattern preserved;
**Uniq** = column uniqueness constraint still satisfiable; **RI** = referential
integrity preserved (no FK column touched); **n/a** = not applicable.

### 4.1 `users` (288 rows) — identity, profile, lifecycle, entitlement

| Column | Class | Transformation | Why / capability | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `email` | PSEUDONYMIZE | `'date9ja+' || id || '@snapshot.invalid'` | Legacy-ID map keys on email; Devise login mechanism; `.invalid` TLD is non-routable | preserved (NOT NULL) | preserved (id unique) | n/a |
| `unconfirmed_email` | DESTROY | `NULL` | May hold a real pending address; no rehearsal need | not preserved (documented) | preserved | n/a |
| `encrypted_password` | PSEUDONYMIZE | single fixed inert bcrypt digest (cost 12) for **every** row | Column must hold a valid bcrypt string for the auth *mechanism*; the production-hash proof is a separate operator procedure (§6) | preserved (NOT NULL) | n/a | n/a |
| `full_name` | PSEUDONYMIZE | `'Snapshot User ' || id` | Real name is a direct identifier; serializer/onboarding shape testing only needs a value | preserved (NOT NULL) | n/a | n/a |
| `display_name` | PSEUDONYMIZE | `'Snapshot ' || id` | "first name" at the API boundary; same reasoning | preserved (NOT NULL) | n/a | n/a |
| `phone` | PSEUDONYMIZE | `NULL` when null, else `'+99900000' || id` | `+999` is an unassigned country calling code → non-routable; phone-verification state testing needs presence/absence + uniqueness | preserved | preserved (id unique) | n/a |
| `public_id` | PSEUDONYMIZE | `'usr_' || lpad(to_hex(id),6,'0') || substr(md5(id||salt),1,18)` → `usr_` + 24 hex = 28 chars, matching the legacy `"usr_" + 24` length; `to_hex(id)` prefix guarantees uniqueness | Real `public_id` is a live deep-link handle; importer only needs a stable unique opaque source id | preserved (NOT NULL) | preserved (id-derived) | n/a |
| `jti` | DESTROY | `'snapshot-' || id` | Devise-JWT denylist id; live session material | preserved (NOT NULL) | preserved (id unique) | n/a |
| `reset_password_token` | DESTROY | `NULL` | Live credential-reset secret | not preserved (documented; no test needs it) | preserved | n/a |
| `reset_password_sent_at` | DESTROY | `NULL` | Paired with the token | not preserved | n/a | n/a |
| `confirmation_token` | DESTROY | `NULL` | Live email-confirmation secret | not preserved (documented) | preserved | n/a |
| `confirmation_sent_at` | DESTROY | `NULL` | Paired | not preserved | n/a | n/a |
| `confirmed_at` | PRESERVE | — | Email-verified state → drives identifier `verified_at` in the importer + auth-compat tests | — | n/a | n/a |
| `phone_verified_at` | PRESERVE | — | Phone-verified state for the importer | — | n/a | n/a |
| `current_sign_in_ip`, `last_sign_in_ip` | DESTROY | `NULL` | IP addresses are identifiers | not preserved | n/a | n/a |
| `date_of_birth` | GENERALIZE | `make_date(extract(year …)::int, 7, 1)` (year kept, fixed 1 Jul) | Age-band drives discovery/eligibility mapping; exact birthday removed; 1 Jul avoids leap-day and year-boundary age drift | preserved | n/a | n/a |
| `city` | REDACT | `NULL` | City + coarse coords + age + tribe re-identifies in 288 rows; stored `profile_completeness_score` is preserved independently | not preserved (documented) | n/a | n/a |
| `location_latitude`, `location_longitude` | DESTROY | `NULL` | A shareable rehearsal snapshot must not carry real user geography; no currently-unblocked test needs coordinates (discovery/distance rehearsal is separately gated and can use deterministic synthetic coordinates). Reviewer decision R6. | not preserved (documented) | n/a | n/a |
| `about_me`, `ideal_partner_description`, `interest_in_nigerian_culture` | REDACT | `'[redacted]'` when non-null | Free-text UGC; only presence matters for completeness tests | preserved | n/a | n/a |
| `occupation` | REDACT | `'[redacted]'` when non-null | Free-text, mildly identifying in combination | preserved | n/a | n/a |
| `deletion_reason`, `suspension_reason`, `ban_reason` | REDACT | `'[redacted]'` when non-null | Free-text that can contain PII/complainant detail; presence signals the lifecycle event | preserved | n/a | n/a |
| `tribe`, `denomination`, `state_of_origin`, `nationality`, `religion`, `ethnicity`, `intertribal_marriage_openness`, `polygamy_openness`, `is_nigerian` | DESTROY | `NULL` (all nullable) | Sensitive ethnic/religious/health-adjacent attributes. The sensitive-field importer is **gated** in `DECISIONS.md` and will need its own product-approved extract, so nothing currently justifies carrying real values or even their co-occurrence structure. Snapshot data-minimisation; the `DECISIONS.md` product rows are untouched. Reviewer decision R1. | not preserved (documented) | n/a | n/a |
| `gender`, `looking_for`, `education`, `marital_status`, `wants_children`, `children_count`, `relationship_intention`, `commitment_timeline`, `smoking`, `drinking`, `fitness`, `family_involvement_preference` | PRESERVE | — | Non-sensitive integer enum codes; required to test enum→typed-capability mapping. (`religion`/`ethnicity`/`polygamy_openness`/`intertribal_marriage_openness` moved to DESTROY — see the row above.) | — | n/a | n/a |
| `preferred_religion`, `preferred_tribes` | REDACT | `'{}'` | Sensitive free-text preference arrays; blocked, not needed for rehearsal | preserved (NOT NULL default) | n/a | n/a |
| `interests`, `relationship_values`, `dealbreakers` | REDACT / REVIEW_REQUIRED | `'{}'` | Free-text UGC arrays. **REVIEW_REQUIRED:** may be a controlled vocabulary in source → could become PRESERVE for catalog-mapping tests once confirmed. | preserved (NOT NULL) | n/a | n/a |
| `languages_spoken`, `preferred_countries`, `relocation_preferences` | PRESERVE | — | Low-risk enumerable (languages, ISO country codes); needed for options/preference mapping | — | n/a | n/a |
| `signup_source`, `attribution_source`, `attribution_medium`, `attribution_campaign`, `attribution_content` | GENERALIZE | `'bucket_' || (abs(hashtext(lower(col))) % 16)` when non-null | "Attribution shape" testing needs populated/empty + rough cardinality, not raw campaign/ad identifiers | preserved | n/a | n/a |
| `device_type`, `os_name`, `browser_name` | PRESERVE | — | Generic families; non-identifying (item 8) | — | n/a | n/a |
| `notification_preferences`, `email_notification_preferences` | GENERALIZE | keep only entries whose value is a JSON **boolean**; non-object collapses to `{}` | The app's only write path (`normalize_notification_preferences`) allowlists keys and validates values to booleans; the projection enforces that shape at sanitize time so a non-model write cannot leak. Preserves the on/off toggle shape for preference testing. Reviewer decision R4. | — (NOT NULL, `{}` default) | n/a | n/a |
| `v2_onboarding_answers` | REDACT | `'{}'` | Keys include `genotype`, `custom_religion`, `faith_practice` — health-adjacent / sensitive free text; blocked | preserved (NOT NULL) | n/a | n/a |
| `profile_completeness_score`, `verification_tier`, `trust_xp`, `subscription_status`, `premium_expires_at`, `founding_member`, `profile_hidden`, `suspended_at`, `banned_at`, `deleted_at`, `flagged_for_moderation_at`, `last_active_at`, `onboarding_completed_at`, `rewind_used_on`, `hide_last_seen`, `seed_account`, `admin`, `height`, `body_type`, `willing_to_relocate`, `preferred_age_min/max`, `preferred_distance_km`, `country_of_residence`, `aunty_phobie_language`, `sign_in_count`, `current_sign_in_at`, `last_sign_in_at`, `created_at`, `updated_at`, `id` | PRESERVE | — | Lifecycle / entitlement / verification / trust / profile state and timestamps required for reconciliation and no-downgrade proof; `country_of_residence` is a country, `body_type` a small enum | — | `id`, — | RI (id) |

### 4.2 Authentication-adjacent tables

| Table.column | Class | Transformation | Why | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `phone_verifications.phone` | PSEUDONYMIZE | `'+99900000' || user_id` | Non-routable, deterministic, aligns with `users.phone` | preserved (NOT NULL) | n/a (no uniq) | n/a |
| `phone_verifications.code_digest` | DESTROY | `'redacted'` (NOT NULL) | OTP digest | preserved (NOT NULL) | n/a | n/a |
| `phone_verifications.verified_at`, `request_count`, `attempt_count`, timestamps | PRESERVE | — | Phone-verification state/shape | — | n/a | n/a |
| `push_tokens.token` | PSEUDONYMIZE | `'snapshot-token-' || id` | Live device push credential; unique index | preserved (NOT NULL) | preserved (id unique) | n/a |
| `push_tokens.device_name` | DESTROY | `NULL` | Often a personal device label ("Jane's iPhone") | preserved (nullable) | n/a | n/a |
| `push_tokens.last_error` | REDACT | `'[redacted]'` when non-null | May embed token/endpoint fragments | preserved | n/a | n/a |
| `push_tokens.platform`, `disabled_at`, `last_registered_at`, timestamps | PRESERVE | — | Device-registration state/shape | — | n/a | n/a |

### 4.3 Verification & Trust

| Table.column | Class | Transformation | Why | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `verification_checks.provider`, `provider_reference`, `ai_review_model`, `ai_review_error` | DESTROY | `NULL` | Provider identifiers / evidence locators / raw AI text (item 13) | not preserved (documented) | n/a | n/a |
| `verification_checks.rejection_code` | DESTROY | `NULL` | Conservative — small code, but may narrow an individual; state is carried by `status` | not preserved | n/a | n/a |
| `verification_checks.ai_review_result` | REDACT | `'{}'` (NOT NULL jsonb) | Sensitive AI evidence payload | preserved (NOT NULL) | n/a | n/a |
| `verification_checks.check_type`, `status`, `submitted_at`, `decided_at`, `evidence_expires_at`, `duration_seconds`, `ai_review_status`, `ai_reviewed_at`, `evidence_retention_hold_until`, `reviewed_by_id`, timestamps | PRESERVE | — | Migration-testable verification **state** (item 13); `reviewed_by_id` is a FK to a user | — | (user_id,check_type) uniq preserved | RI |
| `verification_events.metadata` | REDACT | `'{}'` (NOT NULL jsonb) | Arbitrary metadata may expose user data / external refs | preserved (NOT NULL) | n/a | n/a |
| `verification_events.event_type`, `actor_id`, `verification_check_id`, `user_id`, timestamps | PRESERVE | — | Verification history structure | — | n/a | RI |
| `selfie_verifications.rejection_reason` | REDACT | `'[redacted]'` when non-null | Free-text moderation note | preserved | n/a | n/a |
| `selfie_verifications.status`, `reviewed_by_id`, `reviewed_at`, timestamps | PRESERVE | — | Verification state | — | user_id uniq preserved | RI |
| `trust_events.idempotency_key` | PSEUDONYMIZE | `'snapshot-te-' || id` | May embed external/source references; unique index | preserved (NOT NULL) | preserved (id unique) | n/a |
| `trust_events.metadata` | REDACT | `'{}'` (NOT NULL jsonb) | Arbitrary metadata | preserved (NOT NULL) | n/a | n/a |
| `trust_events.event_type`, `points`, `source_type`, `source_id`, timestamps | PRESERVE | — | Trust ledger structure for reconciliation (item 14); `source_id` is a loose polymorphic ref, not an enforced FK | — | n/a | n/a |
| `trust_adjustments.idempotency_key` | PSEUDONYMIZE | `'snapshot-ta-' || id` | Same as above | preserved (NOT NULL) | preserved | n/a |
| `trust_adjustments.note` | REDACT | `'[redacted]'` when non-null | Free-text moderator note | preserved | n/a | n/a |
| `trust_adjustments.points`, `reason_code`, `appeal_status`, `appealed_at`, `resolved_at`, `actor_id`, `resolved_by_id`, timestamps | PRESERVE | — | Adjustment ledger structure | — | n/a | RI |

### 4.4 Media (no bytes are ever copied)

| Table.column | Class | Transformation | Why | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `active_storage_blobs.key` | PSEUDONYMIZE | `'snapshot/' || id || '/' || md5(id::text || salt)` | Raw object key is an R2 access/location identifier (item 17); unique index | preserved (NOT NULL) | preserved (id unique) | n/a |
| `active_storage_blobs.filename` | PSEUDONYMIZE | `'file-' || id || <ext-from-content_type>` | Real filenames often contain personal names | preserved (NOT NULL) | n/a | n/a |
| `active_storage_blobs.metadata` | REDACT / REVIEW_REQUIRED | `NULL` | Analyzer JSON (text). **REVIEW_REQUIRED:** an allowlisted `{width,height,duration,analyzed}` projection could be restored if media dry-run needs dimensions. | preserved (nullable) | n/a | n/a |
| `active_storage_blobs.content_type`, `byte_size`, `checksum`, `service_name`, `created_at` | PRESERVE | — | Owner/type/size/count reconciliation (item 17); `checksum` is a content digest, not identifying | — | n/a | n/a |
| `active_storage_attachments.*` (`name`, `record_type`, `record_id`, `blob_id`, timestamps) | PRESERVE | — | The attachment graph itself — required for owner/reference mapping | — | uniqueness index preserved | RI |
| `active_storage_variant_records.*` | PRESERVE | — | Derived-media structure | — | uniqueness index preserved | RI |
| `photos.*` (all columns) | PRESERVE | — | Ordering, primary flag, moderation status, reviewer, timestamps — no free text | — | n/a | RI |
| `profile_videos.rejection_reason` | REDACT | `'[redacted]'` when non-null | Free-text moderation note | preserved | n/a | n/a |
| `profile_videos.*` (all other columns) | PRESERVE | — | Owner, duration, moderation status, reviewer, timestamps; `user_id` uniq | — | user_id uniq preserved | RI |

### 4.5 Dating graph

| Table.column | Class | Transformation | Why | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `messages.body` | REDACT | `'[redacted]'` when non-null | Private conversation content; null body = media message → topology preserved | preserved | n/a | n/a |
| `messages.*` (all other columns) | PRESERVE | — | `match_id`, `sender_id`, `reply_to_id`, `kind`, `duration_seconds`, `read_at`, `deleted_at`, `edited_at`, timestamps — conversation/message graph, read state, reply structure | — | n/a | RI |
| `message_reactions.*` (incl. `emoji`) | PRESERVE | — | Reaction structure; an emoji is not content | — | (message_id,user_id) uniq preserved | RI |
| `likes.*`, `matches.*`, `profile_passes.*`, `profile_views.*`, `explore_impressions.*` | PRESERVE | — | Interaction graph + view history for reconciliation | — | direction/pair uniq preserved | RI |
| `daily_introductions.compatibility_reasons` | REDACT | `'[]'::jsonb` (NOT NULL, `[]` default) | May contain profile-derived text | preserved (NOT NULL) | n/a | n/a |
| `daily_introductions.*` (all other columns) | PRESERVE | — | user/candidate/date/position/score structure | — | (user,date,candidate) & (user,date,position) uniq preserved | RI |
| `blocks.*` | PRESERVE | — | Safety graph (3 rows) | — | (blocker,blocked) uniq preserved | RI |
| `reports.body` | REDACT | `'[redacted]'` when non-null | Reporter's free-text allegation | preserved | n/a | n/a |
| `reports.*` (all other columns) | PRESERVE | — | reporter/reported/category/resolution state (3 rows) | — | n/a | RI |

### 4.6 Notifications

| Table.column | Class | Transformation | Why | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `notifications.payload` | REDACT | `'{}'` (NOT NULL jsonb) | Payload embeds names/message snippets (item 12) | preserved (NOT NULL) | n/a | n/a |
| `notifications.*` (all other columns) | PRESERVE | — | recipient/actor/notifiable/kind/read_at — inbox shape and read state | — | n/a | RI |
| `notification_deliveries.last_error` | REDACT | `'[redacted]'` when non-null | May embed address/endpoint | preserved | n/a | n/a |
| `notification_deliveries.*` (all other columns) | PRESERVE | — | channel/status/attempts/delivered_at — delivery state | — | (notification_id,channel) uniq preserved | RI |

### 4.7 Community

| Table.column | Class | Transformation | Why | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `community_questions.body`, `community_answers.body`, `community_remarks.body`, `community_stories.body`, `community_events.description` | REDACT | `'[redacted]'` (NOT NULL) | User-generated content | preserved (NOT NULL) | n/a | n/a |
| `community_questions.aunty_phobie_take`, `*.moderation_note` (all community tables), `community_reports.body` | REDACT | `'[redacted]'` when non-null | AI/moderator free text | preserved | n/a | n/a |
| `*.risk_flags` (questions, answers, events, remarks, stories) | REDACT | `'[]'::jsonb` (NOT NULL jsonb, `[]` default) | May quote flagged content | preserved (NOT NULL) | n/a | n/a |
| `community_events.title`, `community_stories.title` | PSEUDONYMIZE | `'Event ' || id` / `'Story ' || id` | May contain identifying phrasing | preserved (NOT NULL) | n/a | n/a |
| `community_events.venue`, `community_stories.location` | DESTROY | `NULL` (both nullable) | Precise meetup locations | preserved (nullable) | n/a | n/a |
| `community_events.city` | REDACT | `'[redacted]'` (NOT NULL — cannot drop) | Precise meetup location; column is NOT NULL so a placeholder is used | preserved (NOT NULL) | n/a | n/a |
| `community_stories.couple_names` | PSEUDONYMIZE | `'Couple ' || id` | Real names of (possibly non-user) people | preserved (NOT NULL) | n/a | n/a |
| `community_*` (all other columns: category, status, risk_level, anonymous, is_featured, is_pick_of_week, publish_consent, content_type, published_at/closed_at, all FK ids, votes, rsvps, timestamps) | PRESERVE | — | Community relationship graph + moderation state | — | vote/rsvp/report partial-uniques preserved | RI |

### 4.8 Dating Hub & personas

| Table.column | Class | Transformation | Why | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `personas.current_life`, `family_background`, `looking_for` | REDACT | `'[redacted]'` when non-null | Personal narrative text | preserved | n/a | n/a |
| `personas.core_values`, `hobbies_and_interests`, `good_stories`, `topics_to_ease_into` | REDACT | `'{}'` (NOT NULL arrays) | Free-text arrays | preserved (NOT NULL) | n/a | n/a |
| `personas.tone`, `user_id`, timestamps | PRESERVE | — | Structural relationship | — | user_id uniq preserved | RI |
| `dating_hub_batches.name` | PSEUDONYMIZE | `'Batch ' || id` | May contain names | preserved (NOT NULL) | n/a | n/a |
| `dating_hub_batches.description` | REDACT | `'[redacted]'` when non-null | Free text | preserved | n/a | n/a |
| `dating_hub_batches.started_on`, `user_id`, timestamps | PRESERVE | — | Structure | — | n/a | RI |
| `tracked_contacts.external_name` | PSEUDONYMIZE | `'Contact ' || id` when non-null | **Name of a non-user third party** | preserved | n/a | n/a |
| `tracked_contacts.external_location` | DESTROY | `NULL` | Third-party location | preserved (nullable) | n/a | n/a |
| `tracked_contacts.partner_birthday_month`, `partner_birthday_day` | DESTROY | `NULL` | Third-party birthday | preserved (nullable) | n/a | n/a |
| `tracked_contacts.external_age`, `matched_user_id`, `status`, `dating_hub_batch_id`, `user_id`, `last_contacted_on`, `next_follow_up_on`, timestamps | PRESERVE | — | Dating Hub relationship graph; `matched_user_id` FK | — | n/a | RI |
| `tracked_contact_notes.body` | REDACT | `'[redacted]'` (NOT NULL) | Private notes about a contact | preserved (NOT NULL) | n/a | n/a |
| `tracked_contact_notes.category`, `tracked_contact_id`, timestamps | PRESERVE | — | Structure | — | n/a | RI |
| `daily_life_entries.today_plan`, `highlight`, `learned`, `ask_prompt`, `share_prompt` | REDACT | `'[redacted]'` when non-null | Journal free text | preserved | n/a | n/a |
| `daily_life_entries.mood`, `focus_tag` | REDACT | `'[redacted]'` when non-null | May be free text rather than a fixed picker; redacted defensively | preserved | n/a | n/a |
| `daily_life_entries.user_id`, `entry_date`, timestamps | PRESERVE | — | Structure | — | (user_id,entry_date) uniq preserved | RI |

### 4.9 Aunty Phobie (AI assistant)

| Table.column | Class | Transformation | Why | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `aunty_phobie_messages.content` | REDACT | `'[redacted]'` (NOT NULL) | Private AI-support conversation | preserved (NOT NULL) | n/a | n/a |
| `aunty_phobie_messages.context_snapshot` | REDACT | `'{}'` (NOT NULL jsonb) | Snapshot of the user's profile/state at send time | preserved (NOT NULL) | n/a | n/a |
| `aunty_phobie_messages.client_message_id` | PSEUDONYMIZE | `'snapshot-cm-' || id` when non-null | Partial unique index `(conversation_id, client_message_id)` | preserved | preserved (id unique) | n/a |
| `aunty_phobie_messages.role`, `model`, `aunty_phobie_conversation_id`, timestamps | PRESERVE | — | Message structure | — | n/a | RI |
| `aunty_phobie_conversations.escalation_resolution_note` | REDACT | `'[redacted]'` when non-null | Moderator free text | preserved | n/a | n/a |
| `aunty_phobie_conversations.*` (status, escalation_status, escalated_at, escalation_reviewer_id, escalation_resolved_at, last_message_at, user_id, timestamps) | PRESERVE | — | Conversation + escalation structure | — | active-conversation partial uniq preserved | RI |
| `aunty_phobie_usage_events.request_key` | PSEUDONYMIZE | `'snapshot-rk-' || id` | Unique index; may embed request context | preserved (NOT NULL) | preserved (id unique) | n/a |
| `aunty_phobie_usage_events.*` (model, token counts, status, conversation_id, user_id, timestamps) | PRESERVE | — | Usage/limit structure | — | n/a | RI |

### 4.10 Careers, Feedback, Ops, Company

| Table.column | Class | Transformation | Why | Null | Uniq | RI |
|---|---|---|---|---|---|---|
| `career_applications.name` | PSEUDONYMIZE | `'Snapshot Applicant ' || id` | Applicant real name | preserved (NOT NULL) | n/a | n/a |
| `career_applications.email` | PSEUDONYMIZE | `'applicant+' || id || '@snapshot.invalid'` | Applicant email | preserved (NOT NULL) | n/a | n/a |
| `career_applications.phone` | PSEUDONYMIZE | `'+99900000' || id` when non-null | Applicant phone | preserved | n/a | n/a |
| `career_applications.date9ja_email` | PSEUDONYMIZE | `'date9ja+' || coalesce(user_id, id) || '@snapshot.invalid'` when non-null | Links to the app account where present | preserved | n/a | n/a |
| `career_applications.cover_letter` | REDACT | `'[redacted]'` (NOT NULL) | Free text | preserved (NOT NULL) | n/a | n/a |
| `career_applications.portfolio_url`, `linkedin_url` | PSEUDONYMIZE | `'https://snapshot.invalid/' || id` when non-null | External profile URLs | preserved | n/a | n/a |
| `career_applications.admin_note` | REDACT | `'[redacted]'` when non-null | Reviewer free text | preserved | n/a | n/a |
| `career_applications.*` (has_date9ja_account, status, reviewed_at, reviewed_by_id, career_job_id, user_id, timestamps) | PRESERVE | — | Application state + linkage | — | n/a | RI |
| `career_jobs.summary`, `description`, `responsibilities`, `requirements`, `nice_to_have` | REDACT | `'[redacted]'` (`nice_to_have` keeps null) | Company-authored postings are not migration data; an unpublished draft could carry internal wording / staff names. Reviewer decision R5. | preserved | n/a | n/a |
| `career_jobs.*` (title, slug, department, location, employment_type, status, dates, `created_by_id`) | PRESERVE | — | Non-sensitive structural fields | — | slug uniq preserved | RI |
| `feedback_items.message` | REDACT | `'[redacted]'` (NOT NULL) | User feedback free text | preserved (NOT NULL) | n/a | n/a |
| `feedback_items.*` (category, reviewed_at, reviewed_by_id, user_id, timestamps) | PRESERVE | — | Feedback state | — | n/a | RI |
| `error_logs.message`, `backtrace`, `request_path` | REDACT | `'[redacted]'` when non-null | May contain PII in params/paths/exception messages | preserved | n/a | n/a |
| `error_logs.*` (exception_class, request_method, status, user_id, timestamps) | PRESERVE | — | Error shape + user linkage | — | n/a | RI (user_id nullable FK) |
| `audit_logs.metadata` | REDACT | `'{}'` (NOT NULL jsonb) | Admin action detail may embed user data | preserved (NOT NULL) | n/a | n/a |
| `audit_logs.*` (kind, actor_id, target_user_id, timestamps) | PRESERVE | — | Admin/security history structure | — | n/a | RI |
| `company_journal_entries.title` (NOT NULL), `company_journal_entries.note`, `company_settings.mission`, `vision`, `advisor_summary`, `advisor_why`, `advisor_error` | REDACT | `'[redacted]'` (nullable ones keep null) | Internal company strategy text; out of migration scope, redacted defensively | preserved | n/a | n/a |
| `company_settings.advisor_focus_areas` | REDACT | `'[]'::jsonb` (NOT NULL, `[]` default) | Internal | preserved (NOT NULL) | n/a | n/a |
| `company_goals.*`, `company_settings.*` (numeric/date/enum/array remainder), `company_journal_entries.*` (occurred_on, title, milestone, timestamps) | PRESERVE | — | Non-sensitive structure; not imported | — | n/a | n/a |

### 4.11 Framework tables

| Table | Class | Note |
|---|---|---|
| `schema_migrations`, `ar_internal_metadata` | PRESERVE | Schema identity; no PII |
| all `id`, `created_at`, `updated_at`, and every FK column across all tables | PRESERVE | Never rewritten — relational graph and reconciliation depend on them |

## 5. Deterministic transformation primitives

| Primitive | Definition |
|---|---|
| salt | constant `'date9ja-snapshot-v1'` embedded in the script. Not a secret; changing it changes all pseudonymous outputs. Documented so equivalent snapshots reproduce values. |
| pseudonymous token | derived from `md5(<immutable id>::text || salt)` — never from row order. |
| bucket | `'bucket_' || (abs(hashtext(lower(value))) % N)` — `hashtext` is deterministic within a PostgreSQL major version; acceptable because buckets only need to be stable *within* one snapshot for cardinality/mapping tests. |
| placeholder | `'[redacted]'` for text, `'{}'::jsonb` / `'{}'::text` / `'{}'` array literal for structured columns. |
| non-routable phone | `+999` prefix — ITU-unassigned country calling code. |
| non-routable email | `@snapshot.invalid` — reserved `.invalid` TLD (RFC 2606). |

## 6. bcrypt: sanitized dataset vs. the real compatibility proof

- **This sanitized dataset:** every `users.encrypted_password` is the **same fixed
  inert bcrypt digest**. It proves the *column shape* and lets the importer's
  credential-creation path run, but it is **not** a test of real hash
  verification. No plaintext for this digest is recorded in the repository.
- **The real proof (separate, operator-only, NOT in this task):** the operator
  runs `BCrypt::Password.new(hash).is_password?(known_plaintext)` against **one or
  a very small number of operator-owned accounts** whose plaintext Uchechi holds
  out of band, using hashes read directly from the pristine raw restore — never
  from a shared artifact, never logged. See `SNAPSHOT-RUNBOOK.md` §6.
- Rationale: a shareable dataset carrying every production bcrypt hash is an
  offline cracking target for 288 real users. The mechanism and the proof are
  decoupled.

## 7. Reconciliation invariants (enforced by the verifier)

The verifier (`verify_sanitized_snapshot.sql`) `RAISE`s on any of:

1. table set ≠ the 51 expected; column fingerprint ≠ constant.
2. **Row counts** — `users` etc. differ from counts captured at the top of the
   sanitizer run (stored in `sanitize_audit.counts`, a table in a dedicated
   non-`public` schema so it never affects either fingerprint check; the
   operator drops schema `sanitize_audit` before packaging). The verifier also prints
   the 2026-09-02 baseline (users 288, photos 279, profile_videos 35,
   active_storage_blobs 443, likes 546, matches 82, messages 1025,
   profile_views 1627, blocks 3, reports 3) as **informational only** — a
   different future snapshot may legitimately differ.
3. Orphaned core FKs: any `likes`/`matches`/`messages`/`profile_views`/`blocks`/
   `reports`/`photos`/`profile_videos`/`active_storage_attachments` row whose
   user/match/blob parent is missing.
4. Any `users.email` not matching `^date9ja\+[0-9]+@snapshot\.invalid$`; any
   `unconfirmed_email IS NOT NULL`; any `@`-containing string in
   `career_applications.email`/`date9ja_email` outside `@snapshot.invalid`.
5. Any non-null `reset_password_token` / `confirmation_token`; any `jti` not
   `^snapshot-`; any `users` IP column non-null.
6. Any `phone_verifications.code_digest <> 'redacted'`; any `phone` (users,
   phone_verifications, career_applications) not `^\+999` (when non-null).
7. Any `push_tokens.token` not `^snapshot-token-`.
8. Any `verification_checks.provider`/`provider_reference`/`ai_review_model`/
   `ai_review_error` non-null; any `ai_review_result <> '{}'::jsonb`.
9. Any redacted-required text column still holding a value that is neither NULL
   nor `'[redacted]'` (checked for: `messages.body`, `reports.body`,
   `community_*` bodies, `aunty_phobie_messages.content`,
   `tracked_contact_notes.body`, `personas` narrative columns,
   `feedback_items.message`).
10. Any object-shaped redacted jsonb column (`notifications.payload`,
    `audit_logs.metadata`, `trust_events.metadata`,
    `verification_events.metadata`, `verification_checks.ai_review_result`,
    `aunty_phobie_messages.context_snapshot`, `users.v2_onboarding_answers`)
    not equal to `'{}'::jsonb`; any array-shaped one (`community_*.risk_flags`,
    `daily_introductions.compatibility_reasons`,
    `company_settings.advisor_focus_areas`) not equal to `'[]'::jsonb`.
11. Any `users.location_latitude`/`longitude` that is not NULL;
    any `users.date_of_birth` where `month <> 7 OR day <> 1`.
12. Legacy IDs preserved: `count(users) = count(distinct id) = count(distinct
    public_id) = count(distinct email)`.
13. Determinism spot-check: `email = 'date9ja+' || id || '@snapshot.invalid'` for
    every row.
14. Media graph counts unchanged vs. `_sanitize_audit`
    (`active_storage_attachments`, `active_storage_blobs`).

Where a violation is found the verifier prints the offending count and
`RAISE EXCEPTION` (fail-closed, non-zero exit under `ON_ERROR_STOP`).

## 8. Assumptions

- The operator runs the sanitizer against `date9ja_snapshot_sanitized` (a copy),
  **never** `date9ja_snapshot_tmp`. The script cannot technically distinguish
  them; this is an operator responsibility stated in the header and the runbook.
- PostgreSQL 17; `hashtext`, `md5`, `make_date`, `regexp` operators available.
- No application (Date9ja or D8N) runs against the sanitized DB, so only
  DB-level constraints (NOT NULL, unique indexes, the three `users` CHECKs) must
  remain satisfied — and they do.
- `character varying` columns have no length limit in this schema, so synthetic
  values cannot overflow.
- The 51-table / 574-column schema in `~/date9ja-snapshot-work/schema/` is the
  truth; the sanitizer refuses to run against anything else.

## 9. Open REVIEW_REQUIRED items

| # | Item | Default applied | Decision needed |
|---|---|---|---|
| R1 | sensitive religious/ethnic/tribal attrs | **RESOLVED** — all dropped to NULL (was hashed bucket / PRESERVE) | A future sensitive-field importer needs its own product-approved extract regardless. |
| R2 | `users.interests` / `relationship_values` / `dealbreakers` | `'{}'` | Confirm whether these are controlled vocab in source → could become PRESERVE. |
| R3 | `active_storage_blobs.metadata` | `NULL` | Whether an allowlisted `{width,height,duration,analyzed}` projection is needed for a media dry-run. |
| R4 | notification-preference JSON | **RESOLVED** — boolean-value projection + verifier assertion (was PRESERVE) | — |
| R5 | `career_jobs` free text | **RESOLVED** — long-text fields REDACTED | — |
| R6 | `users.location_*` | **RESOLVED** — dropped to NULL | If a later discovery/distance rehearsal needs coordinates, add deterministic synthetic ones then. |
| R7 | `verification_checks.rejection_code` | `NULL` | Whether the code is a safe enum worth preserving as verification state. |

## 10. Scope statement

This is **migration infrastructure**, not a Date9ja product subsystem and not a
generic anonymization framework. It is one guarded SQL transform + one verifier +
this contract, sized exactly to the Date9ja schema. No new abstraction, no D8N
runtime code, no product/privacy decision. Permanent sensitive-field migration,
verification-evidence portability, trust presentation, and entitlement semantics
remain gated in `DECISIONS.md` and are untouched here.
