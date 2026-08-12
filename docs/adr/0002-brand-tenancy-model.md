# ADR 0002: Use Brand-Based Tenancy

## Status

Accepted for initial build, subject to CTO review.

## Context

D8N must power multiple internal brands and eventually external operator/franchise brands. Data must remain isolated by brand while shared platform capabilities serve all brands.

## Decision

D8N will model brands as first-class tenants.

Brand-owned records must include brand ownership and be accessed through tenant-aware request context, policies, and query patterns.

The initial schema should preserve future external ownership concepts instead of assuming all brands are D8N-owned forever.

## Consequences

- Internal and future external brands can share infrastructure safely.
- Cross-brand data leaks become a primary test and review concern.
- Network-level admin access must be explicit and audited.
- The system can later support franchise/white-label operators without rewriting the brand model.

## Alternatives Considered

- Separate database per brand from day one.
- Separate application per brand.
- Brand as a simple enum/config value only.
