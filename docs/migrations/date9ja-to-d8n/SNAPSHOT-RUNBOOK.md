# Sanitized Date9ja Snapshot & Data-Dictionary Runbook

Status: **REHEARSAL ARTIFACT PRODUCED AND VERIFIED FOR ENGINEERING USE
(2026-09-02).** The operator restored a Date9ja production backup into an
isolated PG17 instance, ran the sanitizer + verifier, and confirmed a full
`pg_dump` / `pg_restore` round trip preserves every row count (see §10). No
production access occurred from the builder. This document specifies the
*minimum* data required to unblock Phase 1 work and how to produce, move,
protect, and destroy it. Taking any future snapshot is an operator (Uchechi)
action.

> **The sanitized rehearsal snapshot does NOT prove bcrypt compatibility.** The
> sanitizer replaces every normal user's `encrypted_password` with one fixed
> inert digest, so no real hash is present. The bcrypt proof is the separate
> operator procedure in §6 (operator-owned seed accounts, plaintext known out of
> band). **The operator ran it on 2026-09-02 and reported `$2a$ 12 PASS` — the
> bcrypt gate is VERIFIED (§10).** The identity importer's credential step is
> now unblocked; every other gated migration stays gated.

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
> - `scripts/date9ja/schema_signature.sql` — the shared canonical schema-signature guard (v2)
> - `scripts/date9ja/sanitize_snapshot.sql` — the sanitizer
> - `scripts/date9ja/verify_sanitized_snapshot.sql` — the fail-closed verifier
> - `scripts/date9ja/source_census.sql` — the read-only reconciliation source census
> - [`SANITIZATION-CONTRACT.md`](SANITIZATION-CONTRACT.md) — per-column classification of all 51 tables / 574 columns, and §3 the schema-signature contract
>
> **First-run only — confirm the v2 signature on the PG17 snapshot (read-only,
> self-contained):**
> ```
> psql -d date9ja_snapshot_sanitized -f scripts/date9ja/schema_signature.sql
> # -> "Date9ja schema signature OK (v2 41a653a8d4c25621071fb76e6e59fbc0, ...)" = confirmed
> # -> "SCHEMA DRIFT: ... signature <X> != expected" = <X> is the observed value
> ```
> If the only cause is PG17 rendering a non-sequence default differently, pin
> `<X>` in `schema_signature.sql` (`v_expect_sig`) and note the one-line diff in
> SANITIZATION-CONTRACT.md §3. Do not weaken the contract.
>
> Run order (operator only):
> ```
> # date9ja_snapshot_sanitized is a COPY of the pristine date9ja_snapshot_tmp restore
> psql -v ON_ERROR_STOP=1 -v sanitize_ack=SANITIZE_THE_COPY \
>      -d date9ja_snapshot_sanitized -f scripts/date9ja/sanitize_snapshot.sql
> psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized \
>      -f scripts/date9ja/verify_sanitized_snapshot.sql
> # reconciliation source baseline (read-only; safe to run any time after verify):
> psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized \
>      -f scripts/date9ja/source_census.sql
> psql -d date9ja_snapshot_sanitized -c 'DROP SCHEMA IF EXISTS sanitize_audit CASCADE;'
> ```
> Each script `\ir`-includes `schema_signature.sql`, so all three enforce the
> identical v2 contract. The sanitizer refuses to run against
> `date9ja_snapshot_tmp`, refuses a second run, and aborts (rolls back) on any
> schema drift or post-check violation. Then
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

## 6. bcrypt compatibility proof — operator-only procedure

**Goal.** Prove that an existing Date9ja `users.encrypted_password` bcrypt digest
authenticates through D8N's `Identity::PasswordEngine` **unchanged** — no rehash,
no truncation, no reset — for **every bcrypt prefix/cost format that actually
exists in Date9ja production**, without any bcrypt hash or plaintext password ever
reaching an agent, a log, a fixture, a commit, or a PR.

**Why the sanitized rehearsal artifact cannot do this.** `sanitize_snapshot.sql`
overwrites every normal user's `encrypted_password` with one fixed inert digest
(`AUTHENTICATION.md` acceptance "all observed hash formats verify" is structurally
impossible against it). Real hashes are only ever touched by the operator, on a
controlled restore, under this procedure.

**Standing constraints.** No live-primary access (use a restore of an encrypted
backup). Do not mutate any credential. Do not issue password resets. Do not write
real hashes or plaintext to repository fixtures, `tmp/` that gets committed, logs,
or PR text. Print no full hash, ever.

### 6a. Safe aggregate hash-format discovery

Run against a **restore** of a recent encrypted Date9ja backup (the same
`date9ja_snapshot_tmp` pristine restore is fine — this reads `users` before
sanitization; it does **not** need the raw production primary). Output is
structural only: the 4-char algorithm prefix and the 2-digit cost. The bcrypt
salt begins at character 8 and the digest after that — neither is selected.

```sql
-- date9ja bcrypt format census — aggregate only, no hash material leaves this query
SELECT substring(encrypted_password FROM 1 FOR 4)  AS prefix_family,  -- $2a$ / $2b$ / $2y$
       substring(encrypted_password FROM 5 FOR 2)  AS cost,           -- e.g. 10, 11, 12
       count(*)                                     AS n
FROM   users
WHERE  encrypted_password IS NOT NULL AND encrypted_password <> ''
GROUP  BY 1, 2
ORDER  BY 1, 2;

-- sanity: any row whose hash is NOT a well-formed 60-char bcrypt string
SELECT count(*) AS malformed
FROM   users
WHERE  encrypted_password IS NOT NULL AND encrypted_password <> ''
  AND  encrypted_password !~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$';
```

One-liner:

```
psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_tmp \
     -c "SELECT substring(encrypted_password FROM 1 FOR 4) AS prefix_family, substring(encrypted_password FROM 5 FOR 2) AS cost, count(*) AS n FROM users WHERE encrypted_password IS NOT NULL AND encrypted_password <> '' GROUP BY 1,2 ORDER BY 1,2;"
```

The operator records **only** the resulting `(prefix_family, cost, n)` table in
§10 (it is non-sensitive). That table defines the **bucket set** the proof must
cover. Also note whether Date9ja's Devise config sets a `pepper` — if it does, the
proof plaintext must be combined with that pepper the same way Devise did, and
D8N must be configured with the identical pepper before cutover (see Risks).

**Operator result (2026-09-02, run against the pristine restore):**

| prefix_family | cost | n |
|---|---|---|
| `$2a$` | 12 | 288 |

Malformed bcrypt hashes: **0**. Exactly **one** bucket → the proof needs exactly
one seed account. Devise `pepper`: **not configured** — the only `config.pepper`
lines in `config/initializers/devise.rb` are the commented stock examples; a
repo-wide non-comment scan confirmed no active pepper. (An early `rg` hit was the
commented `# config.pepper = ...` template line only.)

### 6b. One operator-owned seed account per bucket

For each `(prefix_family, cost)` bucket from 6a, the operator provides **one**
Date9ja account they control:

- either an existing operator-owned Date9ja account whose current
  `encrypted_password` is already in that bucket and whose plaintext the operator
  knows, **or**
- a freshly created Date9ja account (on the restore, or on a throwaway Devise
  console using the same `BCrypt::Engine.cost`) registered with a known plaintext,
  so its digest lands in that bucket.

Plaintext passwords are held **out of band** by the operator (password manager /
sealed note) — never typed into the repo, a shared channel, or a prompt. A
minimal manifest lives only on the operator's encrypted disk (`§7` storage):

The manifest is **tab-separated**, one line per bucket, with the header row the
script tolerates. Values are placeholders here — real values live only on the
operator's encrypted disk:

```
prefix_family<TAB>cost<TAB>email<TAB>password<TAB>bcrypt_digest
$2a$<TAB>12<TAB><seed-email><TAB><known-plaintext><TAB><legacy $2a$12$… digest>
```

`scripts/date9ja/bcrypt_proof.rb` validates each row before touching the database:
digest must be a well-formed 60-char bcrypt string; `prefix_family` and `cost`
must agree with the digest; duplicate `(prefix_family, cost)` buckets are
rejected; any missing field fails closed; a group/other-readable manifest emits a
permission warning. For the single observed bucket the manifest is one data line.

### 6c. Verification procedure

On a machine with the D8N app checked out, against a **throwaway D8N test
database** (`RAILS_ENV=test`), the operator runs a script that, per bucket:

1. Creates a real D8N `User` + email `IdentityIdentifier` + **active** password
   `Credential` + `CredentialPasswordHash` whose `password_hash` is the legacy
   digest **copied verbatim** (no `PasswordEngine.set!`, which would rehash).
2. Creates an **active** `BrandMembership` for the `date9ja` brand (so
   `PasswordLogin` can reach the credential; `PasswordEngine.matches?` only needs
   the eligible credential).
3. Asserts:
   - `Identity::PasswordEngine.matches?(credential:, password: <known plaintext>)` → **`true`**
   - `Identity::PasswordEngine.matches?(credential:, password: <known plaintext + "x">)` → **`false`**
   - `Identity::PasswordLogin.call(brand: date9ja, identifier: <seed email>, password: <known plaintext>)` → `success?` **`true`**, issues a session
   - the row's `password_hash` is **byte-identical** to the input digest after the
     round trip (no truncation/normalisation mutation)
4. Rolls back / drops the throwaway database.

This is implemented as `scripts/date9ja/bcrypt_proof.rb` (module
`Date9ja::BcryptProof`). The file contains **no** hash, plaintext, email, or
identifier literal — every sensitive value is read from the operator's
uncommitted manifest via `BCRYPT_PROOF_MANIFEST`. Per bucket it provisions the
records inside a transaction that is **rolled back** (nothing persists), copies
the digest verbatim (never `PasswordEngine.set!`), then asserts `matches?` true /
`matches?` false on a first-byte-flipped wrong password / `PasswordLogin.call`
success with a session / stored hash byte-identical. Output is only
`<prefix_family> <cost> PASS` or `… FAIL <verify|wrong-password|login|hash-mutated|setup …>`;
plaintext, digests, and exception text carrying them are scrubbed. Exit status:
`0` all PASS, `1` any FAIL, `2` manifest error, `3` not `RAILS_ENV=test`.
Synthetic-value tests: `test/scripts/date9ja/bcrypt_proof_test.rb`.

**Executed 2026-09-02 — result `$2a$ 12 PASS` (VERIFIED, §10).**

Operator command:

```
# manifest path holds the real hash/plaintext; never committed
BCRYPT_PROOF_MANIFEST=/abs/path/to/date9ja-bcrypt-manifest.tsv \
  bin/rails runner -e test scripts/date9ja/bcrypt_proof.rb
# -> prints:  $2a$ 12 PASS      (or e.g. "$2a$ 12 FAIL verify")
```

### 6d. Success / failure criteria

**PASS (proof established)** — for **every** bucket in the 6a census:
`PasswordEngine.matches?` true with the known plaintext, false with a wrong one,
`PasswordLogin` issues a session, and the stored hash is byte-identical to the
legacy digest. No hash/plaintext appeared in any output or artifact.

**FAIL** — any bucket where `matches?` is false with the correct plaintext, or the
hash is mutated on store, or `$2y$`/`$2x$` is rejected by the bcrypt gem. On FAIL,
capture only the failing `(prefix_family, cost)` and the failure mode (verify /
mutate / prefix-reject); do **not** capture the hash. FAIL means the direct-copy
migration is not universally safe and `AUTHENTICATION.md`'s recovery path becomes
the primary route for the affected bucket — a product/security decision, not an
importer workaround.

### 6e. Cleanup

After the proof: drop the throwaway D8N test database; `shred` the manifest and
any local hash file (§8); confirm `git status` shows nothing under
`scripts/date9ja/` or `tmp/` containing hash material. Record the bucket census
and PASS/FAIL summary in §10 — nothing else.

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

## 10. Snapshot record

### Rehearsal artifact — 2026-09-02

| Field | Value |
|---|---|
| Snapshot ID | `date9ja_sanitized_20260902` |
| Kind | Engineering / migration rehearsal artifact — **not** a cutover snapshot |
| Produced by / date | Operator (Uchechi), 2026-09-02 |
| Source backup timestamp | Date9ja production backup, 2026-09-02 |
| Method | Full restore into isolated PG17 (`date9ja_snapshot_tmp` pristine → `date9ja_snapshot_sanitized` working copy), in-place sanitize via `scripts/date9ja/sanitize_snapshot.sql`, then `pg_dump` |
| Sanitizer / verifier result | `sanitize_snapshot.sql` committed; independent review verdict **B — safe to execute after small fixes (fixes applied)**; operator run: sanitize `COMMIT` + inline post-checks passed; `verify_sanitized_snapshot.sql` **PASSED (0 violations)** |
| Schema guard at production time | **v1** (exact 51-table set + exact column-name list + name-only fingerprint `a317e7fb…`). The schema-only artifact and the sanitized DB derive from the **same** 2026-09-02 backup — no version skew — so v1 was sufficient *for this run*. See "Impact" note below. |
| Schema guard in current tooling | **v2** (`schema_signature.sql`, signature `41a653a8…`) — adds type / nullability / ordinal / precision / default coverage. Applies to all *future* runs. |
| v2 re-confirmation on the existing artifact | **Recommended, non-blocking:** operator runs the read-only v2 one-liner (§3) against `date9ja_snapshot_sanitized`; expect `41a653a8…`. A match retroactively strengthens confidence at zero cost. **A new raw-production sanitization run is NOT required.** |
| Packaged dump | `~/date9ja-snapshot-work/output/date9ja_sanitized_20260902.dump` |
| Round-trip check | Restored into `date9ja_snapshot_package_test`; post-restore reconciliation **exactly matched** source rehearsal baseline (below) |
| `users` count | 288 |
| Per-table row counts | users 288 · active_storage_blobs 443 · photos 279 · profile_videos 35 · likes 546 · matches 82 · messages 1025 · profile_views 1627 · blocks 3 · reports 3 (full breakdown: run `scripts/date9ja/source_census.sql`) |
| Relationship fingerprint parity (pristine vs sanitized) | Matched exactly for users, likes, matches, messages (incl. `match_id`/`sender_id`/`reply_to_id`), profile_views, blocks |
| Storage path | Isolated PG17 instance + local encrypted-at-rest `~/date9ja-snapshot-work/`, outside any git work tree |
| Media dry-run approved? | Not for pass 1 — no blob bytes; structural metadata only (`SANITIZATION-CONTRACT.md` R3) |
| Deletion date / method | Pending — `shred` local dir + dump within 14 days of the first importer batch being reviewed (§8) |
| No tokens/JTI/OTP/session/IP present | Confirmed by `verify_sanitized_snapshot.sql` (auth-secret, IP, push-token, provider-reference, idempotency-key assertions all pass) |
| Classification | **SANITIZED SNAPSHOT REHEARSAL ARTIFACT — VERIFIED FOR ENGINEERING USE** |

### bcrypt compatibility proof — record — **VERIFIED (2026-09-02)**

| Field | Value |
|---|---|
| Procedure | §6 (6a discovery → 6b seed accounts → 6c verification) |
| Proof script | `scripts/date9ja/bcrypt_proof.rb` + `test/scripts/date9ja/bcrypt_proof_test.rb` (synthetic-value tests green; rubocop clean) |
| Format census `(prefix_family, cost, n)` | **`$2a$` / 12 / 288** — one bucket only (operator, 2026-09-02, pristine restore) |
| Devise `pepper` configured in Date9ja? | **No** — only commented stock `# config.pepper` examples; repo-wide non-comment scan confirmed none |
| Malformed-hash count | **0** |
| Seed accounts (one per bucket) | One operator-owned `$2a$12$` Date9ja account; manifest on the operator's encrypted disk only, **deleted after the run** |
| Per-bucket result | **`$2a$ 12 PASS`** (operator, 2026-09-02) — legacy digest verified through `Identity::PasswordEngine.matches?`, wrong password rejected, `Identity::PasswordLogin` issued a D8N session, stored hash byte-identical to the source digest |
| Hash/plaintext leak check | `git status` clean; the only output was `$2a$ 12 PASS`; no hash/plaintext/email in any artifact |
| Outcome | **VERIFIED.** Wave A slice 3 credential step is **READY**. Preserving a supported legacy Date9ja bcrypt credential is safe for the identity importer. No other gated migration is unblocked. |

### Identity importer rehearsal — record — **VERIFIED (2026-09-03)**

| Field | Value |
|---|---|
| Importer | `Date9ja::Import::IdentityImport` (`domains/date9ja/`), `date9ja:import_identity` rake task |
| Source | `date9ja_snapshot_sanitized` (inert bcrypt digests — auth not re-proven here) |
| Schema preflight | **PASS** — v2 signature `41a653a8d4c25621071fb76e6e59fbc0`, 51 base tables, 574 columns |
| First pass | 288 considered → **280 imported / 8 skipped (`source_soft_deleted`) / 0 failed**; 280 users·credentials·password_hashes·memberships·profiles, 460 identifiers, 1580 legacy_references; all anomaly counters 0 |
| Second pass (idempotency) | 288 considered → **0 imported / 280 already_imported / 8 skipped / 0 failed**; nothing created; all anomaly counters 0 |
| Source reconciliation | census 288 = 280 kept + 8 soft-deleted; both passes balance with no unexplained rows; distinct `lower(email)`/`public_id` = 288 (no collisions) |
| Leak check | reconciliation output is counts + reason codes only — no email/phone/hash/free-text |
| Outcome | Wave A Slice 3 **implementation reviewed + rehearsal VERIFIED**. **NOT `PARITY_ACCEPTED`, NOT production-ready, NOT cutover-ready.** Deferred mapping/product decisions remain open (see `STATUS.md`). |

### Profile-photo MEDIA PREFLIGHT rehearsal (pass 1) — procedure

`bin/rails date9ja:preflight_photos` (after `date9ja:import_identity`, same
`DATE9JA_SNAPSHOT_DATABASE_URL`, throwaway D8N DB). Pass 1 reads the `photos`
table + `record_type='Photo' AND name='image'` attachments and their blobs'
`byte_size/checksum/content_type` **only** — it never reads
`active_storage_blobs.key`, `filename`, `metadata` or `service_name`, copies no
bytes, creates no `ProfilePhoto` or D8N Active Storage record, and enqueues no
job. It records `Migration::MediaObjectRef` / `Migration::MediaAttachmentRef` and
prints a PII-free reconciliation JSON (`RECONCILIATION.md` pass-1 contract). Full
command in `RECONCILIATION.md`. Architecture: ADR 0027.

**Executed 2026-09-03 — VERIFIED.** 279 considered / 276 preflighted / 3
`owner_not_imported` / 0 failed; second pass 276 `already_preflighted`, 0 created;
all anomaly counters 0. Measures matched the census baseline. Record:
`RECONCILIATION.md` "Pass-1 rehearsal result".

### Profile-video MEDIA PREFLIGHT rehearsal (pass 1) — procedure

`bin/rails date9ja:preflight_videos` (after `date9ja:import_identity`, same
`DATE9JA_SNAPSHOT_DATABASE_URL`, throwaway D8N DB). The video analogue of
`preflight_photos`: reads `profile_videos` +
`record_type='ProfileVideo' AND name='video'` attachments and their blobs'
`byte_size/checksum/content_type` **only** — never `key` / `filename` /
`metadata` / `service_name` / `rejection_reason`, no bytes, no `ProfileVideo`, no
Active Storage record, no `playback`/`poster` derivative, no job. Records
`Migration::MediaObjectRef` / `MediaAttachmentRef` and prints a PII-free
reconciliation JSON (`RECONCILIATION.md` video pass-1 contract).

**Executed 2026-09-03 — VERIFIED (Codex independent review: ACCEPT WITH SMALL FIX
— duration wording corrected).** 35 considered / 35 preflighted / 0
`owner_not_imported` / 0 failed; second pass 35 `already_preflighted`, 0 created,
0 `ProfileVideo`/Active Storage rows; all anomaly counters 0; content types 26
`video/mp4` + 9 `video/quicktime` (0 unsupported). **`duration_missing` 35 / 35:**
Date9ja did not persist `duration_seconds`, so no source row is known to exceed
the limit and actual duration is unproven for every legacy video — **pass 2 must
derive authoritative duration from the media container**; if it exceeds the
limit, stop for the grandfather / trim-reencode / quarantine product decision.
Record: `RECONCILIATION.md` "Profile-video MEDIA PREFLIGHT contract".

### Profile-video BYTE TRANSFER rehearsal (pass 2A) — IMPLEMENTED / SELF_VERIFIED (2026-09-04)

`bin/rails date9ja:transfer_videos_phase_a` (after `date9ja:preflight_videos`,
same throwaway D8N DB, `DATE9JA_MEDIA_CORPUS_DIR` synthetic corpus). ADR 0029.
Per source video: resolve owner `Profile`; `Migration::MediaTransfer.call`
(`media_kind: MediaKind::Video`) — stream source bytes under the 50 MB video
ceiling → exact byte-size + MD5 vs `MediaObjectRef` → `ftyp` type detect ==
preflighted type → `Media::VideoContainerValidator` → `Media::VideoProcessor.probe`
(ffprobe) authoritative duration → Date9ja `VideoPolicy` 60s gate → **only then**
`CanonicalKey.final_key`
(`migrations/media/v3/date9ja/profile_video_original/<uuidv5>/original.<ext>`) +
`AdoptOrUpload`. **Creates NO `ProfileVideo`, NO `profile_video` `ReferenceMap`
binding, NO `Media::ProcessProfileVideoJob`.** Unreadable duration →
`quarantined`/`duration_unreadable`; over 60s → `quarantined`/`duration_over_limit`
— neither adopts a blob. Prints a PII-free reconciliation JSON with
`lifecycle: SOURCE_ACCEPTED / DESTINATION_ADOPTED (pass 2A; NOT transferred)`.

**Full 35-video source-byte rehearsal: DEFERRED to Pass 2C synthetic L2** — the
sanitized snapshot has no media bodies. L1 automated coverage only
(`test/domains/date9ja/import/video_transfer_test.rb` + the MediaKind / probe /
locator tests), against real ffmpeg-generated fixtures. Do NOT record a 35/35
source-byte result. NOT independently reviewed; NOT `VERIFIED`.
Record: `RECONCILIATION.md` "Profile-video PASS 2A BYTE TRANSFER contract".

### Profile-video DOMAIN MIGRATION rehearsal (pass 2B) — IMPLEMENTED / SELF_VERIFIED (2026-09-04)

`bin/rails date9ja:transfer_videos` (after `date9ja:preflight_videos`, same
throwaway D8N DB, `DATE9JA_MEDIA_CORPUS_DIR` synthetic corpus). ADR 0029
`stage: :domain`. Per adopted video: RESOLVE (idempotent existing-chain check) →
Phase A (2A verify + adopt) → Phase B short `LockGuard`-held transaction (re-lock
`MediaAttachmentRef`, re-resolve owner, re-prove the deterministic blob,
one-live-video invariant, moderation map → `Profiles::VideoUpload.build_video!`
→ `Migration::ReferenceMap.bind!` `source_entity: "profile_video"`) → Phase C
(`Media::ProcessProfileVideoJob` inline → `Media::PlaybackDerivative` bounded
remote validation of the exact playback + poster pair → `ready` → existing
`video.purge_later`). Prints a PII-free reconciliation JSON with
`stage: "domain"`, `lifecycle: PROFILE_VIDEO_DOMAIN_MIGRATED (pass 2B) — …`, and
**never `transferred`**. A `processing_ready` video whose derivatives do not
validate is `derivative_validation_failed`, never `ready`.

New shared runtime: migration `20260904120000_add_processing_claim_to_profile_videos`
(run `bin/rails db:migrate` + `RAILS_ENV=test bin/rails db:test:prepare`),
`ProfileVideo` claim/sweepable helpers, `Media::ProcessProfileVideoJob`
claim-token concurrency, `Media::ProfileVideoProcessingSweeper`,
`Media::PlaybackDerivative`, `Profiles::VideoUpload.build_video!`.

**Full 35-video synthetic-corpus L2 rehearsal: DEFERRED to Pass 2C.** L1
automated coverage only (`test/domains/date9ja/import/video_domain_transfer_test.rb`
+ `playback_derivative_test` + `process_profile_video_job_claim_test`), against
real ffmpeg-generated fixtures. Do NOT record a 35/35 result. NOT independently
reviewed; NOT `VERIFIED`.
Record: `RECONCILIATION.md` "Profile-video PASS 2B DOMAIN MIGRATION contract".

### Profile-video SYNTHETIC L2 rehearsal (pass 2C) — IMPLEMENTED / SELF_VERIFIED (2026-09-04)

The video analogue of the Profile Photo synthetic L2. Full write-up:
**[`VIDEO-L2.md`](VIDEO-L2.md)**.

**Builder side (done, automated):** `Date9ja::Snapshot::SyntheticVideoMedia`
generator + verifier; `test/domains/date9ja/snapshot/synthetic_video_media_test.rb`
(L1) + `test/domains/date9ja/import/video_l2_rehearsal_test.rb` (the full
self-contained 35-record Pass 1 → 2A → 2B rehearsal + interruption + adversarial,
569 assertions). Documentable corpus fingerprint (fixed seed):
`5fbcc9dac1d7334859c5753b3c5b347589898af0ce3302e15cc117366433c378`.

**Operator side (deferred):** against a `date9ja_snapshot_sanitized_media_v3`
restore (a disposable copy of `date9ja_snapshot_sanitized`), same pattern as the
photo `media_v2` operator run:

```
bin/rails date9ja:build_video_media_v3     # DATE9JA_SNAPSHOT_DATABASE_URL=media_v3, DATE9JA_MEDIA_CORPUS_DIR=out
bin/rails date9ja:verify_video_media_v3    # + DATE9JA_SANITIZED_DATABASE_URL=parent [+ DATE9JA_MEDIA_CORPUS_DIR_2]
bin/rails date9ja:preflight_videos
bin/rails date9ja:transfer_videos_phase_a  # stage :adopt — 35 destination_adopted, 0 ProfileVideo
bin/rails date9ja:transfer_videos          # stage :domain — 35 ready
bin/rails date9ja:transfer_videos          # rerun -> 35 already_ready, zero growth
```

Plus the real forked-worker SIGKILL rehearsal (not safely automatable against
the transactional test DB — see `VIDEO-L2.md` §6).

**Evidence rule:** 35 legacy records exist; 35 synthetic bodies built for
rehearsal; real duration/codec/container UNKNOWN. Never claim the synthetic
files are the users' videos or that all 35 real videos are ≤ 60 s. **PD-2 stays
OPEN — real over-limit count UNKNOWN.**

**Feature-boundary review (Codex BLOCKED — fixes applied 2026-09-04):** Finding 1
(BLOCKER) hardened `Media::ProcessProfileVideoJob#finalize!` to independently
validate every candidate playback/poster blob's actual remote bytes before
attaching (new `Media::PlaybackDerivative` blob-level validators, out of lock,
+ ABA recheck); Finding 4 tightened `ProfileVideo#safe_derivative_ready?`;
Findings 2 & 3 added verifier checks 24 / 27 / 28 (manifest key containment,
full `active_storage_attachments`, unrelated table counts). `verify_video_media_v3`
now exits non-zero on any of the 28 checks. Retest: 546 runs / 0 failures.
Record: `RECONCILIATION.md` "Profile-video PASS 2C — SYNTHETIC L2 REHEARSAL" and
`VIDEO-L2.md` §10.

### Profile-photo BYTE TRANSFER rehearsal (pass 2) — L2 VERIFIED (Codex independent review, 2026-09-03)

The synthetic-corpus (L2) rehearsal is **built, green, and independently
verified** (Codex 2026-09-03: FINAL VERDICT ACCEPT; L2 review loop closed). No
real R2, no production, no live media, no L3. L2 verification does **not** imply
production / cutover readiness or L3 approval.

```
# 0. media_v2 artifact — a TEMPLATE copy of the verified sanitized snapshot,
#    on the isolated PG17 instance (127.0.0.1:55432). Operator/one-time:
psql -h 127.0.0.1 -p 55432 -d postgres \
  -c "CREATE DATABASE date9ja_snapshot_sanitized_media_v2 TEMPLATE date9ja_snapshot_sanitized;"

# 1. Build the deterministic synthetic corpus + manifest, and rewrite the
#    media_v2 blob byte_size/checksum to match. Contains NO real Date9ja media.
export RAILS_ENV=test
export DATABASE_URL=postgresql://localhost/d8n_date9ja_rehearsal_l2_20260903  # throwaway
export DATE9JA_SNAPSHOT_DATABASE_URL=postgresql://127.0.0.1:55432/date9ja_snapshot_sanitized_media_v2
export DATE9JA_MEDIA_CORPUS_DIR=/path/to/scratch/media_v2_corpus
bin/rails date9ja:build_media_v2

# 2. Verify the corpus (15 checks). Optionally build a second corpus and set
#    DATE9JA_MEDIA_CORPUS_DIR_2 for a byte-for-byte determinism cross-check.
export DATE9JA_SANITIZED_DATABASE_URL=postgresql://127.0.0.1:55432/date9ja_snapshot_sanitized
bin/rails date9ja:verify_media_v2      # -> "MEDIA_V2 ARTIFACT: VERIFIED FOR L2"

# 3. Fresh throwaway D8N DB, then the established dependency order.
createdb d8n_date9ja_rehearsal_l2_20260903
bin/rails db:schema:load
bin/rails runner 'Brand.find_or_create_by!(slug:"date9ja"){ _1.name="Date9ja"; _1.status=:active; _1.auth_methods=%w[email_password phone_password] }'
bin/rails date9ja:import_identity        # 280 imported / 8 skipped / 0 failed
bin/rails date9ja:preflight_photos       # 276 preflighted / 3 owner_not_imported
bin/rails date9ja:transfer_photos        # transferred 276 / owner_not_imported 3
bin/rails date9ja:transfer_photos        # rerun -> 276 already_transferred, zero growth
```

Code: `Date9ja::Snapshot::SyntheticMedia` (`render` / `Generator` / `Verifier` —
`verify_media_v2` checks include `16_manifest_rows_match_media_v2_blobs` and
`17_complete_blob_table_drift_is_authorized`), `Date9ja::Snapshot::SanitizedParentConnection`,
`Date9ja::Storage::LocalCorpusReader`, `Date9ja::Storage::SafeObjectKey` (shared
safe-key + path-containment contract for both the corpus reader and the generator).
Corpus: 279 objects (252 jpeg / 21 png / 6 webp), manifest fingerprint
`ebcff28a796a230807fbdbfeb19ff63a…`. Results and the full disposition breakdown:
`STATUS.md` "L2 rehearsal" and `RECONCILIATION.md` "Pass-2 L2 synthetic-corpus
rehearsal".

**Cleanup:** `dropdb d8n_date9ja_rehearsal_l2_20260903` (and any `_intr_` DB);
`rm -rf $DATE9JA_MEDIA_CORPUS_DIR`; optionally
`DROP DATABASE date9ja_snapshot_sanitized_media_v2`. Nothing is committed; the
corpus never enters the repo.

L3 (scoped read-only R2 transport + operator logistics) remains **NOT YET READY**.

### Profile-photo BYTE TRANSFER rehearsal (pass 2) — original design notes

Full design: `MEDIA-TRANSFER.md`. Pass 2 will additionally require:

- **Source-storage access** — a scoped **read-only** legacy Cloudflare R2 token
  in the migration run's environment only (`DATE9JA_SOURCE_R2_*`), never in
  `config/` or Rails credentials; or a pre-exported controlled media bundle
  (`DECISIONS.md`, awaiting decision). The host is allowlisted
  (`*.r2.cloudflarestorage.com`); the reader is `HEAD`/`GET` only and fails
  closed.
- **Synthetic media rehearsal corpus** — for L1/L2 rehearsal, a generated
  image set keyed by `source_blob_id` whose bytes define the recorded
  size/MD5/type; local source endpoint; **production bytes never enter any
  artifact**.
- A read-only `service_name` census over the 279 photo blobs (Pass-1 did not
  record `service_name`) confirming a single expected legacy service before any
  transfer. **Run 2026-09-03 against `date9ja_snapshot_sanitized`
  (`127.0.0.1:55432`): `cloudflare` = 279, no other services. Blocker closed for
  this slice; Pass 2 re-asserts it against the final production snapshot.** See
  `RECONCILIATION.md` "Pass-2 `service_name` census".
- The reader is **HTTPS-only**, **refuses redirects** (never follows a `3xx`),
  **constructs the R2 endpoint from `DATE9JA_SOURCE_R2_ACCOUNT_ID` only**
  (rejects any caller/DB-supplied endpoint), exposes **no write/delete/copy**
  method, uses a bounded `0600` temp file cleaned in `ensure`, enforces the
  `Media::ImageProcessor` dimension/pixel ceilings, has a bounded retry/backoff,
  redacts provider exceptions, and logs no credential / locator / key / signed
  URL / checksum (`MEDIA-TRANSFER.md` §5b).
- **Synthetic rehearsal (L1/L2) — Revision 3:** a **distinct**
  `date9ja_snapshot_sanitized_media_v2` artifact. It preserves the canonical
  sanitized source graph from `date9ja_snapshot_sanitized` but rewrites the
  synthetic photo corpus's `active_storage_blobs` `checksum`/`byte_size`/
  `content_type` to the generated bytes' real values. `date9ja_snapshot_sanitized`
  is **NOT** rewritten or relabelled — it stays the verified sanitized source
  rehearsal artifact. `v2` carries its own generation procedure, manifest,
  artifact + schema + corpus fingerprints, sanitizer/verifier result, Pass-1
  rerun, and reconciliation baseline. The canonical **production** snapshot is
  never touched. `v2` is not created in the design turn (`MEDIA-TRANSFER.md`
  §21).

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
