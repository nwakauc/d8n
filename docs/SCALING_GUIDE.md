# D8N Scaling Guide

## Purpose

This document gives a practical scaling roadmap for D8N infrastructure, cost control, security, and operational readiness.

Numbers are planning estimates, not capacity guarantees. Actual needs depend on daily active users, message volume, media volume, geography, verification usage, and product behavior.

## Scaling Principles

- Start simple.
- Measure before scaling.
- Scale bottlenecks, not diagrams.
- Keep the Rails API stateless.
- Put slow work in background jobs.
- Use PostgreSQL well before adding exotic infrastructure.
- Use Redis carefully for cache, jobs, rate limiting, and realtime support.
- Store media in object storage, not on app servers.
- Keep tenant isolation test-covered at every scale.
- Do not extract services until operational pressure proves the need.

## Main Load Drivers

D8N's biggest load drivers will likely be:

- Signup/login OTP traffic
- Discovery feed reads
- Like/pass writes
- Match creation
- Messaging
- Push notifications
- Photo/video upload and processing
- Verification checks
- Moderation queues
- Analytics events

Dating apps can become write-heavy because likes, messages, notifications, and analytics events happen constantly.

## Planning Assumptions

Use these for early planning:

```txt
Registered users are not the same as active users.
Daily active users matter more than total signups.
Messaging and media drive cost faster than profile reads.
SMS OTP can become expensive quickly.
Verification can become very expensive if required too early.
```

## Infrastructure Bands

### Private Beta / First 5k Users

Target:

- Validate product
- Validate auth
- Validate matching
- Validate safety workflows

Suggested infrastructure:

- 1 Rails API web instance
- 1 Rails worker instance
- Managed PostgreSQL small instance
- Solid Queue on the PostgreSQL instance, using its own queue database
- Cloudflare R2 for media
- Cloudflare CDN/WAF
- Error tracking
- Basic uptime monitoring

Priorities:

- Correctness
- Security
- Tenant isolation
- Observability
- Backup/restore testing

Do not optimize heavily yet.

### 50k Registered Users

Likely shape:

- 2 Rails API web instances
- 1 to 2 worker instances
- Managed PostgreSQL with enough memory for indexes
- Managed Redis
- R2/CDN for media
- Background jobs separated by queue priority

Important tuning:

- Add database indexes based on real query plans
- Add rate limits for auth, messaging, and discovery
- Add pagination everywhere
- Cache brand configuration
- Cache lightweight profile cards where safe
- Move media processing fully async
- Batch analytics writes where possible
- Monitor slow queries
- Monitor job retries/dead jobs

Security:

- Admin MFA required
- Webhook signature verification
- Audit logs reviewed periodically
- Backups tested
- Secrets managed outside the repo

### 100k Registered Users

Likely shape:

- 2 to 4 Rails API web instances
- 2 to 4 worker instances
- Larger managed PostgreSQL
- Managed Redis with eviction policy reviewed
- Dedicated queues for media, notifications, payments, verification, analytics
- Optional read replica if read pressure is high

Important tuning:

- Tune database connection pool
- Add query timeouts
- Add request timeouts
- Use read replica only for safe read paths
- Avoid expensive cross-brand admin queries
- Precompute discovery candidates where needed
- Add denormalized counters carefully
- Add idempotency keys for critical writes
- Add CDN caching for public/static assets

Cost controls:

- Avoid sending SMS when email/push is enough
- Use phone OTP only where brand policy requires it
- Delay expensive ID verification until needed
- Use image compression and thumbnail variants
- Set retention rules for old media variants
- Batch non-critical emails/notifications

### 1m Registered Users

Likely shape:

- 4 to 12 Rails API web instances depending on active usage
- 4 to 12 worker instances depending on messaging/media/notification volume
- PostgreSQL primary with tuned memory, storage, and indexes
- Read replicas for heavy read paths
- Redis sized for jobs, cache, rate limits, and realtime support
- Dedicated realtime layer if chat/presence becomes heavy
- Dedicated analytics pipeline if event volume grows

Important tuning:

- Partition or archive high-volume tables if needed
- Add database read replicas for discovery/admin/reporting paths
- Move analytics out of the primary request path
- Separate queues by latency requirement
- Consider dedicated messaging/realtime infrastructure
- Consider extracting media processing if it becomes operationally independent
- Consider service extraction only for proven hotspots

Potential extraction candidates:

- Chat/realtime
- Media processing
- Notifications
- Analytics/events
- Verification provider orchestration

Do not extract billing or trust too early. They are correctness-heavy domains where consistency matters.

## Database Scaling

PostgreSQL should carry D8N for a long time if used well.

Required practices:

- Proper indexes
- Foreign keys
- Partial indexes for soft-deleted uniqueness
- Query plan review
- Avoid N+1 queries
- Use pagination
- Avoid unbounded admin exports
- Archive old analytics where needed
- Keep large JSON blobs out of hot paths
- Use background jobs for heavy writes

High-volume tables to watch:

- `messages`
- `analytics_events`
- `notifications`
- `likes`
- `passes`
- `media_assets`
- `auth_attempts`
- `security_events`

## Redis Usage

Use Redis for:

- Job backend if selected
- Cache
- Rate limiting
- Short-lived auth/OTP state if appropriate
- Realtime/presence support if needed

Do not use Redis as the source of truth for:

- Payments
- Entitlements
- Verification state
- Moderation actions
- User identity
- Brand ownership

## Media Scaling

Media can become expensive quickly.

Best practices:

- Store originals in R2/object storage
- Generate only needed variants
- Strip metadata
- Compress images
- Use signed URLs where appropriate
- Use CDN caching
- Process media asynchronously
- Moderate media before broad exposure where policy requires it
- Delete unused variants on retention schedule

## Messaging Scaling

Start simple.

Options:

- Polling for first beta
- Server-sent events or WebSockets when needed
- Dedicated realtime layer when chat volume proves it

Rules:

- Messages are stored in PostgreSQL.
- Realtime delivery is a delivery mechanism, not the source of truth.
- Blocking/reporting must be enforced server-side.
- Message visibility must remain brand-scoped.

## Auth And OTP Scaling

SMS is both a security and cost area.

Required controls:

- Per-phone rate limits
- Per-IP rate limits
- Attempt lockouts
- Generic errors
- OTP expiry
- Single-use OTPs
- Device tracking
- Step-up verification for sensitive actions

Cost controls:

- Prefer push/email for non-login notifications
- Do not resend OTPs aggressively
- Use cooldown windows
- Track SMS spend by brand and country
- Add fraud detection for OTP abuse

## Email Strategy

Start with a reliable provider.

Later, D8N can consider self-hosting or semi-self-hosting transactional email using a tool like UseSend if it reduces cost and operational risk is acceptable.

Do not self-host email too early.

Before moving email in-house, D8N needs:

- Deliverability expertise
- Bounce handling
- Complaint handling
- Suppression lists
- DKIM/SPF/DMARC
- IP/domain warming
- Monitoring
- Provider fallback

Email cost savings are only worth it if deliverability does not suffer.

## Verification Cost Controls

Verification can become one of the largest variable costs.

Controls:

- Require expensive verification only when needed
- Use progressive verification levels
- Reuse platform verification where privacy policy allows
- Charge for high-cost verification where appropriate
- Track provider cost per brand
- Track failed verification cost
- Use risk-based checks where policy allows

## Payment Scaling

Rules:

- Provider webhooks must be idempotent
- Store provider event IDs
- Never trust client payment status
- Entitlements must be derived from server-confirmed payment state
- Keep end-user billing separate from operator billing
- Monitor failed webhooks

## Observability By Stage

Minimum:

- Error tracking
- Uptime checks
- Structured logs
- Job failure monitoring
- Database slow query logs

At 50k+:

- Dashboard for request latency
- Dashboard for job latency
- Dashboard for SMS/email/payment failures
- Dashboard for signups, matches, messages, reports
- Alerting for error spikes

At 100k+:

- SLOs for API, auth, messaging, payments
- Queue-specific alerts
- Database saturation alerts
- Redis memory/latency alerts
- Provider incident playbooks

At 1m+:

- Capacity planning cadence
- Cost dashboards by brand
- Regional performance monitoring
- Incident review process
- Dedicated security monitoring

## Security At Scale

More users means more abuse.

Scale security before marketing spend.

Required:

- Rate limits
- Bot detection
- Admin MFA
- Audit logs
- Moderation tools
- Report queues
- Abuse escalation
- Payment fraud monitoring
- OTP abuse monitoring
- Media moderation
- Account recovery controls

## Cost Controls

Cost areas to watch:

- SMS OTP
- Push/email volume
- Verification checks
- Media storage
- Media bandwidth
- Realtime infrastructure
- Database size
- Analytics volume
- Payment disputes

Cost-saving practices:

- Keep images optimized
- Use CDN aggressively for media
- Avoid unnecessary SMS
- Use progressive verification
- Archive analytics
- Batch background work
- Delete unused media variants
- Track cost per brand
- Track cost per active user
- Track cost per successful match/conversation

## When To Extract Services

Extract only when one domain has a separate scaling, reliability, or team ownership profile.

Good reasons:

- Chat needs a dedicated realtime architecture
- Media processing saturates workers
- Analytics volume hurts product database performance
- Notifications need provider routing at large volume

Bad reasons:

- The diagram looks more impressive
- A reviewer prefers microservices by default
- The team wants to copy Big Tech architecture early

## CTO Review Questions

- What are expected daily active users for HookUs beta?
- What is expected messages/user/day?
- What is expected photos/user?
- What is expected OTP attempts/signup?
- What markets launch first?
- What are SMS costs in launch markets?
- What provider limits apply?
- What is the backup/restore target?
- What uptime is required for beta?
- What moderation staffing exists at launch?
