# Private Media Storage Operations

## Current boundary

D8N has a guarded Cloudflare R2 configuration for Rails Active Storage, but the
production profile-photo API remains disabled. Generic Active Storage routes are
also disabled. This is intentional: selecting private object storage does not
make the current development upload flow safe for users.

Do not enable production photo uploads until the Media asset boundary, verified
image processing, moderation eligibility, authorized delivery, and durable purge
gates in `docs/architecture/media-and-verification.md` have passed.

## Provider configuration

Create separate private buckets for staging and production. Do not attach an R2
public development URL or public custom domain. Create a bucket-scoped token with
only Object Read & Write access for the relevant environment.

The application expects:

| Variable | Value |
| --- | --- |
| `D8N_R2_ENABLED` | Exactly `true` to select R2 |
| `D8N_R2_ACCESS_KEY_ID` | R2 S3 API access-key ID |
| `D8N_R2_SECRET_ACCESS_KEY` | R2 S3 API secret |
| `D8N_R2_BUCKET` | Environment-specific private bucket name |
| `D8N_R2_ENDPOINT` | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |

Keep all values in the deployment secret store. Never commit them, print them in
CI, or place them in an image build argument. The R2 service uses region `auto`,
path-style requests, and `public: false`.

After the bucket exists, add the variable names to the destination-specific Kamal
environment configuration and resolve their values from `.kamal/secrets.staging`
or `.kamal/secrets.production`. Those files must reference the operator's secret
environment/password manager; they must never contain literal credential values.

Production boot fails when `D8N_R2_ENABLED=true` and any required setting is
blank. When the flag is absent or false, production retains local storage only
as a harmless disabled fallback: both upload routes remain unavailable.

### Staging wiring (done)

The `staging` Kamal destination is wired end to end:

- `.kamal/secrets.staging` maps the bucket-scoped `d8n-staging-media` credential
  from the operator's local/CI environment (`STAGING_R2_ACCESS_KEY_ID`,
  `STAGING_R2_SECRET_ACCESS_KEY`, `STAGING_R2_BUCKET`, `STAGING_R2_ENDPOINT`) to
  the application-level `D8N_R2_*` names — never a literal value.
- `config/deploy.staging.yml` sets `D8N_R2_ENABLED: "true"` in `env.clear` and
  lists the four `D8N_R2_*` keys under `env.secret` so Kamal injects them into
  the staging container at deploy time.
- `test/config/kamal_staging_r2_configuration_test.rb` asserts this wiring
  structurally (correct key names, no literal values, consistent with
  `config/storage.yml`) without needing real credentials or a deploy.
- No `.kamal/secrets.production` or production destination exists yet, and none
  was created by this change — production remains on local disk with R2 disabled.

## Activation gate

Before setting `D8N_R2_ENABLED=true` in staging, prove all of the following:

1. The bucket has no anonymous/public access.
2. The credential is scoped to the single staging bucket.
3. A server-side upload, read, and delete smoke test succeeds without logging a
   credential, object key, or signed URL.
4. The media processing and purge jobs pass their retry/idempotency tests.
5. No unprocessed original is returned by the API.

Production activation additionally requires an approved retention/lifecycle
policy and a completed staging failure drill.

## Staging verification procedure

The production-style `ProfilePhoto` HTTP API is intentionally disabled in every
`RAILS_ENV=production` boot, including staging (`config.x.profile_photos_enabled
= false`), until the full media pipeline in
`docs/architecture/media-and-verification.md` ships. There is therefore no HTTP
endpoint to exercise yet — the "supported app flow" below is the configured
Active Storage service itself (the same code path any future feature will use),
driven directly through `bin/rails runner` against the deployed staging release.
Do not attempt to prove this by re-enabling `profile_photos_enabled` in staging.

Run each step as a distinct, observable command. Do not chain them into one
script — the point is to see each one succeed independently.

**A. Upload one harmless image through the supported app flow**

```
kamal app exec -d staging \
  "bin/rails runner 'blob = ActiveStorage::Blob.create_and_upload!(
     io: StringIO.new(SecureRandom.bytes(32)),
     filename: \"r2-smoke-test.bin\",
     content_type: \"application/octet-stream\"
   ); puts blob.key'"
```

Record the printed blob `key` — every later step refers to it.

**B. Confirm the object appears in `d8n-staging-media`**

Check via the Cloudflare dashboard or `rclone`/`aws s3 --endpoint-url` configured
with the same bucket-scoped credential (not from application code) that an
object with that key exists in `d8n-staging-media`.

**C. Confirm direct public R2 access is unavailable**

Attempt an unauthenticated HTTPS GET against the R2 endpoint/bucket/key
directly (no signed params). It must fail — R2 public access is disabled and
`config/storage.yml` sets `public: false`.

**D. Confirm the app can retrieve it through the intended authorized path**

```
kamal app exec -d staging \
  "bin/rails runner 'blob = ActiveStorage::Blob.find_by!(key: \"<KEY_FROM_A>\");
   puts blob.download.bytesize'"
```

This proves the app can read the object back through its own service
credentials, independent of any public URL.

**E. Delete/purge the record**

```
kamal app exec -d staging \
  "bin/rails runner 'ActiveStorage::Blob.find_by!(key: \"<KEY_FROM_A>\").purge'"
```

**F. Confirm the object disappears from R2**

Re-check the bucket by the same means as step B; the object must be gone.
`purge` is synchronous here (no async purge job exists yet), so this should be
immediate — record if it is not.

Record the dated output of each step (blob key, byte count, and pass/fail) as
the evidence artifact for this drill. None of these steps touch product data or
any HTTP-facing route.

## Failure and rollback boundary

Before real media exists, unset `D8N_R2_ENABLED` to roll back this configuration
without affecting product data. After real media exists, never silently fall
back to app-local disk: keep the API unavailable, restore R2 access, and reconcile
failed media jobs. Switching storage services does not migrate existing blobs.

Deleting a Rails record is not proof that its R2 objects were purged. The future
purge workflow must remain observable and idempotent, with database state as the
authorization source of truth.

## What is not yet proven

- The `d8n-staging-media` bucket and its bucket-scoped credential exist and are
  wired through Kamal, and a staging deploy has now run with
  `D8N_R2_ENABLED=true` and is healthy (the app boots with R2 selected). However,
  no network operation against R2 has been executed yet: nothing has been
  uploaded to, retrieved from, or purged from the bucket through the application
  service. The staging A-F verification procedure above is written but not yet
  performed.
- Safe decode/re-encoding, EXIF removal, moderation, signed delivery, and purge
  retries are not implemented yet.
- The production photo HTTP API remains disabled in every environment,
  including staging — this change only proves the storage backend, not an
  end-user upload path.
- No production R2 bucket, credential, or Kamal destination exists; this change
  deliberately does not create one.
