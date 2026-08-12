# ADR 0003: Separate User Identity From Brand Profiles

## Status

Accepted for initial build, subject to CTO review.

## Context

The same person may use multiple D8N-powered brands, but joining one dating brand must not automatically expose them on another. Identity may be portable, but dating activity must remain private and brand-scoped.

## Decision

`User` represents the platform identity.

`Profile` represents the brand-specific dating presence.

A user can have multiple brand profiles, but each profile and its dating activity remain scoped to one brand.

## Consequences

- Account recovery, security, verification, and device management can be platform-level.
- Brand-specific dating data remains isolated.
- Verification portability can be designed deliberately.
- Cross-brand visibility must be explicit, not accidental.

## Alternatives Considered

- One user equals one dating profile.
- Separate identity tables per brand.
- Automatically copying profiles across brands.
