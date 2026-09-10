# Date9ja → D8N — Production Cutover Runbook (executable)

**Status:** DRAFT FOR OPERATOR APPROVAL. Do not begin the write freeze or any
traffic switch until the operator explicitly approves this runbook.

**Approved migration state**
- Branch `date9ja-parity`, tip `01cdd2b` (docs), migration/closure code `9903c8a`.
- Verdict: **CUTOVER READY** — `GO-NO-GO-CUTOVER-REPORT.md`.
- Working tree clean; local branch is **2 commits ahead of `origin/date9ja-parity`** — push before deploying.

**What this repo automates vs. what it does not.** The migration *logic*
(importers, reconciliation, media transfer path, discovery/publication) is proven
and idempotent. The *production plumbing* below is **not** in the repo and is
called out as operator prerequisites (§0):
1. a path to land the migrated dataset into the **live multi-brand `d8n_production`** (the importers are fenced to a disposable `RAILS_ENV=test` DB — §0.A);
2. a **production media-byte transport** (the `date9ja:transfer_*` tasks only read a local synthetic corpus — §0.B);
3. **Date9ja production infrastructure**: R2 bucket + proxy host + DNS + email/SMS senders + frontend repoint (§0.C).

Deployment mechanism: **Kamal 2.12** (invoked as `bundle exec kamal`; `gem "kamal", require: false`) (`config/deploy.production.yml`), single
host `164.68.106.97` (web + job roles), image `nwakauc/d8n` via `ghcr.io`,
`builder.local: true` (image is built on the operator's machine from local
`HEAD`). Schema migrations run automatically on container boot
(`bin/docker-entrypoint` → `bin/rails db:prepare`).

---

## 0. Operator prerequisites — MUST be resolved before scheduling the window

### 0.A — How the migrated dataset reaches `d8n_production`

`Date9ja::Snapshot::Connection.connect!` (used by every `date9ja:import_*` /
`preflight_*` / `transfer_*` task) calls `assert_runtime_safe!`, which **raises
unless `RAILS_ENV=test` and the primary database name matches
`/\Ad8n_date9ja_rehearsal(?:_[a-z0-9_]+)?\z/`** (`domains/date9ja/snapshot/connection.rb:39`).
This is a deliberate builder-safety fence (`RECONCILIATION.md`, DECISIONS.md
"Import execution model"). **The importers cannot write to `d8n_production`
directly as committed.**

`d8n_production` is a live multi-brand database (HookUs on `api.d8n.tech`, DateZA
on `dateza-api.d8n.tech`). Choose ONE path, get it reviewed, and record the
decision here before the window:

| Path | Summary | Cost / risk |
|---|---|---|
| **A1 — build-then-promote** | Run the full migration into a disposable `d8n_date9ja_rehearsal_cutover` DB (schema loaded from a fresh `d8n_production` dump so sequences match), reconcile, then load only the migration-created rows into `d8n_production` with an FK-ordered, sequence-safe `pg` load script. | A load script + collision analysis is **net-new operator work** (no precedent in repo). Date9ja rows are all new (fresh D8N `user`/`profile`/… ids from the rehearsal DB's sequences, which continue from the production dump) so there is no id overlap, but the load order and `legacy_references` / `active_storage_*` inclusion must be exact. |
| **A2 — scoped fence relaxation (recommended)** | A minimal, reviewed, **time-boxed** change that lets `assert_runtime_safe!` accept `d8n_production` **only** when an explicit env flag (e.g. `DATE9JA_CUTOVER_UNLOCK=<one-time token>`) is set, run the proven importer sequence directly against `d8n_production`, then revert. | Touches otherwise-frozen code for one commit; needs its own review + a revert commit staged. Writes are additive, idempotent, and reconciled at every step; this is the same code proven in rehearsal, now pointed at the real primary. |

Either way the **source** is a restored copy of the final Date9ja snapshot in a
disposable Postgres DB whose name contains none of `prod`/`production`/`live`
(the `assert_safe!` forbidden-fragment guard), reached via
`DATE9JA_SNAPSHOT_DATABASE_URL`.

**Operator action:** pick A1 or A2, write the chosen mechanism (and, for A2, the
exact diff + revert commit) into this section, and get it independently reviewed.

### 0.B — Production media-byte transport

`date9ja:transfer_photos` / `transfer_videos` **`abort`** unless
`DATE9JA_MEDIA_CORPUS_DIR` (a local synthetic corpus) is set — "L3 scoped
read-only R2 transport is not wired in this build"
(`lib/tasks/date9ja_import.rake`). `Date9ja::Storage::SourceReader` (a real,
security-fenced R2 HTTP reader keyed on `DATE9JA_SOURCE_R2_ACCOUNT_ID` +
`bucket`) exists but is wired to no task and needs an injected HTTP `transport`.

Choose ONE:

| Path | Summary |
|---|---|
| **B1 — bucket-to-bucket copy (recommended, no code)** | `rclone` / `aws s3 sync` from the Date9ja source R2 bucket to `r2_date9ja_production`, **preserving object keys**. Then run `date9ja:preflight_photos` / `preflight_videos` against the restored snapshot (integrity metadata check only — no bytes), and a destination-side integrity pass: every migrated `ProfilePhoto` / `ProfileVideo` blob key resolves in `r2_date9ja_production` with matching `byte_size` + `checksum`. Photos/videos are served straight from the destination bucket; the D8N `ProfilePhoto`/`ProfileVideo` rows created by the importers point at the same keys. |
| **B2 — wire `SourceReader`** | Add a production `date9ja:transfer_photos_r2` / `transfer_videos_r2` task that constructs `SourceReader` + a real HTTP transport from `DATE9JA_SOURCE_R2_*`. Net-new code — outside the freeze; needs review + the L3 security gate in `MEDIA-TRANSFER.md`. |

Message-media / selfie / verification-evidence **bytes** stay deferred (per the
GO/NO-GO report): the references + integrity metadata are migrated; schedule the
byte backfill immediately post-cutover.

### 0.C — Date9ja production infrastructure (config, not code logic)

Prepare these and land them in a **pre-window deploy** (§1). All are additive and
dormant until a Date9ja host is mapped.

| Item | Where | Value |
|---|---|---|
| Private media bucket | `config/storage.yml` | add an `r2_date9ja_production:` service block (copy `r2_dateza_production`, swap `DATEZA`→`DATE9JA`) |
| R2 secrets | `.kamal/secrets.production` + `config/deploy.production.yml` `env.secret` | `D8N_R2_DATE9JA_PRODUCTION_ACCESS_KEY_ID`, `_SECRET_ACCESS_KEY`, `_BUCKET` — **the app refuses to boot** without these once `date9ja` is in `D8N_R2_BRANDS` (`config/environments/production.rb`) |
| Enable the brand's storage | `config/deploy.production.yml` `env.clear` | `D8N_R2_BRANDS: "hookus,dateza,date9ja"` |
| API host (TLS) | `config/deploy.production.yml` `proxy.hosts` | add `date9ja-api.d8n.tech` (or the real Date9ja API hostname if it will resolve to this host) |
| Brand→host mapping | `config/deploy.production.yml` `env.clear` | `DATE9JA_API_HOST: "date9ja-api.d8n.tech"` — consumed by `brands:ensure_date9ja` (already runs every boot) and `brands:install_date9ja` |
| Email sender | `.kamal/secrets.production` / `env.clear` | `D8N_DATE9JA_EMAIL_FROM` (e.g. `"Date9ja <no-reply@…>"`); provider `resend` already set |
| SMS sender | `.kamal/secrets.production` / `env.secret` | `TWILIO_DATE9JA_MESSAGING_SERVICE_SID` (falls back to a generic SID if unset); provider `twilio` already set |
| CORS | `config/deploy.production.yml` `D8N_CORS_ORIGINS` | append the Date9ja web origin(s) |
| DNS | operator DNS | `date9ja-api.d8n.tech` → `164.68.106.97` (A record); TLS cert is auto-provisioned by kamal-proxy once the host is in `proxy.hosts` |
| Date9ja frontend / mobile | Date9ja app config or a new release | base API URL repointed to the D8N host. If the mobile app has a hard-coded host, an app-store release is on the critical path — plan accordingly (the legacy host can also be CNAME'd to D8N as a bridge). |

### 0.D — Other confirmations

- **Which commit deploys:** `date9ja-parity` @ `9903c8a` (data + logic) / `01cdd2b` (docs). Decide whether it is merged to `dev` first or deployed from the branch (`builder.local: true` builds from local `HEAD`, so `git checkout date9ja-parity` then deploy is sufficient).
- **Backups tooling present:** `script/operations/postgres_backup` (custom-format, sha256, no-overwrite), `script/operations/postgres_restore_drill` (disposable `d8n_restore_*` only).
- **Legacy Date9ja freeze is on Date9ja's own infrastructure** — this repo does not control it.
- **Final Date9ja snapshot** is produced by the operator from Date9ja production.
- **DB access:** the migration run (§4) needs shell + `psql`/`pg_restore` on a host that can reach `d8n_production` (`172.18.0.1:5432`) and hold the disposable source + rehearsal DBs (the production host, or a secure adjacent box).

---

## 1. Pre-window deploy (do this 1–2 days before, outside the freeze)

Goal: get the Date9ja schema + code onto `d8n_production` while it is **dormant**
(no Date9ja host mapped yet), so the window itself is data + switch only.

```bash
# 1.1 Confirm the exact commit
git checkout date9ja-parity
git fetch origin && git push origin date9ja-parity        # local is ahead by 2
git rev-parse HEAD                                         # must be 01cdd2b (or 9903c8a)
git status --porcelain                                     # clean
git diff --check                                           # clean

# 1.2 Review the migrations that will apply on d8n_production (all additive):
git diff --name-only origin/dev...HEAD -- db/migrate
#   add_date9ja_onboarding_fields, add_preferred_country_codes_to_profile_preferences,
#   add_sensitive_preservation_destinations, add_date9ja_message_history_fields,
#   add_private_assurance_metadata_to_users, create_verification_assertions,
#   create_date9ja_history_records, create_message_reactions
bin/rails db:migrate:status                                # against a fresh d8n_production restore, confirm these 8 are 'down'

# 1.3 Land the §0.C config changes (storage.yml, deploy.production.yml, .kamal/secrets.production)
#     WITHOUT DATE9JA_API_HOST yet — brand exists, no host mapped, dormant.
#     Keep D8N_R2_BRANDS updated + the 3 R2 secrets set (boot fails otherwise).

# 1.4 Deploy
bundle exec kamal deploy -d production
#   -> builds image from HEAD, pushes, boots web+job
#   -> bin/docker-entrypoint runs `db:prepare` (applies the 8 additive migrations)
#   -> `brands:ensure_date9ja` creates the Date9ja Brand + catalogue (no host)

# 1.5 Verify dormant tenant
bundle exec kamal app exec -d production 'bin/rails runner "puts Brand.find_by(slug:%q(date9ja)).inspect; puts BrandDomain.joins(:brand).where(brands:{slug:%q(date9ja)}).count"'
#   -> Brand present & active; BrandDomain count = 0
bundle exec kamal app exec -d production 'bin/rails brands:verify[date9ja]'   # required capabilities present
curl -s https://api.d8n.tech/api/v1/health                            # HookUs unaffected
curl -s https://dateza-api.d8n.tech/api/v1/health                     # DateZA unaffected
```

**STOP if:** any migration is non-additive/unexpected, HookUs or DateZA health
degrades, or `brands:verify[date9ja]` reports missing capabilities.

---

## 2. Pre-cutover (window start, before the freeze)

```bash
# 2.1 Confirm deployed commit on the host
bundle exec kamal app exec -d production 'bin/rails runner "puts ENV[%q(D8N_GIT_SHA)]"'   # baked into the image at build time

# 2.2 D8N production DB + migrations ready
bundle exec kamal app exec -d production 'bin/rails db:migrate:status | tail -20'   # all 'up', schema matches 9903c8a
bundle exec kamal app exec -d production 'bin/rails runner "ActiveRecord::Base.connection.execute(%q(select 1))"'

# 2.3 Credentials / storage / services
bundle exec kamal app exec -d production 'bin/rails runner "
  puts Rails.configuration.x.r2_brand_slugs.inspect
  puts ActiveStorage::Blob.services.fetch(:r2_date9ja_production).name
  puts Media::StorageResolver.service_name(brand: Brand.find_by(slug: %q(date9ja)))
"'
#   -> [\"hookus\",\"dateza\",\"date9ja\"] ; r2_date9ja_production ; r2_date9ja_production
bundle exec kamal app exec -d production 'bin/rails runner "
  b = Brand.find_by(slug: %q(date9ja))
  puts Notifications::Email.from_address(b).inspect   # non-nil => D8N_DATE9JA_EMAIL_FROM is set (nil in prod means UNSET)
"'

# 2.4 Date9ja source DB connectivity (operator confirms the final-snapshot host/creds)
#     and R2 source bucket read access (for §0.B media copy).

# 2.5 Record CURRENT D8N production baseline (pre-migration)
bundle exec kamal app exec -d production 'bin/rails runner "
  %w[brands users profiles brand_memberships likes profile_passes matches conversations messages
     reports profile_blocks verification_assertions date9ja_history_records message_reactions
     profile_photos profile_videos active_storage_blobs legacy_references].each { |t|
    puts %(#{t} #{ActiveRecord::Base.connection.select_value(%(select count(*) from #{t}))})
  }
  puts %(date9ja profiles #{Profile.joins(:brand).where(brands:{slug:%q(date9ja)}).count})
"' | tee cutover-artifacts/d8n-baseline-$(date -u +%Y%m%dT%H%M%SZ).txt

# 2.6 Verify a restorable D8N backup exists + define the ROLLBACK POINT
D8N_BACKUP_DATABASE=d8n_production \
D8N_BACKUP_OUTPUT_DIR=/mnt/backups/cutover \
D8N_BACKUP_LABEL=d8n_production_precutover \
  script/operations/postgres_backup
#   -> records d8n_production_precutover-<ts>.dump + .sha256
#   Optional confidence: restore-drill it
D8N_RESTORE_BACKUP=/mnt/backups/cutover/d8n_production_precutover-<ts>.dump \
D8N_RESTORE_TARGET=d8n_restore_precutover_check \
D8N_RESTORE_KIND=primary \
D8N_RESTORE_CONFIRM=CREATE_DISPOSABLE_RESTORE_DATABASE \
  script/operations/postgres_restore_drill
```

**ROLLBACK POINT = the `d8n_production_precutover-<ts>.dump` above + the current
deployed image digest** (record `bundle exec kamal app details -d production`). Because
Date9ja has no mapped host until §6, rollback before §6 needs no data restore at
all — just do not map the host.

**STOP if:** the backup/checksum fails, storage/service checks fail, or the
Date9ja source is unreachable.

---

## 3. Freeze (legacy Date9ja — operator's infrastructure)

D8N needs no maintenance mode (no Date9ja traffic reaches it yet). The freeze is
entirely on the legacy Date9ja system.

1. Put legacy Date9ja into maintenance / read-only mode.
2. Stop Date9ja background/mutating jobs (the 30-day-grace `AccountHardDeleteJob`,
   any notification/trust/matching workers).
3. Block all member writes: registration, profile edits, likes/passes, messages,
   verification changes, reports, blocks, entitlement changes.
4. **Confirm writes are actually stopped:** watch the legacy DB for ~5 min —
   `MAX(updated_at)` / `MAX(id)` on `users`, `messages`, `likes`, `profile_passes`,
   `reports`, `verification_checks`, `matches` must stop advancing. Record the
   final `MAX(id)` per table and the wall-clock boundary.

**Do not proceed to §4 until write cessation is confirmed.**

---

## 4. Final source capture + migration

### 4.1 Final snapshot

```bash
# Operator takes the final Date9ja production DB backup (custom format).
# Preserve it read-only, checksummed, off-host. DO NOT mutate or drop the legacy DB.
sha256sum date9ja_final_<ts>.dump > date9ja_final_<ts>.dump.sha256

# Restore into a disposable, non-prod-named DB (assert_safe! forbids prod/production/live):
createdb date9ja_cutover_source
pg_restore --no-owner --no-privileges -d date9ja_cutover_source date9ja_final_<ts>.dump

# Schema signature + PII-free source census — record counts
psql -d date9ja_cutover_source -f scripts/date9ja/schema_signature.sql     # must print "schema signature OK (v3 …)"
psql -d date9ja_cutover_source -f scripts/date9ja/source_census.sql | tee cutover-artifacts/date9ja-source-census-<ts>.txt
```

**STOP if** the schema signature is not v3 `0b0e2e2b…` (the importers are pinned
to that contract).

### 4.2 Media bytes (path B1 — recommended)

```bash
# Bucket-to-bucket, keys preserved. Source creds from the operator; destination = r2_date9ja_production.
rclone sync date9ja-src-r2:<source-bucket> d8n-r2:<D8N_R2_DATE9JA_PRODUCTION_BUCKET> \
  --checksum --transfers 16 --stats 30s | tee cutover-artifacts/media-sync-<ts>.log
# Expect: photos + videos + message/selfie/verification evidence objects copied, 0 errors.
```

### 4.3 Run the proven importer sequence

**Path A2 (fence relaxed for the window):** `RAILS_ENV=test` is still required by
the fence check; point the primary at production and set the unlock token per the
reviewed 0.A change. **Path A1:** target the disposable rehearsal DB, then §4.4.

```bash
export RAILS_ENV=test
export DATABASE_URL="postgresql://d8n_app:***@172.18.0.1:5432/<d8n_production | d8n_date9ja_rehearsal_cutover>"
export DATE9JA_SNAPSHOT_DATABASE_URL="postgresql://localhost/date9ja_cutover_source"
# A1 only: bin/rails db:schema:load   (into d8n_date9ja_rehearsal_cutover, from a fresh d8n_production dump so sequences continue)
# A2 only: export DATE9JA_CUTOVER_UNLOCK=<one-time token from the reviewed 0.A change>

bin/rails brands:ensure_date9ja                                            # idempotent; no-op if pre-window deploy ran it

bin/rails date9ja:import_identity              | tee cutover-artifacts/01-identity.json
bin/rails date9ja:import_profile_preferences   | tee cutover-artifacts/02-preferences.json
bin/rails date9ja:import_sensitive_profile     | tee cutover-artifacts/03-sensitive.json
bin/rails date9ja:preflight_photos             | tee cutover-artifacts/04-preflight-photos.json
bin/rails date9ja:preflight_videos             | tee cutover-artifacts/05-preflight-videos.json
# Media bytes were copied in 4.2 (B1). If path B2 is chosen, run the R2 transfer tasks here instead.
DATE9JA_PUBLICATION_POLICY=publish_visible_onboarded \
  bin/rails date9ja:import_profile_readiness    | tee cutover-artifacts/06-readiness.json
bin/rails date9ja:import_historical_graph       | tee cutover-artifacts/07-graph.json
bin/rails date9ja:import_verification           | tee cutover-artifacts/08-verification.json
bin/rails date9ja:import_extended_history       | tee cutover-artifacts/09-extended-history.json
bin/rails date9ja:import_lifecycle              | tee cutover-artifacts/10-lifecycle.json

# Idempotency re-run of the graph + heaviest importers — expect 0 new rows
bin/rails date9ja:import_identity ; bin/rails date9ja:import_historical_graph ; bin/rails date9ja:import_extended_history
```

Expected shape (from the final rehearsal; exact numbers scale with the final
snapshot): identity `imported == eligible`, `failed == 0`, all `_absent`/`_raw_preserved`
notes only; `balanced: true` everywhere; `trust_xp_delta == 0`; readiness
`remediation_required == 0`, `failed == 0`; graph `reports.imported == reports.considered`,
`messages.imported == messages.considered − participant_not_migrated`.

**Do not introduce new importer behaviour, flags, or ad-hoc SQL fixes during the
window.**

### 4.4 (Path A1 only) Promote the migrated rows into `d8n_production`

Run the reviewed FK-ordered, sequence-safe load script prepared in §0.A. It must
load the migration-created rows across `users`, `identity_identifiers`,
`credentials`, `credential_password_hashes`, `brand_memberships`, `profiles`,
`profile_preferences`, `profile_option_selections`, `likes`, `profile_passes`,
`matches`, `conversations`, `messages`, `message_reactions`, `profile_blocks`,
`reports`, `verification_assertions`, `date9ja_history_records`, `profile_photos`,
`profile_videos`, `active_storage_blobs`, `active_storage_attachments`,
`legacy_references`, and the `users.metadata` / `profiles.metadata` updates — and
advance every touched sequence. No script → path A2.

---

## 5. Reconciliation gate

```bash
# 5.1 Source vs D8N destination, per domain (record every number)
bundle exec kamal app exec -d production 'bin/rails runner "
  b = Brand.find_by!(slug: %q(date9ja))
  pids = Profile.where(brand: b).select(:id)
  {
    users:            User.where(id: Profile.where(brand: b).select(:user_id)).distinct.count,
    memberships:      BrandMembership.where(brand: b).count,
    profiles:         Profile.where(brand: b).count,
    published:        Profile.where(brand: b, status: :active, visibility: :visible).count,
    preferences:      ProfilePreference.where(profile_id: pids).count,
    option_selections: ProfileOptionSelection.where(profile_id: pids).count,
    likes:            Like.where(brand: b).count,
    passes:           ProfilePass.where(brand: b).count,
    matches:          Match.where(brand: b).count,
    conversations:    Conversation.where(brand: b).count,
    messages:         Message.where(brand: b).count,
    media_messages:   Message.where(brand: b).where.not(source_media_reference: nil).count,
    reactions:        MessageReaction.where(brand: b).count,
    reports:          Report.where(brand: b).count,
    reports_open:     Report.where(brand: b, status: :open).count,
    blocks:           ProfileBlock.where(brand: b).count,
    verification:     VerificationAssertion.where(brand: b).count,
    history_ledger:   Date9jaHistoryRecord.where(brand: b).count,
    tombstones:       Date9jaHistoryRecord.where(brand: b, source_entity: %q(identity_tombstone)).count,
    photos_ready:     ProfilePhoto.where(brand: b).where(processing_state: :ready).count,
    videos:           ProfileVideo.where(brand: b).count,
    founding_members: User.where(%q(metadata #>> {date9ja,founding_member} = true)).count,
    cross_brand_leak: Profile.where(user_id: Profile.where(brand: b).select(:user_id)).where.not(brand_id: b.id).count,
    resurrected:      Date9jaHistoryRecord.where(brand: b, source_entity: %q(identity_tombstone)).where.not(user_id: nil).count,
    premium_grants:   User.where(%q(metadata #>> {date9ja,subscription_status} = premium)).count,
  }.each { |k,v| puts %(#{k}: #{v}) }
"' | tee cutover-artifacts/11-reconciliation.txt
```

Compare against the §4.1 source census and the importer JSONs. Confirm:
- users/identities, tombstones, profiles, preferences/options, photos/videos/media,
  likes/passes/matches, conversations/messages/reactions, reports/blocks/moderation,
  RealMe/verification, trust/history, publication/discovery readiness — each
  reconciles (destination = source − deliberately-excluded soft-deleted/banned/seed).
- **cross_brand_leak == 0**, **resurrected == 0**, **premium_grants == 0**.
- Media resolves: `ProfilePhoto` `display_image` + `ProfileVideo` `playback`/`poster`
  blob keys all resolve in `r2_date9ja_production` with matching checksum/size; `0`
  missing blobs.
- Discovery: a sample published viewer resolves a non-zero reciprocal candidate
  set through `Matching::EligibilityScope`.

**STOP THE CUTOVER immediately — do not proceed to §6 — if reconciliation shows:**
unexplained user/data loss, a resurrected deleted account, cross-brand leakage,
broken required media, referential-integrity failure, a security/privacy failure,
or a critical Date9ja runtime regression. Go to §9.

---

## 6. Production switch (only after §5 passes)

```bash
# 6.1 Map the Date9ja host. Two equivalent options:
#   (a) already in deploy.production.yml from §1 with DATE9JA_API_HOST set — then:
bundle exec kamal app exec -d production 'bin/rails brands:install_date9ja'
#   (b) or add DATE9JA_API_HOST + the proxy host now and redeploy:
bundle exec kamal deploy -d production          # boot runs brands:ensure_date9ja / install_date9ja

# 6.2 Verify the mapping and that NO other brand host resolves to Date9ja
bundle exec kamal app exec -d production 'bin/rails runner "
  BrandDomain.kept.active.joins(:brand).select(:host, %q(brands.slug)).each { |d| puts %(#{d.host} -> #{d.slug}) }
"'
#   -> date9ja-api.d8n.tech -> date9ja ; api.d8n.tech -> hookus ; dateza-api.d8n.tech -> dateza  (no overlap)

# 6.3 DNS: point date9ja-api.d8n.tech (and/or the legacy Date9ja API host via CNAME) at 164.68.106.97.
#     kamal-proxy provisions the TLS cert automatically once the host is in proxy.hosts.
curl -sS https://date9ja-api.d8n.tech/api/v1/health    # 200 ok
```

Keep the **legacy Date9ja database + backend intact and read-only** for the
agreed stability period.

---

## 7. Production smoke test (before reopening writes)

Run against `https://date9ja-api.d8n.tech`.

**Existing migrated member** (pick one with a photo + a match + a conversation +
a verified contact):
1. `POST` password login → session issued (bcrypt digest migrated verbatim).
2. `GET /api/v1/me` → correct identity, brand `date9ja`.
3. `GET /api/v1/profiles/:id` (self) → names, bio, city, option selections, photos.
4. Photo + video render (signed retrieval from `r2_date9ja_production`).
5. `GET /api/v1/discovery` → non-empty candidate list.
6. Like / pass a candidate → 200; a reciprocal like yields a match.
7. `GET /api/v1/conversations` → migrated history, correct order, senders, timestamps, read state.
8. `POST` a new message in an existing conversation → delivered; peer read.
9. RealMe / verification gate: an unverified member gets `403 identifier_verification_required` on a gated action; a verified member does not.
10. Block + report a profile → recorded; a previously-resolved migrated report is **not** in the open moderation queue.

**Also:**
- One **newly registered** Date9ja account through onboarding → discoverable per contract.
- Media rendering for a second migrated member.
- Mobile/API auth: token/session flow from the Date9ja client host.
- Notifications: trigger one immediately-testable path (e.g. new-match) → delivered via `D8N_DATE9JA_EMAIL_FROM` / `TWILIO_DATE9JA_MESSAGING_SERVICE_SID`.
- **Brand isolation:** a Date9ja session against `api.d8n.tech` / `dateza-api.d8n.tech` → `:wrong_brand`; HookUs + DateZA health still green; a Date9ja member is not discoverable from another brand.

**STOP and go to §9 if** login fails for migrated members, media 404s, brand
isolation leaks, or any retained journey is broken.

---

## 8. Reopen

Only after §7 passes:
1. Remove the legacy Date9ja maintenance / write freeze **only if** the legacy
   system is being kept as a passive read-only standby (it should be). Members
   now transact on D8N.
2. Announce Date9ja is live on the new platform.
3. Record: cutover completion timestamp, the D8N `D8N_GIT_SHA`, and the final
   §5 production counts → `cutover-artifacts/COMPLETION-<ts>.md`.
4. Watch `GET /api/v1/health`, error rates, and job queue depth for the agreed
   monitoring period.

---

## 9. Rollback

**Before §6 (no Date9ja host mapped):** nothing member-facing changed. Path A2:
`TRUNCATE` / delete the Date9ja-scoped rows written in §4 (or restore the §2.6
`d8n_production_precutover` dump), revert the 0.A fence commit. Path A1: discard
the rehearsal DB. Legacy Date9ja stays frozen or is reopened on its own infra.

**After §6 (host mapped, members may have transacted on D8N):**
1. Record the D8N boundary — `MAX(id)` / `MAX(created_at)` on `messages`, `likes`,
   `profile_passes`, `matches`, `reports`, sessions for `brand=date9ja`, and the
   wall-clock time.
2. Route Date9ja traffic back to the legacy backend: revert DNS for
   `date9ja-api.d8n.tech` / the legacy host, or unmap the D8N host —
   `bundle exec kamal app exec -d production 'bin/rails runner "BrandDomain.kept.joins(:brand).where(brands:{slug:%q(date9ja)}).update_all(deleted_at: Time.current)"'`
   then `bundle exec kamal proxy reboot -d production` if the proxy host must be dropped.
3. Re-enable legacy Date9ja writes **only after** the D8N boundary is recorded.
4. Verify legacy Date9ja health.
5. **Preserve** all D8N data, logs, the §2.6 backup, the §4 importer artifacts,
   the migration ledgers (`legacy_references`, `date9ja_history_records`), and the
   final Date9ja snapshot. Do not delete or overwrite any of them.
6. Reconcile any writes that landed on D8N during the mixed period before a second
   attempt.

**Rollback triggers:** material account lockout, cross-brand exposure, any
retained feature unavailable, broken conversation access, message/reaction/view
loss or order corruption, duplicate identity/relationship creation, inaccessible
media, security/authentication failure, unreconciled critical loss.

---

## Post-cutover retention (do NOT delete)

The legacy Date9ja database/backend, all backups, the final snapshot, the source
media buckets, the migration ledgers (`legacy_references`,
`date9ja_history_records`, `verification_assertions`), and the
`cutover-artifacts/` directory are retained intact and access-controlled through
the stability period. Legacy retirement is a separately approved phase, never
part of cutover.

## Immediately-post-cutover backlog (tracked, not blocking)

- Message-media / selfie / verification-evidence **byte** backfill (references +
  integrity metadata already migrated; 22 message rows carry
  `source_metadata.media_bytes_transferred = false`).
- Extended-history bulk-load performance (switch per-row savepoint to `insert_all`
  if the final-snapshot run is slow).
- Element-vocabulary review to reclassify the owner-only
  `profile.metadata["date9ja_<field>_raw"]` values into D8N codes.
