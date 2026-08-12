# ADR 0004: Keep D8N Core API-Only

## Status

Accepted for initial build, subject to CTO review.

## Context

D8N Core must power multiple consumer brands, mobile apps, admin tools, a marketing site, and future operator portals. The platform should not become coupled to one public website or frontend.

## Decision

D8N Core will be a Rails API-only platform.

The D8N marketing site should be a separate Next.js app/repository.

D8N Admin may use Rails/Hotwire inside the platform app if it provides the fastest secure operational path.

## Consequences

- The platform stays focused on core dating infrastructure.
- Marketing can optimize for SEO and content independently.
- Consumer brands can have distinct frontends.
- Admin remains free to use Rails-native tools if practical.

## Alternatives Considered

- Full-stack Rails for everything.
- Next.js for all surfaces including admin.
- Marketing site inside the API platform.
