# ADR 0006: Brand Resolution Strategy

## Status

Accepted for direction, implementation details pending.

## Context

D8N must resolve the current brand for API requests. Brand resolution affects tenant isolation, auth policy, feature flags, legal text, payments, notifications, moderation, and analytics.

Resolution must be safe for internal brands and future external operators.

## Decision

D8N will resolve brand context through trusted request properties.

Preferred sources:

- Domain
- Subdomain
- Registered API client identity

D8N must not trust a client-supplied arbitrary brand header as the primary source of tenancy.

A request header may be used only when it is tied to an authenticated/registered client and verified against allowed brands.

## Consequences

- Public web/mobile clients cannot impersonate another brand by changing a header.
- Tenant isolation starts at request context.
- Future external operator brands can use custom domains safely.
- Local development and tests need explicit helpers for brand context.

## Alternatives Considered

- Free-form `X-Brand` header.
- Brand slug in every route.
- Separate API deployment per brand.
