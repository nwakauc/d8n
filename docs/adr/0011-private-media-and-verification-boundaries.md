# ADR 0011: Separate Private Media From Verification Assertions

## Status

Proposed for Phase 6 review on 2026-08-13. No production media or verification
provider is approved by this ADR.

Reconciliation note (2026-08-17): the **media-storage half** of this ADR has been
implemented and staging-proven ahead of formal acceptance — private R2, direct
client uploads with server-allocated PII-free keys, verified decode + safe
re-encode, EXIF/GPS stripping, stranger-safe signed display derivatives, and
durable raw purge (A-F lifecycle proven on staging 2026-08-15). Still Proposed /
not built: **moderation enforcement** on the media states and the **verification
assertion** boundary. The per-brand photo-visibility policy (HookUs visible-on-
attach vs default hidden, `Media::PhotoPolicy`) is a durable decision made under
this ADR. Founder/CTO to confirm whether to promote the media half to Accepted.

## Context

D8N handles dating-profile photos, future private verification evidence, and
provider results across multiple brands. These records differ in ownership,
audience, retention, and legal sensitivity even when they are all backed by
object storage.

The current profile-photo implementation is a Phase 3 development foundation. It
attaches an upload directly to `ProfilePhoto`, accepts multipart uploads through
Rails, records a moderation state, and uses local disk in production
configuration. It does not yet verify decoded image content, strip metadata,
create safe variants, integrate moderation, provide revocable delivery, or use
production object storage. Generic Active Storage blob paths are returned to the
owner. These limitations make the endpoint unsuitable for production media.

Phone OTP proves control of a phone credential at authentication time. It is not
identity, selfie, age, or government-ID verification.

## Decision

### Media Storage And Product Use Are Separate Records

A storage object and its product use have different lifecycles. Phase 6 should
introduce a Media-owned asset record for storage, processing, inspection, purge,
and provider metadata. `ProfilePhoto` remains the brand-profile-owned placement
that controls order, moderation state, and visibility.

A media asset must have an opaque public identifier. Internal database IDs,
storage keys, provider IDs, and raw Active Storage blob routes must not become the
stable public contract.

The initial asset belongs to one brand, user, and profile-photo use. Cross-brand
photo reuse is not implied by common platform identity. Reuse or copying requires
a future explicit opt-in workflow and a new privacy review.

### Uploads Enter Quarantine

An accepted upload is not a publishable image. New assets begin quarantined and
must pass all required processing before public use:

- bounded byte size and decoded dimensions;
- file-signature and decoder verification rather than trusting the supplied MIME
  type or filename;
- rejection of malformed images and decompression/resource-exhaustion hazards;
- metadata removal, including EXIF location and device data;
- re-encoding into D8N-owned safe variants;
- malware/content-safety integration point;
- brand moderation policy.

Only processed, approved, visible variants may appear in public profiles,
discovery, matches, or conversations. Originals remain private and are never
served to other consumers.

### Delivery Is Authorized And Revocable

Owner previews and public profile variants have distinct authorization paths.

- Owner access rechecks the current brand, user, membership, profile lifecycle,
  and undeleted photo.
- Public access is issued only for an approved, visible variant attached to an
  otherwise authorized public profile surface.
- URLs are short-lived signed capabilities or controlled CDN URLs whose access
  can be revoked. They must not reveal bucket keys or provider identifiers.
- Soft deletion immediately removes the photo from API surfaces and invalidates
  new delivery authorization. Storage and CDN purge then run asynchronously and
  idempotently according to retention policy.

The application database remains the source of truth for authorization and
state. R2, a CDN, background jobs, or a moderation provider must not decide
tenant access independently.

### Verification Stores Assertions, Not Public Evidence

Verification is a separate domain from media and authentication. A verification
record describes a bounded assertion about a platform `User`, such as phone
control, selfie/liveness, age, or identity-document outcome. Brand policy decides
whether that assertion satisfies a product requirement.

Raw evidence, derived assertions, and public badges are separate concepts:

- raw evidence is private, highly sensitive, and retained only when an approved
  policy requires it;
- provider references and decision metadata are internal and never serialized to
  consumers;
- public profile payloads may expose only an approved derived capability or badge,
  not raw evidence, scores, failure reasons, or provider data;
- a verification completed for one brand does not silently disclose brand
  membership or make a profile visible on another brand;
- portability across brands requires explicit policy, consent, purpose
  compatibility, and expiry rules.

Provider webhooks must be signature-verified, replay-safe, idempotent, and mapped
to an existing attempt without trusting client-supplied user, profile, or brand
ownership.

### Moderation And Verification Decisions Are Audited

State transitions must record the actor type, bounded reason code, timestamp, and
affected opaque record identifier. Logs and generic audit metadata must not
contain media bytes, signed delivery URLs, face data, identity-document data,
provider payloads, private notes, or unnecessary PII.

Automated provider outcomes do not grant moderators network-wide access. Brand
moderation, platform safety review, support access, and provider processing require
separate authorization policies.

## Initial Slice Boundaries

Implementation must follow the bounded sequence in
`docs/architecture/media-and-verification.md`.

The first implementable slice is the private media asset and processing boundary.
It must not add a production provider, verification flow, cross-brand reuse, or
admin evidence access.

## Human And Provider Gates

Before production media delivery:

- select and configure private object storage and CDN behavior;
- approve photo moderation rules, appeal behavior, and moderator permissions;
- define original and variant retention, recovery, and permanent purge timing;
- approve informed disclosure for image processing and moderation providers.

Before selfie, age, or identity-document verification:

- define HookUs verification requirements and user-facing claims;
- select a provider and approve data-processing terms and regions;
- define evidence minimization, retention, export, deletion, and legal-erasure
  behavior;
- decide whether any assertion is portable across brands;
- define manual review, appeal, support, and network-enforcement permissions.

## Consequences

- Existing profile-photo APIs remain development-only until the Phase 6 media
  gates are implemented.
- Media processing can evolve independently of profile placement without a
  service split.
- Public photo delivery becomes intentionally narrower than storage possession.
- Verification can be platform-owned without creating implicit cross-brand
  disclosure.
- More migrations and background work are required before production uploads.

## Alternatives Considered

- Treat Active Storage blobs as the public media contract.
- Store verification evidence directly on profiles.
- Treat phone OTP as identity verification.
- Reuse photos and verification outcomes across all brands automatically.
- Allow a provider webhook to identify users or brands from untrusted payload
  fields without an existing server-created attempt.
- Make uploaded originals public after checking only the declared content type.
