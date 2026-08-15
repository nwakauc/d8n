# Private Media Storage Operations

## Architecture: R2 is the private store, D8N is the control plane

- **R2 is D8N's private media store.** Buckets are private; public bucket access
  and public development URLs stay disabled.
- **Rails/D8N is the authorization and control plane.** It authenticates the
  caller, authorizes the profile, validates declared media, allocates the object
  identity (key), signs short-lived operations, and owns lifecycle/moderation
  state. Generic Active Storage routes stay disabled — object identity and
  delivery are mediated only by the D8N-controlled profile-photo API.
- **Clients transfer bytes directly to/from R2** using short-lived scoped
  authorization: a presigned `PUT` for upload and a presigned `GET` for
  retrieval. Media bytes never proxy through Puma.
- **R2 service credentials never reach frontend/mobile clients.**

## Current boundary

The owner-scoped profile-photo API is enabled exactly when private R2 storage is
selected (`config.x.profile_photos_enabled = r2_storage_enabled`). It supports
direct-to-R2 upload intent, verified attachment, short-lived signed retrieval,
and soft-delete/purge. Uploaded photos are **owner-only, `pending_review`, and
`hidden`**.

Still gated (see `docs/architecture/media-and-verification.md` and ADR 0011):
public/other-user delivery, safe decode/re-encode, EXIF/metadata removal, and
moderation approval. Because photos never appear in discovery, matches, or any
other user's view yet, enabling owner-only upload/retrieval does not expose
unprocessed media to third parties. Do not surface these photos publicly until
those gates pass. This advances ADR 0011's first slice; record an ADR amendment
noting the owner-scoped API is now live.

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

**Cloudflare R2 checksum compatibility (required).** `config/storage.yml` sets
`request_checksum_calculation: when_required` and
`response_checksum_validation: when_required` on the R2 service. Recent
`aws-sdk-s3` versions add an automatic CRC32 checksum in addition to the
Content-MD5 Active Storage already sends; R2 rejects requests carrying more than
one checksum with `InvalidRequest: You can only specify one non-default checksum
at a time`. Without these settings every upload fails at the network layer even
though the app boots cleanly. Do not remove them.

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

## Verification status — three distinct stages

Do not collapse these into one "media done" status.

1. **R2 infrastructure lifecycle — PROVEN (2026-08-15).** The genuine Active
   Storage A–F lifecycle (upload → object present → public access blocked →
   authorized read-back → purge → object gone) ran green against live
   `d8n-staging-media`. This surfaced and fixed the checksum incompatibility
   above: before the `config/storage.yml` fix, every upload failed with
   `InvalidRequest: You can only specify one non-default checksum at a time`.
   The fix is proven against the live bucket with the deployed SDK. It is
   permanent once `config/storage.yml` is committed and redeployed (the Kamal
   remote builder builds from committed git state).

2. **Profile-photo backend E2E — pending staging deploy.** The direct-upload API
   (intent → presigned PUT → verified attach → signed retrieval → delete/purge)
   is implemented and covered by request/unit/job tests, but the end-to-end
   staging proof through the deployed API must run after the deploy that carries
   both the checksum fix and this API.

3. **HookUs browser/product E2E — not started.** The frontend integration
   against staging has not been exercised.

## Still gated / not built

- Safe decode/re-encoding, EXIF/metadata removal, moderation approval, and
  public (other-user) signed delivery are not implemented. Photos remain
  owner-only, `pending_review`, and `hidden`.
- Hard server-side content-length re-verification uses an S3 `HEAD` in
  production; a declared-size bypass is bounded by the magic-byte check and the
  private owner-only scope until re-encode ships.
- No production R2 bucket, credential, or Kamal destination exists; this work
  deliberately does not create one.
