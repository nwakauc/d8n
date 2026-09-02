# Sanitized Date9ja Snapshot & Data-Dictionary Runbook

Status: **DRAFT — awaiting Uchechi approval and execution.** No snapshot has been
taken. No production access has occurred. This document specifies the *minimum*
data required to unblock the next Phase 1 implementation batch and how to produce,
move, protect, and destroy it. It does not authorize production access; taking the
snapshot is an operator (Uchechi) action.

## 1. Why this snapshot is needed

Four Phase 1 work items are blocked **only** on a representative dataset, not on a
product decision:

| Blocked item | Wave A slice | What the snapshot proves/enables |
|---|---|---|
| bcrypt credential + session/recovery compatibility | 3 | That `users.encrypted_password` hashes verify unchanged under D8N's `bcrypt ~> 3.1` and `Identity::PasswordEngine`; that email/phone normalization does not collide accounts |
| Legacy identifier → D8N identity mapping (importer) | 2 (consumer) / 5 | Real `id` / `public_id` / `email` / `phone` shapes to drive `Migration::ReferenceMap` binding and idempotency tests |
| Profile-photo + profile-video importer | 5 | Real Active Storage blob keys, checksums, content types, positions, moderation states for media preflight and reconciliation |
| Reconciliation harness | 6 | Real source counts to populate `RECONCILIATION.md` acceptance rows |

Everything else in Phase 1 (Verification ADR 0024, Trust ADR 0025, Entitlements
ADR 0026, sensitive profile fields) stays blocked on `DECISIONS.md` product/privacy
rows and is **out of scope for this snapshot** — see §9.

## 2. Principles

1. **Minimum necessary.** Only the tables/columns in §4. No community, Dating Hub,
   Aunty Phobie, analytics, audit-log, or admin tables.
2. **No live secrets.** No JWTs, no `jti`, no reset/confirmation tokens, no OTP
   digests, no session data, no API keys, no push tokens. These are dropped at
   extraction, not redacted later.
3. **Pseudonymize identity, preserve structure.** Real values are kept only where a
   test genuinely needs the real value (bcrypt hashes, email/phone *format*,
   blob metadata). Names, free text, and precise location are redacted or coarsened.
4. **Bounded size.** A stratified sample (§3), not a full copy. Target ≤ 2,000
   source users.
5. **Time-boxed.** The snapshot is deleted within 14 days of the batch completing
   (§8). It never lands in the repo, a bucket with public/broad access, or a
   long-lived backup.
6. **Auditable.** Record snapshot ID, row counts, who produced it, where it lived,
   and deletion confirmation in §10.

## 3. How the snapshot is produced

> **Concrete implementation (2026-09-02):** the dataset is only 288 users, so
> instead of a stratified sample + extraction script, the operator restores the
> full backup into an isolated PostgreSQL 17 instance and sanitizes it **in
> place** with a deterministic, guarded SQL transform:
>
> - `scripts/date9ja/sanitize_snapshot.sql` — the sanitizer
> - `scripts/date9ja/verify_sanitized_snapshot.sql` — the fail-closed verifier
> - [`SANITIZATION-CONTRACT.md`](SANITIZATION-CONTRACT.md) — per-column classification of all 51 tables / 574 columns
>
> Run order (operator only):
> ```
> # date9ja_snapshot_sanitized is a COPY of the pristine date9ja_snapshot_tmp restore
> psql -v ON_ERROR_STOP=1 -v sanitize_ack=SANITIZE_THE_COPY \
>      -d date9ja_snapshot_sanitized -f scripts/date9ja/sanitize_snapshot.sql
> psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized \
>      -f scripts/date9ja/verify_sanitized_snapshot.sql
> psql -d date9ja_snapshot_sanitized -c 'DROP SCHEMA IF EXISTS sanitize_audit CASCADE;'
> ```
> The sanitizer refuses to run against `date9ja_snapshot_tmp`, refuses a second
> run, and aborts (rolls back) on any schema drift or post-check violation. Then
> `pg_dump` the sanitized DB as the shareable artifact and follow §7–§8 for
> transfer, storage, and deletion. The stratified-sample guidance below is
> retained for a future larger snapshot.

Operator runs a **read-only** extraction against a *restore of a recent encrypted
backup* — never against the live primary.

1. Restore the latest encrypted Date9ja backup into an isolated, non-internet-facing
   Postgres instance (local disk-encrypted VM or an access-restricted ephemeral DB).
2. Select a stratified sample of **source `users`**, capped at 2,000:
   - all `founding_member = true` and `subscription_status != 0` users (entitlement
     edge cases) — cap this stratum at 300;
   - all users with a `profile_videos` row — cap 300;
   - all users with ≥ 1 `photos` row and `confirmed_at` present — cap 600;
   - a random sample of the remainder to fill to 2,000, including some
     `deleted_at`, `suspended_at`, `banned_at`, `profile_hidden`, and
     `confirmed_at IS NULL` rows (≥ 25 of each state).
   - include enough **mutual** `likes` / `matches` / `messages` within the sampled
     set that the importer's graph validation is exercised (sample matches first,
     then force-include both participants).
3. Apply the transform in §5 during extraction (a SQL `COPY (SELECT …)` with
   expressions, or a small extraction script — **not** a post-hoc scrub).
4. Write output as per-table newline-delimited JSON or CSV into one directory.
5. Extract Active Storage rows (§4) and, separately, a **manifest** of referenced
   blob keys with `byte_size`, `checksum`, `content_type` — **not the blob bytes**
   for the first pass. A later media dry-run may request a bounded copy of ≤ 200
   real objects into a D8N-controlled private bucket prefix.
6. Compute row counts per table; record in §10.
7. Destroy the restored DB instance immediately (§8 step 1).

## 4. Tables and columns required

### `users` → identity + profile + lifecycle + entitlement state

**Preserve exactly:** `id`, `public_id`, `encrypted_password`, `confirmed_at`,
`phone_verified_at`, `created_at`, `deleted_at`, `suspended_at`, `banned_at`,
`profile_hidden`, `flagged_for_moderation_at`, `last_active_at`,
`onboarding_completed_at`, `verification_tier`, `trust_xp`, `subscription_status`,
`premium_expires_at`, `founding_member`, `profile_completeness_score`, `gender`,
`looking_for`, `date_of_birth` (see §5 — coarsened), all non-sensitive profile
enums/arrays needed for catalog parity work (`education`, `marital_status`,
`wants_children`, `children_count`, `height`, `body_type`, `smoking`, `drinking`,
`fitness`, `family_involvement_preference`, `relationship_intention`,
`commitment_timeline`, `willing_to_relocate`, `interests`, `languages_spoken`,
`relationship_values`, `dealbreakers`, `preferred_age_min`, `preferred_age_max`,
`preferred_countries`, `preferred_distance_km`, `relocation_preferences`,
`country_of_residence`, `city`, `signup_source`, `attribution_source`,
`attribution_medium`, `attribution_campaign`, `attribution_content`).

**Redact / pseudonymize (see §5):** `email`, `phone`, `full_name`, `display_name`,
`about_me`, `ideal_partner_description`, `interest_in_nigerian_culture`,
`deletion_reason`, `suspension_reason`, `ban_reason`, `current_sign_in_ip`,
`last_sign_in_ip`, `location_latitude`, `location_longitude`,
`v2_onboarding_answers`, `notification_preferences`,
`email_notification_preferences` (keep structure/keys, scrub any free-text values).

**Drop entirely (never leave the source DB):** `jti`, `reset_password_token`,
`reset_password_sent_at`, `confirmation_token`, `confirmation_sent_at`,
`unconfirmed_email`, `current_sign_in_at`, `last_sign_in_at`, `sign_in_count`.

**Sensitive fields — DROP for this snapshot** (blocked in `DECISIONS.md`, not
needed to unblock §1): `tribe`, `religion`, `denomination`, `ethnicity`,
`state_of_origin`, `is_nigerian`, `nationality`, `preferred_religion`,
`preferred_tribes`, `intertribal_marriage_openness`, `polygamy_openness`,
`aunty_phobie_language`. A separate, separately-approved snapshot handles these
once the product/privacy rows are decided.

### `photos`

All columns: `id`, `user_id`, `position`, `moderation_status`, `is_primary`,
`reviewed_at`, `created_at`. (No free text.)

### `profile_videos`

All columns: `id`, `user_id`, `duration_seconds`, `moderation_status`,
`reviewed_at`, `created_at`. **Redact** `rejection_reason` (free text →
category code or `null`).

### `active_storage_attachments` + `active_storage_blobs` (for `photos` /
`profile_videos` / message media records only)

`active_storage_attachments`: `id`, `name`, `record_type`, `record_id`, `blob_id`,
`created_at`. `active_storage_blobs`: `id`, `key`, `filename`, `content_type`,
`byte_size`, `checksum`, `created_at`, `service_name`, `metadata` (scrub any
free-text metadata values; keep dimensions/analyzed flags). **No `variant_records`
in pass 1.** **No blob bytes in pass 1.**

### `phone_verifications`

`user_id`, `verified_at` only. **Drop** `code_digest`, `phone` (derive phone
verified-state from `verified_at`; the number itself comes pseudonymized from
`users`). Drop the whole row if `verified_at IS NULL`.

### Relationship graph (sampled subset, IDs only, no bodies)

- `likes`: `id`, `liker_id`, `liked_id`, `kind`, `created_at`
- `profile_passes`: `id`, `passer_id`, `passed_id`, `created_at`
- `matches`: `id`, `user_a_id`, `user_b_id`, `created_at`
- `messages`: `id`, `match_id`, `sender_id`, `reply_to_id`, `kind`,
  `duration_seconds`, `read_at`, `deleted_at`, `edited_at`, `created_at` —
  **`body` REDACTED** to a fixed placeholder or its length only. Message media
  via the Active Storage manifest.
- `message_reactions`: `id`, `message_id`, `user_id`, `emoji`, `created_at`
- `blocks`: `id`, plus the two user FK columns and `created_at`
- `reports`: `id`, `reporter_id`, `reported_id`, `category`, `resolved_at`,
  `created_at` — **`body` REDACTED**
- `notifications`: `id`, `recipient_id`, `actor_id`, `kind`, `read_at`,
  `created_at`, `notifiable_type`, `notifiable_id` — **`payload` structure only,
  values scrubbed**
- `notification_deliveries`: `notification_id`, `channel`, `status`, `attempts`
- `push_tokens`: **DROP the token.** Keep `user_id`, `platform`, `disabled_at`,
  `last_registered_at` only (device-registration state, not the credential).

### Verification / Trust — **state and counts only, no evidence**

- `verification_checks`: `user_id`, `check_type`, `status`, `provider`,
  `decided_at`, `evidence_expires_at` — **drop** `provider_reference`,
  `ai_review_result`, `ai_review_error`, `rejection_code` free text.
- `verification_events`: `verification_check_id`, `user_id`, `event_type`,
  `created_at` — **drop** `metadata`.
- `selfie_verifications` / `trust_events` / `trust_adjustments`: `user_id`,
  status/`event_type`/`points`/`reason_code`, timestamps, `idempotency_key`.
  **Drop** `note`, evidence references.

These are included so reconciliation can count them and the importer contract can
be shaped — **not** so verification/trust implementation can start. That stays
gated (§9).

## 5. Redaction / pseudonymization rules

Applied deterministically during extraction so referential integrity holds:

| Field | Rule |
|---|---|
| `users.email` | `format("date9ja+%d@snapshot.invalid", id)` — preserves uniqueness and lets D8N email normalization run; **not** a real address |
| `users.phone` | Replace national significant digits with a Luhn-neutral deterministic hash of `id`, keep `+234` country prefix and length so E.164 normalization is exercised |
| `full_name` / `display_name` | Faker-style value seeded by `id` (stable), or `"Member <id>"` |
| Free-text (`about_me`, `*_reason`, `ideal_partner_description`, message `body`, report `body`, notes) | Replace with `"[redacted]"` or, where length matters for a test, `"x" * least(original_length, 280)` |
| `date_of_birth` | Keep year and clamp day to the 15th of the month (age-band preserved, exact DOB removed) |
| `location_latitude` / `location_longitude` | Drop (set NULL) — see `SANITIZATION-CONTRACT.md` R6; a later discovery/distance rehearsal adds deterministic synthetic coordinates if needed |
| IP columns | Drop |
| `encrypted_password` | **Kept verbatim** — this is the whole point of the bcrypt proof. It is a one-way hash, not a reversible secret, but still treat the file as confidential (§7). |
| JSONB preference blobs | Keep keys, replace string values with `"[redacted]"`, keep booleans/enums |
| Active Storage `key` | **Kept verbatim** (needed for object preflight); the bucket itself is access-controlled |

## 6. How the bcrypt hashes are tested safely

1. The snapshot's `users.encrypted_password` column is loaded into a **local test
   fixture** or an ignored `tmp/` file — never committed, never logged.
2. A focused test (marked to run only when the fixture is present) asserts:
   - every distinct bcrypt **cost** and **prefix** (`$2a$`, `$2b$`, `$2y$`) present
     in the sample verifies against a known plaintext for a handful of
     operator-created seed accounts whose plaintext Uchechi supplies out of band;
   - `BCrypt::Password.new(hash).is_password?(wrong)` is false;
   - `Identity::PasswordEngine` accepts the copied hash with no rehash/truncation;
   - `$2y$` prefixes (if any) are normalized to a form `bcrypt` gem accepts.
3. The test **never** prints a hash or plaintext; failures report only the cost and
   prefix bucket that failed.
4. After the proof, the hash file is shredded (§8).

Only a **dozen or so** real hashes across the distinct cost/prefix buckets are
strictly required. If Uchechi prefers, the snapshot can carry *only* those
representative hashes plus the seed accounts, and null the rest.

## 7. Transfer, storage, access control

- **Transfer:** single encrypted archive (age or GPG, or an encrypted disk image).
  Move over a direct channel to one workstation (the machine running this batch).
  No email, no Slack, no shared drive, no cloud bucket for the JSON/CSV files.
- **Storage:** on an encrypted-at-rest disk, in a directory outside any git work
  tree, readable only by the operator's user account. The path is recorded in §10.
- **Blob objects (if a media dry-run is approved):** copied into a dedicated
  **private** prefix of a D8N-controlled R2 bucket with a lifecycle rule that
  auto-deletes after 14 days; no public access, no signed URLs shared.
- **Access:** the builder session reads it from local disk only. It is never
  attached to a PR, an artifact, a test fixture that gets committed, or a CI job.
- **In the repo:** only *derived, non-sensitive* outputs — row counts, the
  reconciliation table, redacted structural samples for test fixtures (already
  pseudonymized), and test code.

## 8. Deletion after use

1. Immediately after extraction: destroy the restored source DB instance and its
   storage volume.
2. Within 14 days of the implementation batch being reviewed: `shred`/secure-delete
   the local snapshot directory and the encrypted archive; delete the R2 media
   prefix (or let the lifecycle rule fire and verify).
3. Record deletion date + method in §10.
4. Any committed test fixture derived from it must contain **only** pseudonymized
   values (verify with a diff/grep for `@snapshot.invalid` and absence of real
   domains before commit).

## 9. Explicitly NOT unblocked by this snapshot

Do **not** begin these after the snapshot lands — they need `DECISIONS.md` rows:

- Verification implementation (ADR 0024) — evidence retention model, provider
  choice, cross-brand portability ("Mixed" rows).
- Trust implementation (ADR 0025) — user-visible trust score/history presentation.
- Entitlements implementation (ADR 0026) — which founding/premium access is
  retained and how it is represented.
- Sensitive profile fields (tribe, ethnicity, denomination, genotype, preferred
  tribes) — all "Awaiting Uchechi".
- Historical profile-view visibility, support-chat behavior.

## 10. Snapshot record (fill on execution)

| Field | Value |
|---|---|
| Snapshot ID | _pending_ |
| Produced by / date | _pending_ |
| Source backup timestamp | _pending_ |
| Sampled `users` count | _pending_ |
| Per-table row counts | _pending_ |
| Storage path | _pending_ |
| Media dry-run approved? | _pending_ |
| Deletion date / method | _pending_ |
| Verification: no tokens/JTI/OTP/session data present | _pending_ |

## 11. Verification that no unnecessary secrets are included

Before the snapshot is accepted, the operator confirms (checklist in §10):

- [ ] No `jti`, `reset_password_token`, `confirmation_token`, `unconfirmed_email`
- [ ] No `phone_verifications.code_digest`, no OTP codes
- [ ] No `push_tokens.token` values
- [ ] No session / Action Cable token data
- [ ] No `verification_checks.provider_reference` or `ai_review_*` payloads
- [ ] No IP addresses
- [ ] No real email domains or real phone numbers (grep for `@gmail`, `@yahoo`,
      `+234` followed by real-looking sequences)
- [ ] Free-text columns are `[redacted]` or length-only
- [ ] `encrypted_password` present only where the bcrypt proof needs it
- [ ] File is outside any git work tree

---

Once this snapshot exists and §10 is filled, the next implementation batch is:
**Wave A slice 3 (bcrypt/session proof) → slice 2/5 importer (photos + video as the
first `Migration::ReferenceMap` consumers) → reconciliation harness.** See
`PARITY-BUILD-PLAN.md`.
