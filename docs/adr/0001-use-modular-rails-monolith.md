# ADR 0001: Use A Modular Rails Monolith

## Status

Accepted for initial build, subject to CTO review.

## Context

D8N needs to build multiple dating brands on one shared platform while preserving clear domain boundaries. The platform is pre-code and should prioritize speed, correctness, security, and maintainability.

## Decision

D8N will start as a modular Ruby on Rails monolith.

The platform will keep internal boundaries for Identity, Brands, Profiles, Matching, Messaging, Verification, Trust, Media, Billing, Notifications, Analytics, and Admin.

## Consequences

- Faster initial development.
- Simpler deployment and operations.
- Easier transactional consistency across domains.
- Service extraction remains possible later when scale or team ownership justifies it.
- Agents must not introduce microservices or heavy distributed infrastructure without a new ADR.

## Alternatives Considered

- Microservices from day one.
- Separate backend per brand.
- Serverless-first architecture.
