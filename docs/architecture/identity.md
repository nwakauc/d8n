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

D8N should support multiple credential types:

- Password attached to a verified email or phone identifier
- Email OTP
- Phone OTP
- OAuth
- WebAuthn
- Recovery code

All credential strategies produce the same D8N session result.

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

## Authentication Lifecycle

Phone OTP authentication uses deny-by-default lifecycle rules:

- Inactive or deleted brands cannot request or verify OTP challenges.
- Suspended, closed, or deleted users cannot receive a new session.
- Disabled, revoked, or deleted credentials cannot receive a new session.
- Suspended, left, or deleted memberships are not silently reactivated.
- Public authentication failures remain generic while internal security events retain the denial reason.
- Concurrent OTP requests for the same brand and phone or IP are serialized with PostgreSQL transaction advisory locks before throttle checks.

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
