D8N Founder State

Operational handoff / source of current truth
Updated: 14 August 2026 (reconciliation appended 17 August 2026)

Update 2026-08-17 — product/loop reconciliation

Primary milestone is now stated as HookUs Beta Ready. The single one-screen
NOW/NEXT/LATER view is docs/FOUNDER-HQ/D8N_NOW_NEXT_LATER.md; read it first.

Shipped and verified against code/tests since this file was written:
- R2 A-F private-media lifecycle PROVEN on live staging (2026-08-15); the old
  "immediate next action" in section 16 is DONE.
- Safe media processing + stranger-safe display delivery (EXIF/GPS strip,
  re-encode, purge raw) implemented; needs deploy + staging + frontend browser E2E.
- Discovery modes/facets (for_you default, new_here, vibe, online) shipped.
- Trust: blocking, unblocking, blocked-user list (b02f4f4), and profile reporting
  shipped with cross-surface enforcement; all local gates green.
- DL-03 persisted text messaging (2026-08-17, uncommitted): the core loop now
  closes end-to-end. `Message` model + `GET/POST /api/v1/conversations/:id/messages`,
  cursor history, last-message preview on the conversation list, and block/suspend/
  brand enforcement reusing MatchAccess. IMPLEMENTED + TESTED (18 request tests, all
  gates green); NOT yet staging-proven — DL-04 staging two-user run is the remainder.

- TS-03 admin moderation review queue (2026-08-17, uncommitted): moderators can
  list/inspect/decide reports. Admin auth REUSES the existing session — new
  `admin_users.user_id` link + active AdminAssignment for the host brand (no new
  auth system); 401 unauth / 403 non-moderator; brand isolation inherent. Audited
  lifecycle via SecurityEvent; decision provenance on the report. IMPLEMENTED +
  TESTED (17 request tests); NOT staging-proven. **Admin MFA is still a pre-launch
  gate** (admins can read report content). The admin-auth model likely warrants an
  ADR — founder to confirm.

- TS-04 brand-level suspend/ban enforcement (2026-08-17, uncommitted): `POST/DELETE
  /api/v1/admin/profiles/:profile_id/suspension`. Suspends the BrandMembership +
  revokes the user's brand sessions + durable `AccountEnforcement` + audit, atomic;
  enforced across all surfaces; reinstatement restores only membership. Report state
  stays separate. Reuses TS-03 admin auth. Platform-wide ban deferred (no global
  admin authority). ADR 0013 records the admin-identity + enforcement architecture.
  IMPLEMENTED + TESTED (16 request tests); NOT staging-proven.

- TS-06 brand-level account closure + media purge (2026-08-17, uncommitted):
  `DELETE /api/v1/me` (needs `confirmation:"close"`). Atomic membership tombstone +
  profile discard/anonymize + matches ended + likes/passes discarded + locations
  hard-deleted + brand sessions revoked + `AccountClosure` record + audit, then async
  `Media::PurgeProfileMediaJob` physically purges R2 media (tracked outcome).
  Retained: User/credentials/identifiers (cross-brand), conversations, messages,
  blocks, reports, enforcements, audit. Platform-wide identity deletion deferred
  (policy). ADR 0014 + docs/operations/data-retention.md. IMPLEMENTED + TESTED (18
  tests); NOT staging-proven.

Confirmed remaining P0 gaps to complete + responsibly operate the loop (verified):
- ~~ID-04 signed-out password recovery~~ BUILT 2026-08-17 (IMPLEMENTED + TESTED, 18
  tests; awaiting founder commit + staging QA). Three-step verified-identifier flow,
  enumeration-resistant, cross-brand session revocation, membership-state-preserving;
  reuses `OtpChallenge`/throttle/adapters; production delivery gated on the provider.
- ID-02 registration throttling (last P0 code).

Production hosting remains deliberately sequenced AFTER the product loop; staging
is the current proving ground.

Purpose: A short, portable state file for a fresh founder/AI session.
Read this before relying on old chat history. This file records
current state, priorities, boundaries, pending decisions, and the next
concrete actions. It must never contain live secrets.

1. Current objective

Build D8N into the shared, production-ready platform for the dating
portfolio, while keeping Date9ja stable and using HookUs as the first
brand to prove the new D8N production architecture.

Immediate infrastructure objective: the Cloudflare R2 wiring is now
deployed to a healthy D8N staging environment. The remaining private-media
staging gate is verifying the real upload -> authorized retrieval -> purge
lifecycle against the live bucket before any production R2 resource exists.

2. Current project priority

Active

D8N platform/infrastructure - production-readiness work.

Date9ja - live product; growth, users, support, bugs, and
necessary production maintenance.

Next / proving ground

HookUs - first brand intended to prove the D8N production
architecture. Frontend product-hardening is underway.

Controlled / incubating

Weloid

Weloid AI

Other ideas should be documented without displacing the active
critical path unless the founder explicitly reprioritizes them.

3. D8N staging - established state

Public staging API hostname: staging-api.d8n.tech

Staging server IP recorded in the asset register: 145.241.185.41

Deployment: Kamal + Docker

Application: Rails/Puma

Jobs: separate durable worker / Solid Queue

Database: PostgreSQL 17 accessory

Latest staging deploy: healthy. The Rails/Puma web role, the separate
Solid Queue worker role, and the PostgreSQL 17 accessory are all up, and
the API health check returns HTTP 200 at https://staging-api.d8n.tech.
The Cloudflare R2 staging configuration is deployed (see section 4).

A prior deploy failed because an env.secret list overrode
RAILS_MASTER_KEY and D8N_DATABASE_PASSWORD; that bug was found and fixed,
and regression coverage now proves staging preserves both the base app
secrets and the R2 secrets together.

The HookUs frontend can now use staging-api.d8n.tech as the backend
source of truth (see section 9).

Staging has already been seeded/tested and its current performance
boundaries are understood.

Prior load testing included 3,000 synthetic users. The 25-VU target
passed the defined latency/error thresholds; 50 and 100 VUs remained
error-free but exceeded the latency thresholds.

Do not continue heavy load testing on infrastructure shared with
the existing Date9ja environment. Serious production-scale load
testing belongs on dedicated D8N production infrastructure.

Do not use real Date9ja production user data in staging.

4. Cloudflare R2 - current state

Done

D8N-owned Cloudflare account established.

R2 activated.

Private staging bucket created: d8n-staging-media.

Public bucket access remains disabled.

Bucket-scoped service credential created for read/write/list access.

An initially exposed R2 credential was revoked and rotated. Only the
replacement credential is valid.

Local/deployment secret names established:

STAGING_R2_ACCESS_KEY_ID

STAGING_R2_SECRET_ACCESS_KEY

STAGING_R2_ENDPOINT

STAGING_R2_BUCKET

Rails/Kamal staging R2 wiring completed:

.kamal/secrets.staging maps staging secret names to runtime
D8N_R2_* names without literal values.

config/deploy.staging.yml enables R2 for staging and declares
the four runtime secrets.

test/config/kamal_staging_r2_configuration_test.rb added.

docs/operations/private-media-storage.md updated with staging
wiring and A-F verification procedure.

Engineering verification completed (re-run 14 Aug 2026)

Rails test suite: 310 runs, 1,626 assertions, 0 failures

RuboCop: 245 files, 0 offenses

Zeitwerk: clean

Brakeman: 0 warnings

bundle-audit: 0 vulnerabilities

git diff --check: clean

R2 lifecycle gate - PROVEN 2026-08-15

The genuine Active Storage A-F lifecycle (upload -> object present ->
public access blocked -> authorized read-back -> purge -> object gone) ran
green against live d8n-staging-media. The drill caught a real defect: every
upload was failing with "InvalidRequest: You can only specify one
non-default checksum at a time" because a newer aws-sdk-s3 adds a CRC32
checksum on top of Active Storage's Content-MD5 and R2 rejects two
checksums. The boots-with-R2 deploy never actually wrote an object. Fix:
config/storage.yml now sets request_checksum_calculation and
response_checksum_validation to when_required (scoped to the R2 service).
Proven against the live bucket with the deployed SDK.

Direct-to-R2 profile-photo API implemented (control plane / data plane):
authenticated upload intent -> short-lived presigned PUT -> client uploads
bytes straight to private R2 -> D8N verifies the real object and attaches
it to the owner's profile -> short-lived signed retrieval. R2 credentials
never reach the client; D8N allocates the object key. Owner-only photos
begin pending_review; HookUs makes them visible immediately (per-brand
policy), other brands stay hidden. Public delivery, re-encode, EXIF removal,
and moderation enforcement remain gated (ADR 0011). Full local gates green.

Profile-photo backend HTTP E2E - PROVEN 2026-08-15 against deployed rev
a9e09fcede2d867099769a8bd55a4437394fd80e. Full lifecycle exercised over
HTTP against the real R2 staging bucket with a disposable hookus user:
intent -> short-lived presigned PUT -> direct PUT of a real PNG to private
R2 (200) -> attach bound to the authenticated hookus profile
(pending_review/hidden) -> short-lived signed GET returned the exact bytes
-> anonymous object access blocked (400) -> API list showed the photo ->
delete (200, soft-deleted, delisted) -> worker purge removed the backing R2
object (head 404). Negatives held: unauth intent 401, reused upload 422,
non-image 422, no credential exposed. Staging returned to baseline (0
photos, 0 blobs, empty bucket). No defect in the deployed build; no
redeploy needed.

Two backend policy changes landed 2026-08-15 (not yet deployed; needs
founder commit + redeploy):

- HookUs photo visibility policy. Normal HookUs profile photos are now
  `visible` immediately after attach (still `pending_review`, moderated
  asynchronously) instead of waiting hidden for manual approval. This is a
  per-brand policy (Media::PhotoPolicy): any brand without an explicit
  policy stays hidden/moderate-first (the safe default and the DB column
  default), so Date9ja and future brands are unaffected and moderation
  capability is fully preserved.
- Human-organized R2 object keys. D8N now allocates keys under
  `brands/{slug}/users/{id}/profiles/{uuid}/photos/{uuid}/original.{ext}`
  (Media::ObjectKey) so the Cloudflare dashboard groups objects into
  readable, brand-scoped folders. Keys are server-controlled, PII-free
  (only brand slug + internal user id + profile UUID + per-object UUID),
  unique, and applied to new objects only (no migration). API capability
  docs (root status, OpenAPI, docs/api/README) were corrected to report the
  owner-scoped photo API as live (preview) rather than disabled.

Remaining media proof: HookUs browser/product E2E (frontend integration).
This backend agent cannot drive a real browser; the definitive
browser->intent->PUT->attach->display->delete->purge run must be executed by
the HookUs frontend after the founder's R2 CORS update. Backend contract is
ready and unchanged by the above (response shapes identical).
Still gated (separate tickets): moderation enforcement, video. Do not create
production R2 resources until the HookUs product loop and the remaining ADR 0011
media gates are addressed.

Safe public photo delivery landed 2026-08-15 (not yet deployed; needs founder
commit + redeploy + staging verification). Other eligible users can now see
profile photos in discovery/match/conversation surfaces, but never the raw
upload. After attach, Media::ProcessProfilePhotoJob (libvips/ruby-vips) decodes
the raw original, re-encodes a D8N-owned JPEG display derivative, strips
EXIF/GPS/all metadata, stores it privately beside the original
(`.../photos/{uuid}/display.jpg`), marks processing_state=ready, and purges the
raw. A new processing_state (pending/processing/ready/failed) is separate from
moderation status and visibility; delivery fails closed (only visible AND ready
photos are exposed, via short-lived signed URLs to the derivative). This closes
the EXIF/GPS privacy gate that blocked showing photos to strangers. Requires
libvips in the image (already in the Dockerfile). Remaining media gate:
moderation enforcement (flag/hide acts on the same states). Owner upload/delete
API and response shapes are backward compatible (only added processing_state).

5. AWS / Amazon SES - current state

D8N controlling infrastructure email: d8ncorp@gmail.com

D8N AWS account established.

SES region used: us-east-1 / US East (N. Virginia).

AWS zero-spend budget created: D8N Zero-Spend Budget, alerting
above $0.01.

SES pricing choice: A la carte.

SES domain identity d8n.tech: Verified.

SES email identity d8ncorp@gmail.com: Verified.

Custom MAIL FROM: mail.d8n.tech.

Required SES DKIM / MAIL FROM / SPF / DMARC DNS records were added
through GoDaddy.

SES optional paid enhancements were intentionally left disabled
during setup: Virtual Deliverability Manager, Auto Validation,
Dedicated IPs, Tenant Management.

SES production-access request was submitted on 14 Aug 2026.

At submission time the account remained in SES sandbox (200
emails/24h, 1 email/sec).

Waiting externally: AWS production-access decision.

6. useSend - current state

useSend is being evaluated as the transactional email management/API
layer on top of the D8N email infrastructure.

Access/waitlist request submitted using d8ncorp@gmail.com.

Intended use: transactional email.

Waiting externally: useSend access.

Open architecture decision: useSend Cloud convenience layer vs Rails
sending directly through D8N-owned Amazon SES.

Multi-brand requirement remains: Date9ja, HookUs, and future brands
must send from their own branded identities/domains.

7. Domains / ownership

d8n.tech - D8N company/technical website; GitHub Pages; DNS
currently at GoDaddy.

da8n.com - owned; intended global-facing/non-localized dating
brand/domain.

staging-api.d8n.tech - D8N staging API.

Do not move DNS providers casually while SES, GitHub Pages, and
staging records are active.

8. Date9ja boundary

Date9ja is live and has real users. It remains on its existing
production infrastructure for now.

Current policy: - protect/stabilize it; - keep off-server backups and
monitoring as priorities; - avoid disruptive infrastructure experiments
on it; - do not migrate Date9ja to D8N merely because D8N exists; -
prove the D8N production architecture with HookUs first, then plan
Date9ja migration separately.

9. HookUs frontend state

The frontend engineer is now wiring HookUs against the real staging API
(staging-api.d8n.tech) as the backend source of truth. The frontend local
dev server runs at http://localhost:3001. The staging backend explicitly
allows that origin (and its 127.0.0.1 loopback form) for CORS via the
D8N_CORS_ORIGINS env in config/deploy.staging.yml; no wildcard origin is
used. D8N now supports an opt-in, host-only HttpOnly browser session over the
same brand-bound server session, while bearer auth remains supported. Exact
allowed origins use credentialed CORS and cookie-authenticated mutations require
a session-bound CSRF token. This takes effect on staging only
after the next staging deploy.

A frontend audit/fix pass is underway.

Recent completed product-hardening included removing fabricated
likes-received data and dead/fake Plus behavior, and improving honesty
around unavailable/mock product surfaces. A previous frontend Claude
session produced an authoritative ranked TODO.md plus a
docs/PROJECT_MEMORY.md handoff and was then retired because its
context had grown very large.

A fresh Claude Sonnet frontend session has been started using the
handoff. New frontend work should: - verify the handoff against the
working tree; - preserve existing uncommitted work; - avoid presenting
mock/fabricated data as real; - avoid inventing APIs, billing,
verification guarantees, or backend capabilities; - run
typecheck/lint/build and appropriate tests before declaring work
complete; - remain task-scoped and hand off before context becomes
bloated.

Known frontend engineering gap from the handoff: no meaningful automated
frontend test suite yet. Add focused tests as critical flows are touched
rather than creating a giant testing project detached from product work.

10. AI engineering operating model

Primary roles

Codex Sol - primary backend / Rails / infrastructure engineer
when available.

Claude Sonnet - primary frontend engineer;
secondary/full-stack/backend fallback.

Fable 5 - design/visual exploration.

ChatGPT / Chief - founder desk, architecture, prioritization,
cross-project state, review coordination.

Founder - product direction, users, business priorities, money,
final decisions.

Current Codex constraint

Codex/Work Plus weekly usage is exhausted and is scheduled to reset 20
Aug 2026 at 05:35. Do not halt the company waiting for Codex.

Session hygiene rules

One coherent ticket/workstream per agent session.

Project context is good; giant accumulated conversation context is
not.

Agents read CLAUDE.md, relevant state/handoff/TODO docs, affected
code, and necessary adjacent architecture - not the entire
repository by default.

Use /compact during a genuinely continuous long task.

Start a fresh session when materially switching tasks.

Require a concise handoff before retiring a substantial session.

Separate implementer and reviewer where practical.

Tests/CI are mandatory mechanical gates; an agent saying its own
work is correct is not sufficient.

Parallel agents working in the same repository should use isolated
Git worktrees/branches when they could collide.

Do not burn premium model capacity on routine work when a
cheaper/efficient model is adequate.

11. Founder operating principle

Parallel thinking is allowed; uncontrolled parallel building is not.

Use three states: - ACTIVE - at most two major execution tracks. -
MAINTENANCE - live products receiving support, bugs, and small
necessary improvements. - INCUBATOR - ideas/specs preserved without
stealing the current critical path.

Before significant implementation ask: What product or business
milestone does this unlock?

12. Cost discipline

D8N is bootstrapped. New SaaS/tooling spend should be classified: -
Free - use where appropriate. - Cheap - buy when it removes real
work or risk. - Expensive - prove ROI/throughput benefit first.

Do not enable automatic paid usage/reloads casually. Record recurring
engineering, infrastructure, analytics, email, monitoring, and AI-tool
costs in the company asset/cost register.

13. Planned / outstanding infrastructure

Still to establish, verify, or finalize as appropriate: - Dedicated D8N
production hosting (Hetzner Europe is the current direction). -
Production architecture proven first with HookUs. - Off-server database
backups plus a tested restore procedure. - PostHog for product
analytics. - New Relic or final APM choice. - Error tracking
provider/project. - Founder/Admin control room linking/surfacing
operational tools such as PostHog, APM, email and infrastructure. -
Production R2 bucket/credentials only after staging R2 verification. -
Final transactional email path after SES approval/useSend evaluation. -
Human/company mailbox provider (Zoho was considered; final decision
should be recorded when made). - Password manager/company secrets vault
and recovery procedure if not already finalized.

Avoid premature Kubernetes, microservices, DB clusters/read replicas,
Redis clusters, multiple Rails machines, dedicated load balancers, or
oversized servers without measured need.

14. Secrets policy

Never put live secrets in this file, Notion, Git, screenshots, or
chat.

This file may record: - secret/environment variable names; - which
provider/account owns them; - where they are stored/retrieved.

It must not record: - passwords; - secret access keys; - API tokens; -
private keys; - recovery codes; - MFA seeds; - full payment-card
information.

If a secret is accidentally exposed, revoke/rotate it immediately and
record only that rotation occurred.

15. Source-of-truth hierarchy

When sources disagree, prefer:

Current repository/code/config and verified infrastructure state.

Current FOUNDER_STATE.md / project handoff documentation.

Asset/infrastructure register and ADR/operations docs.

AI memory/chat history.

Old chat history is context, not authority.

16. Immediate next action

Do not restart planning from zero.

The immediate D8N infrastructure action is:

[DONE 2026-08-15] The A-F private-media verification against the healthy R2
staging release was executed and passed (see section 4, "R2 lifecycle gate -
PROVEN 2026-08-15"). Do not re-run as a blocker.

The current primary action is the product loop, not infrastructure. DL-03
(messaging), TS-03 (moderation review), TS-04 (brand-level suspend/ban), TS-06
(account closure + media purge), and ID-04 (signed-out password recovery) are now
built (uncommitted, awaiting founder commit + staging QA). Per
docs/FOUNDER-HQ/D8N_NOW_NEXT_LATER.md the last P0 code is now ID-02 (registration
throttling); then the DR/DL staging proofs and go/no-go. Admin MFA, platform-wide identity deletion, and a platform-wide-ban
authority are separate gates. Production R2 resources are still not to be created
until the HookUs product loop and remaining ADR 0011 media gates are addressed.

In parallel, the HookUs frontend engineer continues wiring HookUs against
staging-api.d8n.tech (CORS for http://localhost:3001 is configured and
takes effect on the next staging deploy).

17. How to use this file in a fresh ChatGPT conversation

Attach or make this file available and say:

Chief, reporting for duty. Read D8N_FOUNDER_STATE.md as the current
operational state. Tell me where we are, what is waiting externally,
and the next three actions. Do not reconstruct state from assumptions
or restart completed work.

A fresh session should be able to resume from this file without needing
the long historical conversation.
