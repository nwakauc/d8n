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

- Email/password
- Email OTP
- Phone OTP
- OAuth
- WebAuthn
- Recovery code

All credential strategies produce the same D8N session result.

## Sessions

D8N sessions are currently brand-scoped.

A token issued after authenticating on HookUs is valid only for HookUs requests. The same underlying `User` may later authenticate into another brand, but that brand receives its own session token.

This is deliberately stricter than a platform-wide session. It keeps brand privacy and tenant isolation simple while D8N is proving the multi-brand model.

## Identity Identifiers

Identity identifiers normalize emails, phones, provider IDs, and other identity signals.

They help D8N detect duplicates, risk, and account recovery cases.

They must not cause automatic account merging.

## Account Linking And Merging

Credential linking is allowed.

Automatic account merging is not allowed.

If two accounts appear to belong to the same person:

- Require step-up verification where appropriate.
- Require support-assisted review for any merge.
- Preserve audit logs.
- Do not merge profiles, matches, messages, photos, or brand memberships automatically.

## Brand Privacy

A user joining one brand must not become visible in another brand.

Cross-brand profile visibility, profile import, photo reuse, recommendation, or membership disclosure must be explicit and opt-in.
