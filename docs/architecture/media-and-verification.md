# D8N Media And Verification Architecture

## Current Safety Boundary

`ProfilePhoto` and its multipart endpoints are a local-development foundation,
not a production media pipeline. Production use remains disabled until private
object storage, verified processing, moderation, delivery authorization, and
purge behavior exist.

Authentication by phone OTP proves credential control only. No selfie, liveness,
age, or identity-document verification API currently exists.

## Domain Ownership

| Concern | Owner | Boundary |
| --- | --- | --- |
| Stored upload, variants, inspection, purge | Media | Private storage object and processing lifecycle |
| Photo order and brand-profile visibility | Profiles | `ProfilePhoto` placement scoped to one profile |
| Moderation policy and decisions | Trust | Authorized state transitions and appeal/evidence policy |
| Identity assertions and provider attempts | Verification | Platform-user assertion with explicit brand policy |
| Public discovery projection | Profiles/Matching | Approved variants only; no storage/provider internals |

Media and Verification remain modules inside the Rails monolith. Object storage,
CDN delivery, processing workers, and external providers are integrations, not
sources of authorization truth.

## Implementation Sequence

### Slice 1: Private Media Asset Boundary

- Add a Media-owned asset record with opaque public ID, brand/user/profile
  ownership, storage state, processing state, byte and dimension limits, detected
  content type, checksum, and soft-deletion/purge state.
- Enforce tenant ownership with database constraints where practical.
- Keep storage keys and provider metadata internal.
- Configure production for private S3-compatible object storage only after R2
  credentials, bucket lifecycle, region, and access policy are approved.
- Preserve local disk for development and isolated test storage.

Gate: no raw storage key or generic blob route is returned by an API; cross-brand
asset attachment is rejected by both service queries and database constraints;
production refuses to boot into an upload-enabled state with local app-disk.

### Slice 2: Verified Image Processing

- Accept a bounded upload into quarantine.
- Decode with a maintained image library and verify the actual format.
- Reject malformed, oversized, extreme-dimension, and resource-exhaustion inputs.
- strip metadata and re-encode only required display variants;
- process asynchronously with idempotent jobs and bounded retries;
- record operational failure codes without copying sensitive payloads to logs.

Gate: fixtures with spoofed MIME types, corrupt bytes, EXIF location, oversized
dimensions, and duplicate jobs are covered by tests. No unprocessed original can
be serialized publicly.

### Slice 3: Moderation And Profile Publication

- Define an explicit state machine for pending, approved, rejected, and deleted
  media uses.
- Integrate the selected moderation provider behind a small Media/Trust boundary.
- Record audited automated and human decisions with bounded reason codes.
- Count only safe, policy-eligible photos toward publication completion. A
  moderate-first brand may count a processed pending photo for onboarding while
  withholding it from public delivery; this prevents review latency from
  deadlocking onboarding without treating an unusable upload as public media.
- Automatically unpublish an active profile when it loses its required eligible
  photo set.

Gate: founder/Trust approval exists for categories, reviewer permissions, appeal,
and retention. Rejected photos cannot satisfy publication or enter public
serializers. Pending photos enter public serializers only for an explicit
immediate-visibility brand policy; moderate-first pending photos remain hidden.

### Slice 4: Authorized Delivery And Purge

- Issue owner previews only after current-brand owner authorization.
- Project approved public variants through the profile serializer.
- Use short-lived signed or controlled CDN URLs with cache behavior that supports
  revocation.
- Revoke API visibility synchronously on deletion and enqueue idempotent origin,
  variant, and CDN purge.
- Reconcile failed purge jobs without restoring visibility.

Gate: copied owner URLs do not grant durable access; deleted/rejected media stops
receiving new delivery authorization; purge and retry behavior is observable and
tested without logging signed URLs.

### Slice 5: Verification Assertions

- Add server-created verification attempts and bounded user assertions.
- Keep provider payloads and raw evidence outside consumer serializers.
- Verify webhook signatures and replay/idempotency keys before transitions.
- Evaluate brand requirements through an explicit policy; do not add brand-name
  conditionals to shared verification code.
- Expose only intentionally public derived badge/capability state.

Gate: HookUs policy, provider, consent copy, retention, erasure, portability,
manual review, appeal, and support access are approved. Tests prove that the same
user's verification does not expose membership or profiles across brands.

## Upload And Delivery State

```txt
client upload
    |
    v
quarantined asset -> verified decode -> safe variants -> moderation
    |                    |                    |              |
    +---- reject/purge <-+--------------------+--------------+
                                                  |
                                                  v
                                      approved profile use
                                           /          \
                                  owner preview    public variant
```

Storage completion alone never means public approval.

## API Rules

- Consumers address dating profiles and media with public UUIDs, never internal
  IDs or storage keys.
- Owner and public media serializers are separate.
- Upload responses expose processing state, not a public original URL.
- Public profile responses include only approved, visible, processed variants.
- Stable errors must not reveal cross-brand asset existence.
- Any future direct-upload credential is short-lived, content-length bounded,
  constrained to one server-created asset, and incapable of selecting brand/user
  ownership.

Any route or response change must update `docs/api/openapi.yaml`,
`docs/api/README.md`, endpoint tests, and the OpenAPI contract test in the same
slice.

## Logging And Observability

Permitted operational fields include brand ID, opaque media/attempt ID, state,
bounded error code, job/provider name, duration, and timestamp.

Do not log:

- upload bytes or extracted metadata;
- signed URLs, storage keys, or webhook secrets;
- face embeddings, liveness frames, or identity documents;
- provider payloads, private review notes, or unbounded failure text;
- public profile details unrelated to the operation.

## Deletion And Retention

Soft deletion revokes product visibility and supports an approved recovery window.
Permanent object purge, provider-side deletion, anonymized audit retention, and
legal erasure are separate workflows. Their timing cannot be inferred from a
`deleted_at` column and must be approved before production.

Verification evidence must be minimized independently from the derived assertion.
An assertion may remain valid after provider evidence is deleted only if the
approved policy and legal basis explicitly permit it.

## Deferred

- Video and audio media.
- Cross-brand media reuse.
- Message attachments.
- Face search or biometric matching.
- Network-wide moderator access.
- Client-side public uploads.
- Provider-specific schemas in shared domain models.
