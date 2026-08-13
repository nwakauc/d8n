# D8N Identity Architecture

## Core Rule

`User` is the D8N platform identity.

`BrandMembership` is the user's membership in one dating brand.

`Profile` is the user's dating presence inside that brand.

Do not merge these concepts.

## Relationship Shape

```txt
User
  has many BrandMemberships
  has many Profiles
  has many Credentials
  has many IdentityIdentifiers

BrandMembership
  belongs to User
  belongs to Brand

Profile
  belongs to User
  belongs to Brand
  belongs to BrandMembership
```

## Credentials

D8N supports or plans these credential types:

- Password attached to an email or phone identifier
- OAuth
- WebAuthn
- Recovery code

Legacy phone-OTP credential values remain readable for migration compatibility,
but OTP is no longer a signup/login credential. Phone/email codes are
authenticated, post-signup identifier-verification challenges and never issue a
session.

ADR 0012 provides zero-friction phone/password and email/password as
brand-configurable choices, with Google deferred. New registration immediately
creates the current-brand membership and session, but leaves the supplied
identifier honestly unverified. Registration, login, joining another brand, and
linking a credential remain separate operations. Password or provider
authentication does not silently create membership in another dating brand.

Password knowledge and identifier control are separate facts. An unverified
phone/email may authenticate with its D8N password, but cannot support recovery,
verification badges, linking, or other control-dependent actions until a later
challenge proves access and sets `verified_at`.

## Sessions

D8N sessions are currently brand-scoped.

A token issued after authenticating on HookUs is valid only for HookUs requests. The same underlying `User` may later authenticate into another brand, but that brand receives its own session token.

This is deliberately stricter than a platform-wide session. It keeps brand privacy and tenant isolation simple while D8N is proving the multi-brand model.

Session authentication also requires the brand, user, and brand membership to remain active and not soft-deleted. Sessions issued through a credential retain that credential reference and stop authenticating if it is disabled, revoked, or soft-deleted.

Logout revokes only the current brand session and records a security event. Suspending a membership in one brand must not suspend the same identity's membership or sessions in another brand.

## Identifier Verification Lifecycle

- A valid brand-bound session is required to request or verify a code.
- Challenges target only an existing, kept identifier owned by the session user.
- Challenges are channel- and purpose-bound, single-use, expiring,
  attempt-limited, and resend/IP throttled.
- Verification changes only identifier `verified_at` and audit records. It never
  creates a user, credential, membership, profile, or session.
- Missing/already-verified identifiers receive the same generic request response.
- Concurrent requests for the same brand/channel/identifier or IP are serialized
  with HMAC-keyed PostgreSQL transaction advisory locks before throttle checks.

## Identity Identifiers

Identity identifiers normalize emails, phones, provider IDs, and other identity signals.

They help D8N detect duplicates, risk, and account recovery cases.

They must not cause automatic account merging.

## Account Linking And Merging

Credential linking is allowed.

Automatic account merging is not allowed.

Linking a durable credential requires recent reauthentication of the current
identity plus verification of the new identifier/provider. An identifier already
owned by another user cannot be moved through self-service linking.

If two accounts appear to belong to the same person:

- Require step-up verification where appropriate.
- Require support-assisted review for any merge.
- Preserve audit logs.
- Do not merge profiles, matches, messages, photos, or brand memberships automatically.

## Brand Privacy

A user joining one brand must not become visible in another brand.

Cross-brand profile visibility, profile import, photo reuse, recommendation, or membership disclosure must be explicit and opt-in.
