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
- Review South Africa POPIA obligations before DateZA.
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
- Define message retention, export, deletion, and legal-erasure behavior.
- Define whether suspended or banned counterpart conversation history remains readable.
- Define the evidence-access policy for moderators reviewing reported messages.
- Define photo moderation categories, reviewer permissions, appeal behavior, and
  whether automated approval is permitted.

## Product Decisions

- Define HookUs positioning.
- Define HookUs onboarding.
- Define HookUs required profile fields.
- Define HookUs matching philosophy.
- ADR 0009 profile-level ownership, private-location boundary, shared eligibility, and brand-strategy contract approved through Slice 5 on 2026-08-13; Date9ja production scoring remains blocked.
- ADR 0010 match-gated messaging architecture and metadata-only Slice 1 approved on 2026-08-13; message-content APIs remain blocked on the documented privacy and trust-and-safety gate.
- Confirm before beta that HookUs activation, rather than discovery, owns the profile-completion publication gate.
- Confirm before beta the initial HookUs policy: location becomes stale after 24 hours and is required only when either side sets a distance limit.
- Confirm before beta the initial HookUs policy: discovery displays no distance value.
- Define HookUs auth policy.
- HookUs zero-friction phone/password and email/password signup approved on
  2026-08-13; identifiers remain unverified until later proof. Google is deferred.
- Six-character password minimum with no composition rules approved on
  2026-08-13.
- Approve breached-password handling, reset/session-revocation behavior, and
  recovery/support policy.
- Choose the transactional email provider required for email verification and
  password reset.
- Define recent-reauthentication requirements for linking a new credential.
- Decide the web/mobile Google authorization flow, redirect origins, consent
  scopes, and retained claims/tokens.
- Define HookUs verification policy.
- Define which HookUs actions, if any, require phone control, selfie/liveness,
  age, or identity-document assertions.
- Decide whether verification assertions may be reused across brands, with what
  consent, expiry, and user-facing disclosure.
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

## Media And Verification Privacy

- Define original-media, generated-variant, rejected-media, and deleted-media
  retention and permanent purge timing.
- Approve whether users have a recovery window for deleted photos.
- Approve image-processing and moderation-provider disclosures.
- Define verification evidence minimization, storage region, retention, export,
  deletion, and legal-erasure behavior.
- Define manual verification review, support access, audit, and appeal rules.
- Decide which derived verification claims may be public and how they are worded.

# R2 Brand Buckets

All user-media buckets below must remain private: public access, public
development URLs, public custom domains, wildcard CORS origins, and generic
Active Storage routes stay disabled. Create bucket-scoped Object Read & Write
credentials; never expose credentials to a frontend. The backend selects the
bucket with `D8N_DEPLOYMENT_ENV` + `D8N_R2_BRANDS` and the matching
`D8N_R2_<BRAND>_<ENV>_*` secrets. `D8N_R2_ENDPOINT` remains the private S3 API
endpoint shared by services in the same Cloudflare account.

## HookUs staging

Bucket: `d8n-staging-media`

Brand/environment: HookUs / staging.

Founder action: Do not create a replacement. Reuse the existing private bucket
as the HookUs-only staging bucket and retain its current bucket-scoped credential.

Allowed origins:

- `http://localhost:3001`
- `http://127.0.0.1:3001`
- `http://192.168.0.109:3001`
- `https://hookus.app`
- `https://www.hookus.app`
- `https://hookus-web.hookus.workers.dev`

Methods: `PUT`, `GET`, `HEAD`.

Allowed headers: `Content-Type`, `Content-MD5`, `Content-Disposition`.

Exposed headers: `ETag`.

Then configure: retain legacy `D8N_R2_ACCESS_KEY_ID`,
`D8N_R2_SECRET_ACCESS_KEY`, and `D8N_R2_BUCKET`; map the same secret values to
`D8N_R2_HOOKUS_STAGING_ACCESS_KEY_ID`,
`D8N_R2_HOOKUS_STAGING_SECRET_ACCESS_KEY`, and
`D8N_R2_HOOKUS_STAGING_BUCKET=d8n-staging-media`. Keep `hookus` in
`D8N_R2_BRANDS` with `D8N_DEPLOYMENT_ENV=staging`.

Existing objects: no migration. Existing blob rows may retain service name `r2`;
new HookUs staging blobs use `r2_hookus_staging` against the same bucket.

Verification: perform presigned PUT → attach → signed/revocable GET → delete and
worker purge; confirm anonymous GET fails and both legacy and new-service blobs
remain retrievable/purgeable.

## HookUs production

Bucket: `d8n-hookus-prod`

Brand/environment: HookUs / production.

Founder action: Create a private Cloudflare R2 bucket and a bucket-scoped Object
Read & Write credential when production media is approved.

Allowed origins:

- `https://hookus.app`
- `https://www.hookus.app`
- `https://hookus-web.hookus.workers.dev`

Methods: `PUT`, `GET`, `HEAD`.

Allowed headers: `Content-Type`, `Content-MD5`, `Content-Disposition`.

Exposed headers: `ETag`.

Then configure: `D8N_R2_HOOKUS_PRODUCTION_ACCESS_KEY_ID`,
`D8N_R2_HOOKUS_PRODUCTION_SECRET_ACCESS_KEY`, and
`D8N_R2_HOOKUS_PRODUCTION_BUCKET=d8n-hookus-prod`; keep `hookus` in
`D8N_R2_BRANDS` with `D8N_DEPLOYMENT_ENV=production`.

Existing objects: none expected; no migration from staging.

Verification: perform presigned PUT → attach → signed/revocable GET → delete and
worker purge; confirm anonymous GET and every DateZA origin fail.

## DateZA staging

Bucket: `d8n-dateza-staging`

Brand/environment: DateZA / staging.

Founder action: Create a private Cloudflare R2 bucket and a bucket-scoped Object
Read & Write credential before the next staging deployment enables DateZA media.

Allowed origins:

- `http://localhost:5173`
- `https://dateza.vercel.app`

Methods: `PUT`, `GET`, `HEAD`.

Allowed headers: `Content-Type`, `Content-MD5`, `Content-Disposition`.

Exposed headers: `ETag`.

Then configure: `STAGING_DATEZA_R2_ACCESS_KEY_ID`,
`STAGING_DATEZA_R2_SECRET_ACCESS_KEY`, and
`STAGING_DATEZA_R2_BUCKET=d8n-dateza-staging` on the deploy host; Kamal maps them
to `D8N_R2_DATEZA_STAGING_ACCESS_KEY_ID`,
`D8N_R2_DATEZA_STAGING_SECRET_ACCESS_KEY`, and
`D8N_R2_DATEZA_STAGING_BUCKET`. Keep `dateza` in `D8N_R2_BRANDS` with
`D8N_DEPLOYMENT_ENV=staging`.

Existing objects: none expected; do not copy HookUs objects.

Verification: perform DateZA presigned PUT → attach → signed/revocable GET →
delete and worker purge; confirm anonymous GET and every HookUs origin fail.

## DateZA production

Bucket: `d8n-dateza-prod`

Brand/environment: DateZA / production.

Founder action: Create a private Cloudflare R2 bucket and a bucket-scoped Object
Read & Write credential when DateZA production media is approved.

Allowed origins:

- `http://localhost:5173`
- `https://dateza.vercel.app`

Methods: `PUT`, `GET`, `HEAD`.

Allowed headers: `Content-Type`, `Content-MD5`, `Content-Disposition`.

Exposed headers: `ETag`.

Then configure: `D8N_R2_DATEZA_PRODUCTION_ACCESS_KEY_ID`,
`D8N_R2_DATEZA_PRODUCTION_SECRET_ACCESS_KEY`, and
`D8N_R2_DATEZA_PRODUCTION_BUCKET=d8n-dateza-prod`; keep `dateza` in
`D8N_R2_BRANDS` with `D8N_DEPLOYMENT_ENV=production`.

Existing objects: none expected; no migration from staging.

Verification: perform DateZA presigned PUT → attach → signed/revocable GET →
delete and worker purge; confirm anonymous GET and every HookUs origin fail.

## Brand And Marketing

### DateZA staging API activation

- [x] Create DNS-only `dateza-staging-api.d8n.tech` A record pointing to the
  existing D8N staging server at `145.241.185.41`.
- [ ] Deploy the shared `d8n-staging` Kamal destination so Kamal Proxy serves
  both staging hosts and obtains/renews TLS for the DateZA hostname. Do not
  create another service or deployment.
- [ ] Run the idempotent `brands:install_dateza` task with
  `DATEZA_API_HOST=dateza-staging-api.d8n.tech`; this creates/updates DateZA and
  its active `BrandDomain` mapping without reassigning a conflicting hostname.
- [ ] Verify `/api/v1/auth/methods` reports `brand.slug=dateza` on the DateZA
  hostname and still reports `brand.slug=hookus` on `staging-api.d8n.tech`.
- [ ] Set DateZA's Vercel environment variable to
  `VITE_D8N_API_URL=https://dateza-staging-api.d8n.tech` and redeploy DateZA so
  the Vite build includes the new value.

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
