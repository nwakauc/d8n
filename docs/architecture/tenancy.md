# D8N Tenancy Architecture

## Core Rule

Brand-owned data must be explicitly scoped by brand.

Do not rely on developer memory alone.

## Request Context

Every brand-scoped request should resolve:

- Current brand
- Current user
- Current permissions
- Locale/country where relevant
- Enabled features

Domain services should receive context explicitly.

Example:

```ruby
Profiles::VisibleForBrand.call(context: current_context)
```

Avoid:

```ruby
Profile.where(active: true)
```

## Admin And Network Access

Network/admin queries must use explicit named paths and authorization checks.

External operators must only access permitted brand data.

## Required Tests

Tenant isolation tests should prove:

- Users cannot view another brand's profile.
- Matches cannot cross brands accidentally.
- Conversations cannot cross brands accidentally.
- Reports are brand-scoped.
- Moderators cannot access brands outside their assignment.
- External operators cannot access D8N network data.

## Database Rules

Use database constraints where practical:

- One active membership per user per brand.
- One active profile per user per brand.
- Profile membership must match user and brand.
- Unique active brand slugs.
- Deterministic match participant ordering.
- No self-like.

Use partial unique indexes where soft deletion applies.

Current profile-domain enforcement also uses composite foreign keys:

- A profile's membership, user, and brand must identify the same membership row.
- A preference's profile, user, and brand must identify the same profile row.
- A photo's profile, user, and brand must identify the same profile row.

These constraints protect tenant ownership even when application validations are bypassed.
