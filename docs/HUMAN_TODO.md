# D8N Human TODO

## Purpose

This is the founder/operator checklist for decisions and work that cannot be completed by code agents alone.

Use this alongside `PLAN_OF_ACTION.md`, `AGENT_RULES.md`, and future ADRs.

## Phase 0: Before Code

- Approve D8N Core as Rails API-only.
- Approve HookUs as the first product build target.
- Approve Date9ja as the second-brand proof/migration target.
- Approve separate Next.js repo for D8N marketing.
- Approve Rodauth/Rodauth-Rails credential strategy spike.
- Choose CTO reviewer and review cadence.
- Decide where ADR approvals live.
- Decide private beta target market.
- Decide initial production hosting provider.
- Decide initial SMS provider.
- Decide initial email provider.
- Decide initial payment provider.
- Decide initial media moderation provider.
- Decide initial verification provider.

## Legal And Privacy

- Get legal review for terms of service.
- Get legal review for privacy policy.
- Define minimum age per brand/market.
- Define data retention policy.
- Define account recovery window.
- Define permanent erasure/anonymization policy.
- Define country-specific privacy requirements.
- Review South Africa POPIA obligations before DateSA.
- Review Australian Privacy Act obligations before DateAussie.
- Review Nigerian NDPA obligations before Date9ja.
- Define process for law-enforcement requests.
- Define process for user data export.
- Define process for user data deletion.

## Trust And Safety

- Define prohibited behavior.
- Define report categories.
- Define moderation severity levels.
- Define brand-level vs network-level enforcement.
- Define when a network ban is allowed.
- Define appeal process.
- Define moderator permissions.
- Define escalation process for serious safety cases.
- Define fraud/scam review process.
- Define photo moderation policy.
- Define message reporting policy.

## Product Decisions

- Define HookUs positioning.
- Define HookUs onboarding.
- Define HookUs required profile fields.
- Define HookUs matching philosophy.
- ADR 0009 profile-level ownership and Slice 1 private-location boundary approved on 2026-08-13; approve the shared eligibility and brand-strategy implementation before Slice 2.
- Confirm before beta that HookUs activation, rather than discovery, owns the profile-completion publication gate.
- Confirm before beta the initial HookUs policy: location becomes stale after 24 hours and is required only when either side sets a distance limit.
- Confirm before beta the initial HookUs policy: discovery displays no distance value.
- Define HookUs auth policy.
- Define HookUs verification policy.
- Define HookUs monetization.
- Define Date9ja positioning for second-brand proof.
- Define Date9ja required profile fields.
- Define Date9ja matching philosophy.
- Migrate the existing live Date9ja product onto D8N rather than treating it as a clean brand configuration.
- Inventory Date9ja schema, auth/password behavior, media, messages, matches, and required migration counts before Phase 11.

## Location Privacy

- Define informed consent copy and withdrawal behavior for precise location.
- Define location freshness and retention periods.
- Define whether clients may read stored coordinates back or only replace/delete them.
- Confirm POPIA treatment of precise location before the Cape Town private beta.
- Define support and admin access rules for precise location; default to no access.

## Brand And Marketing

- Decide D8N public positioning.
- Decide D8N marketing site pages.
- Decide D8N partner/franchise waitlist copy.
- Prepare brand assets.
- Prepare domain strategy.
- Prepare investor/partner deck if needed.
- Prepare architecture diagrams for CTO/investor review.

## Operations

- Choose support tool or inbox.
- Choose incident management process.
- Choose monitoring/error tracking stack.
- Choose analytics stack.
- Choose backup policy.
- Choose on-call process for production.
- Decide who can access production data.
- Decide who can access admin.
- Decide admin MFA requirements.

## Finance And Cost

- Estimate SMS cost per market.
- Estimate email cost.
- Estimate media storage/CDN cost.
- Estimate verification cost.
- Estimate payment processing cost.
- Estimate hosting cost at 50k, 100k, and 1m users.
- Decide whether to self-host email later using a tool like UseSend.
- Decide when usage-based operator billing becomes necessary.

## Review Checklist

Before implementation starts:

- Founder approval complete.
- CTO architecture review complete.
- Claude review complete.
- ADRs created for foundational decisions.
- Human TODO blockers identified.
- Phase 1 implementation scope approved.
