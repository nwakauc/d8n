# D8N Agent Engineering Rules

## Purpose

This document defines mandatory rules for Codex, Claude, and any future AI or human agent working in this repository.

D8N is a dating platform handling identity, private profiles, messages, media, payments, verification, moderation, and trust data. Engineering standards must be strict from the beginning.

These rules apply to planning, architecture, code, tests, documentation, reviews, and implementation.

## Prime Directive

Do not optimize for speed at the cost of platform safety.

Every change must preserve:

- Security
- Privacy
- Tenant isolation
- Data integrity
- Auditability
- Rails best practices
- Maintainability
- Clear domain boundaries

If a request conflicts with these principles, the agent must flag the conflict before implementing.

## Required Before Making Changes

Before changing files, an agent must:

1. Read the relevant documentation.
2. Inspect the existing code or repo structure.
3. Understand the domain being changed.
4. Identify tenant, privacy, security, and audit implications.
5. Keep the change scoped to the requested work.

Relevant starting documents:

- `README.md`
- `PLAN_OF_ACTION.md`
- `AGENT_RULES.md`
- `docs/HUMAN_TODO.md`
- `docs/ARCHITECTURE_DIAGRAMS.md`
- `docs/SCALING_GUIDE.md`
- `docs/architecture/`
- Future ADRs in `docs/adr/`

## Architecture Rules

### Modular Monolith First

D8N begins as a modular Rails monolith.

Agents must not introduce microservices, event streaming, Kubernetes, distributed workflows, or separate infrastructure unless explicitly approved by the founder and CTO through an Architecture Decision Record.

### API Core

D8N Core is a Rails API-only platform.

Agents must not turn the core platform into a marketing website, consumer frontend, or generic full-stack app.

Allowed exceptions:

- Internal admin may use Rails/Hotwire if approved.
- Temporary tactical pages may exist only with explicit approval.

### Domain Boundaries

Agents must preserve domain boundaries.

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

Do not place complex cross-domain business logic randomly in models, controllers, jobs, or helpers.

Use clear service objects, policies, commands, or domain modules where the codebase establishes that pattern.

### No Backend Forking Per Brand

Agents must not duplicate the backend for Date9ja, HookUs, DateSA, DateAussie, or future brands.

Brand differences should be handled through:

- Configuration
- Feature flags
- Brand policies
- Strategy objects
- Limited brand-specific modules

Backend forking is a failure mode and requires CTO approval.

## Rails Best Practices

### Prefer Rails Generators

Agents should prefer Rails commands and generators for Rails application structure whenever practical.

Recommended practices:

- Use `rails new` to create the Rails application skeleton.
- Use Rails generators for models, migrations, controllers, jobs, mailers, channels, tests, and other framework-owned structure.
- Use generator output as the baseline, then edit deliberately.
- Avoid manually creating Rails framework files when a standard generator is a clean fit.
- Avoid bypassing Rails conventions just to move faster.

Manual creation is acceptable for:

- Documentation files
- ADRs
- Non-Rails support files
- Small manual edits after generator output exists
- Files where Rails has no appropriate generator
- Cases where the generator would create noisy or unsuitable output

The goal is to keep D8N idiomatic, maintainable, and aligned with Rails defaults unless there is an approved reason to diverge.

### Models

Models should own persistence rules, associations, validations, and small domain behavior.

Models must not become dumping grounds for large workflows, provider integrations, controller concerns, or unrelated cross-domain logic.

Required model practices:

- Use clear associations.
- Use database-backed invariants where practical.
- Use enums carefully and explicitly.
- Validate data at both application and database layers when important.
- Avoid callbacks for complex business workflows.
- Avoid relying only on default scopes for tenant isolation unless explicitly approved.

### Controllers

Controllers should be thin.

Controllers should:

- Authenticate
- Authorize
- Resolve request context
- Validate request shape
- Call domain/application services
- Render responses

Controllers should not contain matching algorithms, payment workflows, verification workflows, moderation workflows, or complex branching business logic.

### Services And Domain Objects

Use services/domain objects for workflows that cross models or external systems.

Examples:

- Creating a match
- Starting a conversation
- Processing a payment webhook
- Running verification checks
- Applying enforcement actions
- Sending notifications
- Uploading media

Services should have clear inputs, outputs, and failure behavior.

### Jobs

Use background jobs for slow, external, retryable, or asynchronous work.

Examples:

- Email
- SMS
- Push notifications
- Media processing
- Payment webhooks
- Verification provider calls
- Moderation provider calls
- Analytics fanout

Jobs must be idempotent where retries can happen.

### Migrations

Migrations must be safe and deliberate.

Required practices:

- Add foreign keys for important relationships.
- Add indexes for lookup paths and uniqueness.
- Use null constraints where data is required.
- Use check constraints where appropriate.
- Avoid destructive migrations without explicit approval.
- Avoid long-locking migrations on production-scale tables.
- Do not remove columns until code no longer depends on them.

### Database Integrity

The database must enforce important invariants.

Do not rely only on application code for:

- Tenant ownership
- Critical uniqueness
- Required relationships
- Payment identifiers
- Provider event idempotency
- Admin permissions

## Tenant And Brand Isolation

Tenant isolation is mandatory.

Every brand-owned object must be scoped to a brand.

Agents must not add queries that can leak records across brands.

Any query touching brand-owned data must answer:

- Which brand is active?
- How is the brand resolved?
- Is the current user allowed to access this brand?
- Can this accidentally return records from another brand?

Tenant isolation must be enforced through explicit request context and approved query patterns.

Agents must not rely on developer memory or casual `where(brand_id: ...)` usage alone.

Recommended rule:

- Brand-owned data access must go through tenant-aware services, scopes, repositories, or query helpers.
- Network/admin access must use explicit named paths and authorization checks.
- Unscoped brand-owned queries should be treated as suspicious in review.

Required tests:

- Users cannot see profiles from another brand unless explicitly allowed.
- Matches cannot cross brands accidentally.
- Conversations cannot cross brands accidentally.
- Moderators cannot access brands outside their permission scope.
- External operators cannot access D8N network data.

## Identity And Profile Rules

`User` is the platform identity.

`Profile` is the brand-specific dating presence.

Agents must not merge these concepts.

Rules:

- A user can have multiple brand profiles.
- Joining one brand must not make a user visible on another brand.
- Dating activity is brand-scoped.
- Verification may be platform-scoped only when explicitly designed and communicated.
- Account deletion and brand profile deletion must remain separate concepts.

## Soft Deletion And Audit Rules

Soft deletion is the default for operational records.

Important records should use fields such as:

```txt
deleted_at
deleted_by_id
deletion_reason
restored_at
restored_by_id
```

Agents must not hard-delete operational records unless:

- The user explicitly requests legal erasure behavior.
- The CTO-approved data retention policy allows it.
- The deletion path preserves required audit, billing, fraud, and moderation obligations.

Restores must be explicit and audited.

Soft deletion does not replace legal erasure, anonymization, provider-side deletion, or media purge requirements.

## Security Rules

Agents must treat security as a core requirement.

Required rules:

- Never commit secrets.
- Never log passwords, tokens, private keys, full payment data, sensitive verification data, or private message contents unnecessarily.
- Verify webhook signatures.
- Make webhook handlers idempotent.
- Rate-limit authentication-sensitive and messaging-sensitive endpoints.
- Require stronger protections for admin access than consumer access.
- Use least privilege for admin and operator permissions.
- Audit sensitive admin reads and writes.
- Keep external operator access restricted to permitted brands only.

If an implementation touches authentication, authorization, payments, verification, media upload, messaging, reports, moderation, or admin access, the agent must explicitly consider security impact.

## Privacy Rules

Agents must preserve user privacy.

Required rules:

- No implicit cross-brand visibility.
- No automatic profile copying across brands.
- No exposure of private dating activity across brands.
- No unrestricted external operator access.
- Verification portability must be explicit.
- Data export and deletion behavior must be considered when adding new sensitive data.
- Analytics should avoid unnecessary personally identifiable data.

## Payments Rules

Payment code must be conservative.

Required rules:

- Webhooks must verify provider signatures.
- Webhooks must be idempotent.
- Store provider event IDs.
- Never trust client-side payment status.
- Keep end-user billing separate from future operator/platform billing.
- Entitlements must be brand-scoped.
- Payment provider-specific details should not leak throughout the core domain.

## Trust And Safety Rules

Trust and safety workflows must be auditable.

Required rules:

- Reports must be brand-scoped.
- Moderation actions must be audited.
- Network-level enforcement must be explicit.
- Minor brand-level rule violations must not automatically become network-level bans.
- Serious fraud/safety signals may be platform-level only through approved policy.
- External operators must not see unrestricted network trust intelligence.

## External Operator Rules

D8N may eventually power external dating businesses.

Agents must preserve this future option.

Rules:

- Do not assume every brand is D8N-owned forever.
- Do not assume every admin is a D8N employee.
- Do not expose network-level data to brand operators.
- Keep operator billing separate from end-user billing.
- Keep brand ownership, brand operation, and platform administration distinct.
- Avoid hard-coded assumptions that prevent future white-label or franchise support.

## Testing Rules

Tests are required for important behavior.

Mandatory test areas:

- Authentication
- Authorization
- Tenant isolation
- Identity/profile separation
- Soft deletion and recovery
- Matching
- Messaging permissions
- Blocking and reporting
- Admin permissions
- Payment webhooks
- Verification workflows
- Media access
- Privacy boundaries

Agents must not claim a change is complete if relevant tests were not run or could not be run.

If tests cannot be run, the agent must state why.

## Documentation Rules

Agents must update documentation when a change affects:

- Architecture
- Data model
- Security
- Privacy
- Tenant behavior
- API behavior
- Admin behavior
- External operator readiness
- Payment or verification flows

Major architecture changes require an ADR.

## Test Integrity Rules

Agents must not modify existing test expectations merely to make tests pass.

If a test appears wrong, outdated, or incompatible with the requested behavior:

- Stop and explain why.
- Identify the product or architecture decision involved.
- Change the test only when the intended behavior has explicitly changed.

Never weaken security, authorization, tenant isolation, deletion, payment, or moderation tests to get a green suite.

## API Serialization Rules

Agents must not expose Active Record models directly in public JSON responses for sensitive domains.

Use explicit response objects, serializers, presenters, or carefully controlled JSON hashes.

This is especially important for:

- Users
- Profiles
- Messages
- Reports
- Trust signals
- Verification records
- Payment records
- Admin users

Do not accidentally expose internal fields such as risk scores, provider IDs, moderation notes, private identifiers, tokens, or verification metadata.

## Legacy Reference Rules

Date9ja may be used as a behavioral reference.

Date9ja must not be treated as an architecture template unless explicitly approved.

When inspecting legacy Date9ja behavior:

- Identify the user-facing behavior.
- Identify the data that must be preserved.
- Reimplement according to D8N architecture.
- Do not copy legacy schemas, constants, auth assumptions, or brand-specific conditionals blindly.

## Review Rules

Before implementation, major decisions require review.

Major decisions include:

- Changing the modular monolith strategy
- Changing API-only core strategy
- Changing tenant model
- Changing identity/profile separation
- Adding cross-brand visibility
- Changing admin permission model
- Adding payment architecture
- Adding verification architecture
- Adding external operator access
- Extracting a service
- Adding major infrastructure

Agents must not silently make these decisions in code.

## Prohibited Actions

Agents must not:

- Commit secrets.
- Hard-code production credentials.
- Bypass authorization checks.
- Add unscoped brand queries.
- Merge `User` and `Profile`.
- Add implicit cross-brand profile sharing.
- Hard-delete important operational records casually.
- Build brand-specific backend forks.
- Introduce microservices without approval.
- Add heavy infrastructure without approval.
- Treat external operators as trusted platform admins.
- Store sensitive provider data unnecessarily.
- Ignore failed tests.
- Present untested security-sensitive work as complete.

## Completion Standard

A task is complete only when:

- The implementation matches the approved architecture.
- Tenant isolation is preserved.
- Security and privacy implications were considered.
- Relevant tests were added or updated.
- Relevant tests were run where possible.
- Documentation was updated where needed.
- Any unresolved risks are clearly stated.

If these conditions are not met, the agent must say what remains.
