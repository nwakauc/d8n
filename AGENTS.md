# D8N Agent Instructions

## Read This First

D8N is a multi-brand dating platform. It handles identity, private profiles, messages, media, verification, trust and safety, payments, moderation, analytics, and future external operator/franchise access.

Agents must treat this repository as security-sensitive.

## Required Context

Before making changes, read the relevant docs:

- `PLAN_OF_ACTION.md` for architecture and roadmap
- `AGENT_RULES.md` for full engineering rules
- `docs/adr/` for accepted architecture decisions
- `docs/architecture/` for deeper implementation constraints
- `docs/SCALING_GUIDE.md` for infrastructure and scaling constraints
- `docs/HUMAN_TODO.md` for founder/CTO decisions
- `docs/ARCHITECTURE_DIAGRAMS.md` for system shape

Use `README.md` for the company/product blueprint.

## Current Direction

- Rails API-only core
- Modular monolith first
- HookUs first product build target
- Date9ja as live migration and second-brand proof target
- PostgreSQL primary database
- Soft deletion by default for operational records
- Explicit tenant/brand isolation
- Identity and brand profiles are separate
- D8N marketing site belongs in a separate Next.js app/repo
- Rodauth/Rodauth-Rails is useful for mature auth/session/security primitives, while HookUs phone-first OTP remains a D8N auth strategy

## Core Invariants

Do not violate these:

1. `User` is platform identity.
2. `Profile` is brand-specific dating presence.
3. Joining one brand must not expose the user on another brand.
4. Brand-owned data must be scoped by brand.
5. Cross-brand visibility is denied by default.
6. Admin/operator access must be explicitly authorized and audited.
7. Soft deletion is the default operational behavior.
8. Legal erasure/anonymization is separate from soft deletion.
9. No backend fork per brand.
10. No secrets in code, prompts, logs, fixtures, or docs.

## Domain Pattern

Yes, follow the domain pattern.

Core domains:

- Brands
- Identity
- Profiles
- Matching
- Messaging
- Verification
- Trust
- Media
- Billing
- Notifications
- Analytics
- Admin

Use these domains to organize responsibility and reviews.

But do not over-abstract early.

Prefer:

- Idiomatic Rails
- Clear models
- Thin controllers
- Focused services for real workflows
- Explicit policies/authorization
- Tenant-safe query helpers
- Tests that prove behavior

Avoid:

- Large speculative frameworks
- Deep indirection for one use case
- Brand-name conditionals scattered through shared code
- Generic abstractions that are harder to understand than the Rails code they replace

Rule of thumb:

If one brand needs it, implement it clearly.

If two brands need it differently, introduce a small strategy/policy/configuration boundary.

If many domains need it, document the pattern before spreading it.

## High-Risk Areas

For changes touching any of these, propose a short plan before implementation:

- Authentication
- Authorization
- Tenant isolation
- Identity/profile modeling
- Messaging
- Payments
- Verification
- Trust and safety
- Media upload/deletion
- Admin access
- External operator access
- Database migrations
- Data deletion/recovery
- Data exports

## AI Agent Pitfalls To Avoid

- Do not copy Date9ja architecture blindly.
- Do not silently change existing test expectations to make tests pass.
- Do not expose Active Record models directly as public JSON for sensitive domains.
- Do not automatically merge accounts when identifiers overlap.
- Do not add dependencies casually.
- Do not hallucinate gem APIs; inspect installed versions and official docs.
- Do not expose Active Record models directly in public JSON when sensitive fields may exist.
- Do not log passwords, tokens, private messages, verification payloads, or unnecessary PII.
- Do not use frontend visibility as authorization.
- Do not run destructive commands without explicit approval.
- Do not deploy or access production credentials from an exploratory coding session.

Date9ja is a behavioral reference, not an architecture source of truth unless explicitly approved.

## Completion Gate

Before saying work is complete:

- Run relevant tests.
- Run linting.
- Run security checks when relevant.
- Report any command that could not be run.
- Summarize changed files and behavior.
- Call out unresolved risks.

Current basic checks:

```sh
bin/rails test
RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bin/rubocop --no-server
```

Use local PostgreSQL access when tests require it.

## API Contract

The canonical frontend/API contract is `docs/api/openapi.yaml`, with integration guidance in `docs/api/README.md`, runtime JSON at `GET /api/v1/openapi.json`, and interactive Swagger UI at `GET /api/docs`.

When adding, removing, or changing an `/api/v1` route, request field, response shape, authentication rule, status, or stable error code:

- Update the OpenAPI contract and integration guide in the same change.
- Add or update the endpoint request test.
- Run `bin/rails test test/contracts/openapi_contract_test.rb`.
- Do not document a planned endpoint as available before its production route exists.
