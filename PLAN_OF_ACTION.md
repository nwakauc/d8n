# D8N Platform Plan of Action

## Purpose

This document defines the initial technical plan for building D8N from scratch as a multi-brand dating platform.

D8N should not be built as one dating app with many skins. It should be built as a shared platform that can power multiple dating brands, each with its own market, identity, rules, matching philosophy, monetization, and user experience.

The first goal is to build a solid, reviewable foundation that can support Date9ja, HookUs, DateSA, DateAussie, and future brands without duplicating core dating infrastructure.

This document is intended for review by:

- Founder / product owner
- Claude / AI architecture reviewer
- CTO / technical reviewer
- Future engineering team

All agents working in this repository must also follow `AGENT_RULES.md`.

Supporting documents:

- `docs/HUMAN_TODO.md`
- `docs/ARCHITECTURE_DIAGRAMS.md`
- `docs/SCALING_GUIDE.md`

## Core Architecture Decision

D8N will begin as a modular monolith, not as microservices.

That means:

- One primary Rails application at the beginning
- One primary PostgreSQL database at the beginning
- Clear internal domain boundaries
- Strong tenant / brand ownership on data
- Shared platform services for identity, profiles, matching, chat, trust, media, payments, notifications, and admin
- Physical service extraction only when scale, operational pressure, or team ownership justifies it

This gives D8N the right balance:

- Fast enough to build
- Simple enough to operate
- Structured enough to scale
- Clean enough to extract later

## Product Model

D8N is the platform.

Brands are products that run on the platform.

Brands may be owned by D8N or operated by external partners in the future.

Initial brands:

- HookUs
- Date9ja
- DateSA
- DateAussie

Future brands should be provisioned by configuration and limited brand-specific code, not by cloning the entire application.

Long term, D8N should be capable of powering external dating businesses in a model similar to Shopify for commerce or white-label dating platforms, but with stronger identity, verification, trust, safety, payments, and analytics infrastructure.

This does not mean external franchises should be built first.

It means the internal architecture should avoid decisions that make external operators impossible later.

The long-term target is:

```txt
D8N Platform
  Identity
  Profiles
  Match
  Chat
  Verify
  Trust
  Media
  Notify
  Pay
  Analytics
  Admin

Brands
  HookUs
  Date9ja
  DateSA
  DateAussie
  Future Brands

External Operators
  Partner Brand A
  Community Dating Brand B
  Franchise Brand C
```

## Product Naming Legend

The public D8N product names and internal engineering domains refer to the same platform capabilities.

```txt
Public / Product Name   Engineering Domain
------------------------------------------
D8N ID                  Identity
D8N Profiles            Profiles
D8N Match               Matching
D8N Chat                Messaging
D8N Verify              Verification
D8N Trust               Trust
D8N Media               Media
D8N Pay                 Billing
D8N Notify              Notifications
D8N Insights            Analytics
D8N Admin               Admin
```

## Guiding Principles

### 1. Shared Core, Distinct Experiences

Backend capabilities should be shared wherever possible.

Frontend experiences should not be forced to look or feel identical.

Date9ja, HookUs, and DateSA may share identity, chat, verification, media, trust, and payments while still having different onboarding, profile fields, tone, matching rules, and brand design.

### 2. Tenant Awareness From Day One

Every brand-owned record must clearly belong to a brand.

Examples:

- Profiles
- Photos
- Likes
- Matches
- Conversations
- Messages
- Reports
- Blocks
- Subscriptions
- Entitlements
- Notification preferences
- Analytics events

The platform must always know whether an action happened on Date9ja, HookUs, DateSA, or another brand.

### 3. Identity Is Not The Same As A Dating Profile

D8N must separate the real account from the brand-specific dating presence.

`User` represents the actual account.

`Profile` represents how that user appears inside a specific dating brand.

One user may eventually have:

- One Date9ja profile
- One HookUs profile
- One DateSA profile

But joining one brand must not automatically expose the person on another brand.

Identity may become portable.

Dating activity must remain brand-scoped and private.

### 4. Trust And Safety Must Be Platform-Level

Fraud, scams, abuse, identity manipulation, and serious safety concerns should not be rediscovered independently by every brand.

D8N needs shared risk intelligence.

However, the platform must distinguish:

- Brand-level moderation
- Network-level safety action

A minor community-rule violation on one brand should not automatically ban a user from all D8N products.

Serious fraud or safety risk may justify network-level action.

### 5. Build For Logical Isolation First

Initially, D8N can run on one PostgreSQL database.

But important data must be logically isolated by brand so that future physical isolation remains possible.

The design should make it possible to later move a large brand into separate infrastructure without rewriting the whole system.

### 6. Configuration Before Forking

Brand differences should be handled through configuration when reasonable.

Examples:

- Brand name
- Domain
- Logo
- Colors
- Country support
- Currency
- Minimum age
- Enabled features
- Profile fields
- Preference fields
- Matching strategy
- Verification requirements
- Subscription products
- Notification templates
- Safety policies

Forking the backend should be treated as a failure mode, not a normal way to launch brands.

### 7. Security And Privacy Are Architecture, Not Features

D8N is a dating platform. That makes security, privacy, moderation, fraud prevention, and auditability core product requirements.

They must be designed into the foundation instead of added later.

No major domain should be considered complete unless it answers:

- Who can access this data?
- Is the data brand-scoped, platform-scoped, or both?
- What gets logged?
- What should never be logged?
- What happens when a user deletes their account or brand profile?
- What happens when trust and safety needs to investigate abuse?
- What happens if an admin account is compromised?

### 8. Reviewable Decisions Over Informal Drift

Because D8N is being reviewed by multiple people, important architecture decisions should be written down before implementation.

The team should avoid changing core direction through scattered chat messages only.

Important decisions should be captured as Architecture Decision Records.

Examples:

- Modular monolith vs microservices
- Rails full-stack vs Rails API-only
- Authentication approach
- Authorization approach
- Brand resolution strategy
- Payment provider strategy
- Verification provider strategy
- Data retention policy
- Admin permission model
- Realtime messaging approach

This keeps Claude, the founder, the CTO, and future engineers aligned.

### 9. Internal Brands First, External Operators Later

D8N should first prove the platform with its own brands.

External operators, franchises, and white-label customers should come later, after D8N has proven:

- Brand isolation
- Identity/profile separation
- Trust and safety operations
- Billing and entitlements
- Admin permissions
- Analytics
- Media handling
- Verification
- Support workflows

However, the platform should be designed so external operators can eventually exist without a rewrite.

This means D8N should distinguish:

- Platform owner: D8N
- Brand owner: D8N or external partner
- Brand operator: the team allowed to manage that brand
- End user: the dating customer
- Admin user: someone with operational access

No external operator should ever receive unrestricted access to D8N network data.

External operators should only see and manage the brands, users, reports, billing records, and analytics they are permitted to access.

## Proposed Rails Structure

Initial repository:

```txt
d8n/
  app/
    controllers/
    models/
    services/
    jobs/
    mailers/
    policies/
  domains/
    identity/
    brands/
    profiles/
    matching/
    messaging/
    verification/
    trust/
    media/
    billing/
    notifications/
    analytics/
    admin/
  config/
    brands/
      date9ja.yml
      hookus.yml
      datesa.yml
      dateaussie.yml
  db/
  test/
```

The exact Rails layout can be refined during implementation, but the domain boundaries should be maintained.

## Initial Domain Responsibilities

### Brands

Responsible for:

- Brand registry
- Brand ownership
- Internal vs external operator classification
- Domains
- Configuration
- Feature flags
- Country and currency settings
- Brand policies
- Operator permissions
- Franchise / partner readiness

Core model:

- `Brand`
- `BrandOwner`
- `BrandMembership`
- `AdminAssignment`

Important distinction:

- `Brand` is the dating product.
- `BrandOwner` is the organization or person that owns the business relationship.
- `BrandMembership` defines an end user's relationship to a dating brand.
- `AdminAssignment` defines staff/operator access to administer a brand.

For D8N-owned brands, the owner is D8N.

For future external franchises or white-label partners, the owner may be an external organization.

External ownership must not imply access to platform-level data.

Do not merge end-user brand membership with staff/admin access.

Example:

```txt
User
  platform identity

BrandMembership
  user_id
  brand_id
  status

Profile
  user_id
  brand_id
  brand_membership_id
  dating presence inside one brand

AdminAssignment
  admin_user_id
  brand_id
  role
  permissions
```

### Identity

Responsible for:

- Registration
- Login
- Passwords
- Passwordless authentication
- Phone/SMS authentication
- Email authentication
- OAuth authentication
- Brand-specific authentication policy
- Sessions
- Devices
- Account recovery
- Account status
- Age eligibility
- Security events

Core models:

- `User`
- `IdentityIdentifier`
- `Credential`
- `AuthAttempt`
- `Session`
- `Device`
- `SecurityEvent`

Authentication must support different brand requirements.

Examples:

- Date9ja may require email, phone, password, and stronger verification.
- HookUs may allow phone-only signup with SMS OTP.
- A future professional brand may require email/password plus MFA.
- A future community or franchise brand may require invite-only access.

All authentication methods should produce the same platform-level session model.

The user experience can differ by brand, but session security, rate limiting, device tracking, audit logs, and account recovery must remain platform-standard.

Recommended auth architecture:

- Use Rodauth/Rodauth-Rails as the preferred mature Ruby/Rails authentication engine, subject to implementation spike.
- Add a D8N credential and strategy layer above the auth engine so brands can choose different auth policies.
- Reuse mature libraries for password hashing, sessions, lockout, WebAuthn, OTP/TOTP, recovery, JSON/JWT API behavior, and related security controls where practical.
- Do not write custom crypto, password hashing, token signing, or session security from scratch.

Suggested credential model:

```txt
credentials
  id
  user_id
  kind
  identifier
  verified_at
  last_used_at
  metadata
  deleted_at
  created_at
  updated_at
```

Possible credential kinds:

- `email_password`
- `email_otp`
- `phone_otp`
- `oauth`
- `webauthn`
- `recovery_code`

All credential strategies must produce the same D8N session result.

```txt
AuthStrategy input
  brand
  credential kind
  identifier
  proof
  device context
  request context

AuthStrategy output
  user
  session
  security event
  risk signals
```

Brand examples:

```txt
HookUs
  signup: phone_otp
  required: phone verified
  optional: email, WebAuthn later

Date9ja
  signup: email_password or phone_otp
  required: email or phone verified
  stronger verification encouraged or required by policy

Future professional brand
  signup: email_password
  required: email verified
  admin/staff: MFA required

Future invite-only brand
  signup: invitation + email or phone
  required: invitation accepted
```

Phone-only auth can be acceptable for some consumer brands if implemented carefully.

Required controls:

- OTP expiry
- Single-use OTPs
- Per-phone rate limits
- Per-IP rate limits
- Exponential backoff
- Attempt lockout
- Device/session tracking
- Generic responses to prevent account enumeration
- Re-verification for sensitive actions
- Risk checks for number changes
- Audit logs for phone changes, failed attempts, and recovery

Phone-only auth should not be treated as strong identity verification.

Sensitive actions may require step-up verification:

- Payments
- Payouts
- Email/phone changes
- Account recovery
- Cross-brand identity portability
- Verification reuse
- Admin/operator access

Implementation note:

Rodauth supports many relevant security features, but D8N must confirm through a spike how best to model phone-first OTP as a first authentication factor in an API-only Rails app. If Rodauth cannot cleanly support a required brand flow, D8N should still preserve the same credential/strategy interface and use mature lower-level libraries rather than building fragile custom auth.

### Identity Identifiers And Account Linking

D8N should normalize identity identifiers so the platform can reason about emails, phone numbers, and provider identities safely.

Examples:

```txt
identity_identifiers
  id
  user_id
  kind
  normalized_value
  verified_at
  last_seen_at
  metadata
  deleted_at
  created_at
  updated_at
```

Possible kinds:

- `email`
- `phone`
- `oauth_provider_uid`
- `device_fingerprint`

Credential linking is allowed.

Automatic account merging is not allowed.

If two accounts later appear to belong to the same person, D8N should not silently merge them. That is a security and privacy risk in a dating platform.

Allowed account resolution path:

- Detect possible duplicate through identifiers or risk signals.
- Lock or step-up verify sensitive operations if needed.
- Require support-assisted review for merges.
- Require user consent where appropriate.
- Preserve an audit trail.
- Never merge profiles, messages, matches, photos, or brand memberships automatically.

### Profiles

Responsible for:

- Brand-specific dating profiles
- Profile fields
- Preferences
- Photos linked to profiles
- Profile completion
- Visibility

Core models:

- `Profile`
- `ProfilePhoto`
- `ProfilePreference`
- `ProfilePrompt`

### Matching

Responsible for:

- Discovery
- Likes
- Passes
- Matches
- Recommendation strategy
- Brand-specific matching policies

Core models:

- `Like`
- `Pass`
- `Match`
- `Recommendation`

### Messaging

Responsible for:

- Conversations
- Messages
- Read receipts
- Typing state
- Attachments
- Blocking hooks
- Reporting hooks
- Realtime delivery integration

Core models:

- `Conversation`
- `ConversationParticipant`
- `Message`
- `MessageReceipt`

### Verification

Responsible for:

- Email verification
- Phone verification
- Selfie verification
- Liveness checks
- ID verification
- Provider integrations
- Verification status

Core models:

- `UserVerification`
- `VerificationCheck`

### Trust

Responsible for:

- Reports
- Blocks
- Moderation cases
- Risk scoring
- Platform-level enforcement
- Brand-level enforcement
- Audit trail

Core models:

- `Report`
- `Block`
- `ModerationCase`
- `TrustSignal`
- `EnforcementAction`

### Media

Responsible for:

- Uploads
- Image processing
- Video processing
- Thumbnails
- Storage
- Signed URLs
- Metadata stripping
- Malware scanning
- Content moderation hooks
- Deletion

Core models:

- `MediaAsset`
- `MediaVariant`

### Billing

Responsible for:

- Products
- Prices
- Subscriptions
- One-time purchases
- Entitlements
- Provider webhooks
- Refunds
- Receipts

Core models:

- `Product`
- `Price`
- `Subscription`
- `Transaction`
- `Entitlement`

Provider targets:

- Stripe
- Paystack
- Additional regional providers later

### Notifications

Responsible for:

- Email
- SMS
- Push
- WhatsApp
- In-app notifications
- Templates
- User preferences
- Provider routing
- Cost-aware channel selection

Core models:

- `Notification`
- `NotificationPreference`
- `NotificationTemplate`

### Analytics

Responsible for:

- Standardized event tracking
- Brand-level metrics
- Funnel metrics
- Retention metrics
- Revenue metrics
- Safety metrics

Core model:

- `AnalyticsEvent`

Initial standard events:

- `user.registered`
- `profile.created`
- `profile.completed`
- `photo.uploaded`
- `verification.completed`
- `profile.viewed`
- `like.created`
- `match.created`
- `conversation.started`
- `message.sent`
- `report.created`
- `user.blocked`
- `subscription.started`
- `subscription.cancelled`

### Admin

Responsible for:

- Network dashboard
- Brand dashboard
- User management
- Profile review
- Reports queue
- Moderation
- Verification review
- Billing support
- Analytics
- Role-based access control

Core models:

- `AdminUser`
- `AdminRole`
- `AdminPermission`
- `AuditLog`

## Database Foundation

Initial critical tables:

```txt
brands
brand_owners
brand_memberships
admin_assignments
users
identity_identifiers
credentials
auth_attempts
sessions
devices
security_events
profiles
profile_photos
profile_preferences
likes
passes
matches
conversations
conversation_participants
messages
reports
blocks
user_verifications
media_assets
products
prices
subscriptions
transactions
entitlements
notifications
analytics_events
admin_users
admin_roles
admin_permissions
audit_logs
```

Initial `brands` table should reserve ownership concepts even if all launch brands are D8N-owned:

```txt
id
owner_type
owner_id
slug
name
status
created_at
updated_at
deleted_at
```

The exact owner implementation can be reviewed by the CTO, but Phase 2 should not hard-code the assumption that every brand is D8N-owned forever.

Initial relationship rules:

```txt
users
  platform identities

brand_memberships
  user_id
  brand_id
  status

profiles
  user_id
  brand_id
  brand_membership_id
  status

admin_assignments
  admin_user_id
  brand_id
  admin_role_id
  status
```

Important constraints to design for:

- One active brand membership per user per brand.
- One active profile per user per brand.
- A profile must belong to a membership for the same user and brand.
- Likes should not allow self-like.
- Matches should use deterministic user/profile pair ordering.
- Matches should be unique for the same brand and participant pair.
- Conversations should not cross brands unless a future feature explicitly allows it.
- Admin assignments must not be confused with consumer brand memberships.

Most brand-owned tables should include:

```txt
brand_id
created_at
updated_at
deleted_at
```

High-risk or operationally important records should include auditability:

```txt
created_by_id
updated_by_id
deleted_by_id
deletion_reason
restored_at
restored_by_id
source
metadata
```

The platform should enforce brand scoping at the application layer and database level where practical.

Brand-owned tables should use partial indexes where soft deletion affects uniqueness.

Examples:

```txt
unique active profile per user per brand:
  unique(user_id, brand_id) where deleted_at is null

unique active brand slug:
  unique(slug) where deleted_at is null
```

## Tenant Query Safety

D8N should not rely on developer memory alone for tenant isolation.

Default scopes can hide bugs and make admin/network workflows difficult, so they should not be the only isolation mechanism.

Recommended approach:

- Use an explicit request context object that carries `current_brand`, `current_user`, permissions, locale, and feature flags.
- Provide required tenant-scoped query helpers for brand-owned models.
- Make unsafe unscoped access difficult and visible in review.
- Add tests that prove cross-brand access is blocked.
- Allow explicit network/admin queries only through named, audited paths.

Example concept:

```ruby
Profiles::VisibleForBrand.call(context: current_context)
```

not:

```ruby
Profile.where(active: true)
```

The exact Rails implementation should be decided during Phase 1/2, but the rule is mandatory: brand-owned data access must be explicitly scoped or intentionally network-level.

## API Direction

The first API should be versioned.

Example:

```txt
/api/v1/auth
/api/v1/me
/api/v1/profiles
/api/v1/discovery
/api/v1/likes
/api/v1/matches
/api/v1/conversations
/api/v1/messages
/api/v1/reports
/api/v1/verifications
/api/v1/billing
```

Every request should resolve:

- Current user
- Current brand
- Country / locale where relevant
- Permissions
- Enabled features

Brand resolution may come from:

- Domain
- Subdomain
- Request header
- API client configuration

This needs a formal decision before public API work begins.

## Frontend And Repository Strategy

D8N Core should be API-only.

The platform should expose versioned APIs that can power:

- D8N admin
- Date9ja web
- HookUs web
- Mobile apps
- Future brand frontends
- Future external operator portals

The core platform should not become tightly coupled to one public marketing site or one consumer frontend.

### Marketing Site

The D8N marketing landing page should be separate from the API core.

Recommended approach:

- Build the D8N marketing site with Next.js
- Keep it in a separate repository when the public brand site becomes real
- Use it for public pages, SEO, brand storytelling, investor/partner pages, franchise/partner waitlists, and lead capture
- Integrate with the D8N API only where needed, such as waitlist signup or partner inquiry forms

Reasoning:

- Marketing pages need SEO, fast static rendering, content flexibility, and design freedom
- The API core should stay focused on identity, tenancy, dating operations, safety, billing, and platform capabilities
- A separate marketing repo avoids coupling deploy risk between the public website and the dating platform
- Next.js is a strong fit for content-heavy public pages and future marketing experiments

Hotwire/Turbo remains a good Rails ecosystem choice for internal admin or operational tools if the CTO prefers Rails-native workflows.

### Admin Frontend

D8N Admin can start inside the Rails application if that gives the fastest secure operational path.

Recommended options:

- Rails API plus server-rendered Rails/Hotwire admin inside the platform app
- Rails API plus separate admin frontend later if admin complexity grows

Admin should be optimized for security, speed of internal operations, auditability, and role-based access control.

It does not need the same technology choice as the marketing site.

### Consumer Brand Frontends

Consumer brand frontends should be separate from the API core once they become serious products.

Examples:

```txt
d8n-platform      Rails API core
d8n-marketing     D8N public marketing site
date9ja-web       Date9ja consumer web
hookus-web        HookUs consumer web
datesa-web        DateSA consumer web
```

This allows each brand to have its own product experience without turning the platform into a white-label UI clone.

### Current Repo Rule

This repository should remain the D8N planning/platform repository for now.

When implementation starts:

- Use this repo for the Rails API platform if approved
- Create a separate repo for the D8N marketing site when the landing page build begins
- Do not mix the marketing site into the API platform unless there is a short-term tactical reason approved by the CTO

## Security And Privacy Requirements

These are foundation requirements, not future polish.

### Authentication

- Secure password hashing
- Session expiry
- Device tracking
- Account lock and recovery flows
- Admin access separated from consumer access
- Multi-factor authentication for admins

### Authorization

- Role-based admin permissions
- Brand-scoped moderator access
- Network-level admin access only for trusted roles
- No implicit cross-brand data access

### Privacy

- A user joining one brand must not become visible on another brand automatically
- Dating activity must remain brand-scoped
- Verification portability must be explicit and carefully communicated
- Data deletion must account for brand profile data and platform identity data separately
- Normal user deletion should be soft deletion first so accounts can be recovered where policy allows
- Legal erasure requests must have a separate anonymization or hard-delete workflow where required

### Deletion, Recovery, And Retention

D8N should use soft deletion as the default operational behavior.

Soft deletion means records are marked as deleted or deactivated instead of being immediately removed from the database.

This supports:

- Account recovery
- Fraud investigation
- Abuse investigation
- Billing support
- Moderation history
- Auditability
- Accidental deletion recovery

Suggested columns for soft-deletable records:

```txt
deleted_at
deleted_by_id
deletion_reason
restored_at
restored_by_id
```

Important soft-deletable records:

- Users
- Profiles
- Photos/media assets
- Conversations
- Messages
- Reports
- Blocks
- Subscriptions
- Admin users
- Brand memberships

Deletion should be treated differently depending on the object:

- User account deactivation: disables login and visibility but may be recoverable
- Brand profile deletion: removes that user's presence from one brand but does not delete the D8N identity
- Media deletion: should revoke access immediately and queue storage cleanup
- Message deletion: may hide content from users while preserving moderation/audit records where policy allows
- Admin deletion: should disable access, not erase the historical admin actor

Recovery should be explicit and audited.

No deleted account, profile, or admin user should be restored silently.

Every restore should record:

- Who restored it
- When it was restored
- Why it was restored
- Which brand/domain it affected

Soft deletion is not a substitute for privacy compliance.

D8N must also support legal data deletion workflows such as:

- Data export
- Account erasure
- Brand profile erasure
- Anonymization of retained records
- Media purge from object storage/CDN
- Provider-side deletion where supported

The platform should distinguish:

- Recoverable deletion
- Permanent erasure
- Anonymized retention
- Legally required retention

This decision needs CTO and legal/privacy review before production.

### Auditability

Audit logs are required for:

- Admin access
- Moderation decisions
- Enforcement actions
- Verification decisions
- Billing support actions
- Sensitive profile/user changes

### Safety

The platform should support:

- Reporting
- Blocking
- Photo moderation
- Message reporting
- User risk signals
- Network-level safety enforcement
- Brand-level moderation policies

### Data Classification

D8N should classify data from the beginning.

Suggested classes:

- Public profile data
- Private profile data
- Account identity data
- Verification data
- Payment data
- Message data
- Location data
- Device/security data
- Moderation data
- Analytics data

Each class should define:

- Storage rules
- Access rules
- Retention rules
- Logging rules
- Export/deletion behavior

Verification data, payment data, message data, device data, and moderation data should be treated as highly sensitive.

### Admin Security

Admin security must be stricter than consumer account security.

Requirements:

- Mandatory MFA for admin users
- Role-based access control
- Brand-scoped moderator permissions
- Network-level access limited to trusted roles
- Audit logs for sensitive reads and writes
- No shared admin accounts
- Principle of least privilege
- Fast ability to suspend admin access

### Secure Engineering Baseline

Before production, D8N should have:

- Dependency scanning
- Secret scanning
- Static analysis where practical
- Environment-based secrets management
- No secrets committed to the repository
- HTTPS-only production traffic
- Secure cookie/session settings
- Rate limiting for authentication and messaging-sensitive endpoints
- Provider webhook signature verification
- Idempotency for payment and verification webhooks
- Backup and restore testing
- Incident response checklist

## Infrastructure Direction

Initial infrastructure target:

```txt
Cloudflare
Rails Web/API
Rails Workers
PostgreSQL
Redis
Cloudflare R2
CDN
Email/SMS providers
Payment providers
Monitoring
Error tracking
```

Avoid adding Kubernetes, microservices, event streaming, or complex distributed systems until there is a clear operational need.

## External Operator And Franchise Readiness

D8N may eventually power dating businesses owned or operated by external parties.

Examples:

- A community wants its own dating platform
- A religious organization wants a private dating network
- A regional entrepreneur wants to operate a licensed D8N-powered dating brand
- A media company wants a branded dating product
- A matchmaker wants digital infrastructure for their audience

This future model should be treated as a platform expansion path, not the first product.

The first priority is still to prove D8N with internal brands such as Date9ja and HookUs.

### Required Future Capabilities

To support external operators later, the architecture should eventually support:

- External brand ownership
- Brand-level operator accounts
- Strict operator permissions
- White-label brand configuration
- Custom domains
- Brand-specific onboarding
- Brand-specific legal pages
- Brand-specific notification templates
- Brand-specific payment products
- Platform fees charged by D8N
- Usage-based billing for operators
- Verification usage billing
- Messaging/media usage billing
- Operator analytics
- Operator support tools
- Data export rules
- Contract-based feature access

### Platform Billing Model

External operators may eventually pay D8N through:

- Monthly platform fee
- Per active user fee
- Verification usage fee
- Messaging/media usage fee
- Payment processing percentage
- Premium support fee
- Setup fee
- Revenue share

This requires D8N Billing to support two billing layers:

- End-user billing: dating users paying for subscriptions, boosts, events, or premium features
- Operator billing: external brand owners paying D8N for platform usage

These should not be mixed together in the data model.

### Operator Admin Boundary

External operators should get a restricted admin experience.

They may be allowed to:

- Manage their brand configuration
- View their users
- Review reports for their brand
- View their analytics
- Manage their subscription products
- Manage notification templates
- Invite their staff

They should not be allowed to:

- View other brands
- View D8N network-wide intelligence
- Access raw verification data unless explicitly permitted
- Access sensitive platform trust signals unless policy allows it
- Export data without permission and audit trail
- Modify platform-level safety rules
- Modify billing provider configuration

### Data Boundary

External operator support makes brand isolation even more important.

For every table, D8N should be clear whether the data is:

- Platform-owned
- Brand-owned
- Operator-owned
- End-user-owned
- Shared only through explicit policy

Future franchise support should never require exposing one brand's private data to another operator.

### Not A Launch Requirement

The first production version does not need a full franchise portal.

But the first production version should avoid choices that block it.

Specifically:

- Do not hard-code all brands as D8N-owned forever
- Do not assume every admin is a D8N employee
- Do not assume all billing is end-user billing
- Do not assume all brand configuration lives only in code
- Do not make network-level trust data visible to brand operators by default
- Do not make cross-brand user/profile visibility implicit

## Build Phases

Each phase should pass technical review before the next major phase begins.

Review does not need to be slow, but it should be explicit.

### Phase 0: Architecture Approval

Deliverables:

- Approve this plan
- Approve modular monolith approach
- Approve initial domains
- Approve identity/profile separation
- Approve tenant/brand model
- Decide initial frontend strategy
- Decide first production brand
- Create initial Architecture Decision Records
- Define security baseline
- Define reviewer approval process
- Confirm external operator readiness as a future architectural requirement
- Confirm flexible per-brand authentication architecture

Reviewer questions:

- Is the tenant model strong enough?
- Are privacy boundaries explicit enough?
- Are we overbuilding any domain too early?
- Are there missing regulatory or safety concerns?
- Is Rails the right initial platform?
- Are admin permissions strict enough?
- Are data deletion and retention responsibilities clear enough?
- Are we designing for safe future service extraction?
- Are we preserving the future option to support external operators without overbuilding it now?
- Does the auth architecture support phone-only, email/password, OAuth, invite-only, and MFA-required brands without custom security mistakes?

### Phase 1: Platform Skeleton

Deliverables:

- New Rails application, preferably created with `rails new`
- PostgreSQL setup
- Test framework
- CI setup
- Linting and formatting
- Basic health check
- Environment configuration
- Error tracking
- Basic deployment path

Acceptance criteria:

- App boots locally
- Rails skeleton follows Rails conventions, using generators where they are a good fit
- Test suite runs
- CI runs on pull request
- Database migrations work
- Deployment target is defined
- Secrets are not stored in code
- Basic security scanning is configured

### Phase 2: Brands And Identity

Deliverables:

- `Brand`
- Brand ownership placeholder
- Brand operator placeholder
- Brand resolution
- `User`
- `Credential`
- Auth strategy interface
- Registration
- Login
- Logout
- Sessions
- Phone OTP flow
- Account status
- Basic admin user

Acceptance criteria:

- A request can be resolved to a brand
- A user can register under a brand context
- Identity is not tied to one brand profile
- Admin and consumer auth are clearly separated
- Brand scoping is covered by tests
- Admin access requires stronger controls than consumer access
- HookUs can support phone-first signup
- Auth attempts are rate-limited and audited
- The schema does not assume every brand is D8N-owned forever

### Phase 3: Profiles

Deliverables:

- Brand-specific profiles
- Profile fields
- Preferences
- Profile photos
- Visibility rules
- Basic profile completion

Acceptance criteria:

- One user can have separate profiles on separate brands
- Profile data is brand-scoped
- Brand-specific required fields are configurable
- Profiles are not automatically copied between brands

### Phase 4: Discovery And Matching

Deliverables:

- Discovery feed
- Like
- Pass
- Match creation
- Brand-specific matching strategy interface
- Initial HookUs strategy
- Initial Date9ja strategy placeholder

Acceptance criteria:

- Discovery only shows eligible profiles for the current brand
- Likes and matches are brand-scoped
- Matching logic can differ by brand

### Phase 5: Messaging

Deliverables:

- Conversations
- Participants
- Messages
- Read receipts
- Basic realtime or polling path
- Reporting/blocking hooks

Acceptance criteria:

- Matched users can message
- Conversations are brand-scoped
- Blocked users cannot continue messaging
- Messages can be reported

### Phase 6: Verification And Media

Deliverables:

- Media upload abstraction
- R2 storage integration
- Image variants
- Basic moderation hooks
- Email verification
- Phone verification
- Selfie/ID verification model design

Acceptance criteria:

- Profile photos can be uploaded and served securely
- Verification status is stored at user/platform level where appropriate
- Brands can require different verification levels

### Phase 7: Trust And Safety

Deliverables:

- Reports
- Blocks
- Moderation queue
- Enforcement actions
- Trust signals
- Audit logs

Acceptance criteria:

- Reports enter a review queue
- Moderators can act only within permitted scope
- Serious platform-level enforcement is possible
- All moderation actions are audited

### Phase 8: Billing

Deliverables:

- Products
- Prices
- Entitlements
- Subscriptions
- Payment provider abstraction
- Stripe integration
- Paystack integration when needed

Acceptance criteria:

- Brands can define their own paid products
- Entitlements are enforced by brand
- Payment webhooks are handled idempotently

### Phase 9: Notifications And Analytics

Deliverables:

- Notification preferences
- Templates
- Email provider
- SMS provider abstraction
- Standard analytics events
- Admin metrics

Acceptance criteria:

- Events are emitted consistently
- Notifications respect user preferences
- Metrics can be compared across brands

### Phase 10: D8N Admin

Deliverables:

- Network dashboard
- Brand dashboard
- User search
- Profile review
- Reports queue
- Verification review
- Billing support view
- Role-based permissions

Acceptance criteria:

- Group admin can see network-level data
- Brand moderators are restricted to assigned brands
- Sensitive actions are audited

### Phase 11: Date9ja Migration And Second-Brand Proof

Deliverables:

- Date9ja legacy system inventory
- Date9ja schema inventory
- Date9ja credential/password-hash inventory
- Date9ja media inventory
- Date9ja data mapping plan
- Migration dry run
- Reconciliation reports
- Rollback plan
- Date9ja configured on D8N as the second brand
- Distinct profile requirements
- Distinct matching strategy
- Distinct frontend/API client behavior if applicable

Acceptance criteria:

- Legacy Date9ja auth/password behavior is understood before migration
- Date9ja users, profiles, photos, matches, and messages are mapped deliberately
- Migration counts reconcile across source and target
- Migration can be dry-run without mutating production data
- Rollback or fallback plan exists before cutover
- Date9ja runs on the same platform core
- Date9ja and HookUs users/data remain properly isolated
- Shared services work across both brands
- Brand experience does not feel like a cheap copy

## Technical Standards

### Code Quality

- Clear domain ownership
- Service objects for complex workflows
- Models should not become unbounded business logic containers
- Background jobs for slow external operations
- Idempotent webhook handling
- Explicit error handling for provider integrations
- No hidden cross-brand data access

### Testing

Required coverage:

- Model validations
- Brand scoping
- Authorization
- Authentication
- Matching behavior
- Messaging permissions
- Blocking/reporting behavior
- Payment webhooks
- Admin permissions
- Critical privacy boundaries

Tenant isolation tests are mandatory.

Examples:

- Date9ja user cannot see HookUs profile unless explicitly eligible inside HookUs
- Date9ja moderator cannot access DateSA reports
- Match creation cannot cross brands accidentally
- Conversation cannot include users from different brand contexts unless a future cross-brand feature explicitly allows it

### Database

- Use foreign keys
- Use indexes deliberately
- Use unique constraints for important invariants
- Use check constraints where practical
- Avoid storing provider-specific logic directly in core domain tables
- Use JSON metadata only where structure is genuinely flexible
- Use soft deletion by default for important operational records
- Avoid foreign key designs that break when a user/profile/admin is soft-deleted
- Keep historical references to deleted admin actors for audit purposes
- Use partial indexes where needed to enforce uniqueness only among active records

### Background Jobs

Use jobs for:

- Email
- SMS
- Push
- Media processing
- Payment webhooks
- Analytics fanout
- Moderation provider calls
- Verification provider calls

### Observability

Required from early production:

- Error tracking
- Request logging
- Job failure logging
- Payment webhook logging
- Admin audit logs
- Security event logs
- Basic performance metrics

## Collaboration And Review Process

D8N should be built with a lightweight but serious review process.

The purpose is not to slow the build down. The purpose is to prevent foundational mistakes in tenancy, privacy, security, payments, moderation, and data modeling.

### Roles

Founder / Product Owner:

- Owns product direction
- Approves brand priorities
- Approves privacy and trust posture
- Resolves tradeoffs between speed, scope, and risk

CTO / Technical Reviewer:

- Reviews architecture soundness
- Reviews database design
- Reviews security and scalability risks
- Approves major technical decisions before implementation

Claude / AI Reviewer:

- Reviews plans, code, and architecture for gaps
- Challenges assumptions
- Suggests alternative designs
- Helps identify security, privacy, and scaling risks

Codex / Implementation Agent:

- Implements approved work
- Keeps changes scoped
- Adds tests for important behavior
- Surfaces blockers and risky assumptions
- Updates documentation when implementation changes the plan

### Decision Process

For normal implementation details:

- Codex can choose the simplest approach consistent with this document
- Changes should be covered by tests where risk justifies it

For major architecture decisions:

- Write or update an Architecture Decision Record
- Review with founder, Claude, and CTO
- Approve before implementation

Major decisions include:

- Changing the tenancy model
- Changing the identity/profile model
- Adding cross-brand visibility
- Changing admin permission strategy
- Adding payment architecture
- Adding verification architecture
- Extracting a service from the monolith
- Introducing a major infrastructure dependency

### Security Review Gates

The following areas require explicit security review before production use:

- Authentication
- Admin access
- Brand scoping
- Messaging
- Media upload
- Verification
- Payments
- Reports and moderation
- Data deletion
- Webhooks

### Pull Request Expectations

Every meaningful code change should explain:

- What changed
- Why it changed
- Which brand/domain it affects
- How tenant isolation is preserved
- What tests were added or updated
- Any security/privacy implications

### Architecture Decision Records

Create an `docs/adr/` directory once implementation begins.

Suggested starting ADRs:

```txt
docs/adr/0001-use-modular-rails-monolith.md
docs/adr/0002-brand-tenancy-model.md
docs/adr/0003-separate-user-identity-from-brand-profiles.md
docs/adr/0004-admin-authorization-model.md
docs/adr/0005-brand-resolution-strategy.md
```

Each ADR should include:

- Status
- Context
- Decision
- Consequences
- Alternatives considered

## Open Decisions For Review

These should be reviewed before implementation begins.

Confirmed direction, still requiring CTO review:

1. D8N Core is a Rails API-only platform.
2. D8N marketing site is a separate Next.js application/repository.
3. HookUs is the first product build target.
4. Date9ja becomes the second-brand proof/migration target.
5. Authentication should use a flexible credential/strategy model, preferably backed by Rodauth/Rodauth-Rails after implementation spike.

Remaining open decisions:

1. How should brand resolution work in API requests?
2. Which authorization library should be used?
3. Which payment provider should be integrated first?
4. Which verification provider should be integrated first?
5. Which media moderation provider should be integrated first?
6. What data retention and deletion policy should D8N adopt from day one?
7. What admin roles should exist at launch?
8. Which events require audit logs from day one?
9. What is the minimum security baseline before private beta?
10. What is the minimum trust and safety workflow before real users join?
11. What is the policy for network-level bans across multiple brands?
12. What data and admin boundaries would be required before allowing an external operator?
13. Should external operator support be represented in the schema from day one or deferred until after internal brand proof?
14. What parts of brand configuration must be database-driven before any white-label/franchise launch?
15. What is the exact policy for soft deletion, account recovery, permanent erasure, and anonymized retention?
16. How long should deleted accounts remain recoverable?
17. Which deleted records must remain available for moderation, fraud, billing, or legal audit?
18. What data residency or regional data-handling requirements apply to DateSA, DateAussie, and future international brands?

## Recommended Initial Decisions

Subject to CTO review:

- Use Ruby on Rails as the modular monolith
- Build D8N Core as an API-only Rails platform
- Build HookUs first
- Use Date9ja as the second-brand proof/migration target
- Use a Rodauth/Rodauth-Rails-backed credential/strategy auth model if the implementation spike validates the required brand flows
- Use PostgreSQL as the primary database
- Use Redis for cache, jobs, and realtime support where needed
- Use Sidekiq or Solid Queue depending on deployment preference
- Use Cloudflare R2 for media storage
- Use Stripe first for global cards
- Add Paystack for Nigeria/Africa payments when billing reaches that market
- Build admin inside the Rails app first if Rails/Hotwire speeds up secure operations
- Build the D8N marketing landing site separately with Next.js
- Keep consumer web/mobile clients separate once product direction is clearer
- Preserve external operator ownership concepts in the brand schema from day one

## Definition Of Success

D8N's foundation is successful when:

- HookUs can run on the same platform
- Date9ja can run on the platform
- Both brands share core infrastructure
- Both brands remain clearly distinct to users
- User identity is portable only where explicitly intended
- Dating activity remains private and brand-scoped
- Trust and safety benefits from network intelligence
- Admin users can operate the portfolio from one command center
- New brands can be added through configuration plus limited brand-specific code
- The platform can later extract high-load domains into services without a full rewrite
- The platform can eventually support external operators without exposing D8N network data or rewriting the brand model
- Users can recover accounts where policy allows, while D8N still supports permanent erasure/anonymization where legally required
- Deletions and restorations are auditable

## Near-Term Next Step

Before writing application code, complete Phase 0 review.

After approval:

1. Create initial ADRs for the foundational decisions.
2. Create the initial Rails application.
3. Implement Phase 1 and Phase 2.

Initial implementation sequence:

1. Platform skeleton
2. Brand model
3. Brand resolution
4. User identity
5. Authentication
6. Basic admin access
7. Tenant isolation tests
8. Initial security baseline

This creates the foundation for every later D8N capability.
