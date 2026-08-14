# D8N Infrastructure TODO — Master Checklist

## Phase 1 — Oracle: Our Temporary Base

### Protect Date9ja Production

* [ ] Leave Date9ja production running on Oracle for now
* [ ] Confirm current Date9ja containers/services
* [ ] Confirm current Date9ja PostgreSQL setup
* [ ] Configure external/off-server Date9ja backups
* [ ] Monitor Oracle CPU
* [ ] Monitor Oracle RAM
* [ ] Monitor disk usage
* [ ] Monitor disk I/O
* [ ] Monitor PostgreSQL connections
* [ ] Add sensible Docker resource limits
* [ ] Do **not** perform heavy D8N load testing here

### Create D8N Staging

* [ ] Create isolated D8N staging environment
* [ ] Create separate D8N staging database
* [ ] Create separate PostgreSQL user
* [ ] Create staging environment variables/secrets
* [ ] Create staging domain
* [ ] Configure HTTPS
* [ ] Deploy D8N staging
* [ ] Configure Rails/Puma
* [ ] Configure separate durable worker
* [ ] Configure Solid Queue properly
* [ ] Verify Rails restart
* [ ] Verify worker restart
* [ ] Verify jobs survive process restart
* [ ] Never copy real production user data into staging

---

# Phase 2 — D8N Build Hardening

Before we trust staging or production:

* [ ] Upgrade from EOL Ruby
* [ ] Upgrade vulnerable Rails/Active Storage version
* [ ] Patch vulnerable JSON dependency
* [ ] Add Linux platform support to `Gemfile.lock`
* [ ] Disable unused Rails Active Storage direct-upload routes
* [ ] Fix Brakeman CI behaviour
* [ ] Run complete Rails test suite
* [ ] Run RuboCop
* [ ] Run Brakeman
* [ ] Run Bundler Audit
* [ ] Run Zeitwerk check
* [ ] Verify OpenAPI tests
* [ ] Build production Docker image
* [ ] Add Docker image build to CI
* [ ] Ensure all quality gates are green

**Gate:** We don't call the build production-ready until these pass.

---

# Phase 3 — useSend + Transactional Email

### Oracle

* [ ] Deploy useSend
* [ ] Give useSend its own database
* [ ] Give useSend its own PostgreSQL user
* [ ] Configure Redis
* [ ] Isolate Redis keys/namespaces
* [ ] Configure resource limits

### AWS SES

* [ ] Set up AWS SES
* [ ] Configure sending domain
* [ ] Configure DNS authentication
* [ ] Configure SPF/DKIM/required records
* [ ] Configure SES production access if required
* [ ] Configure SNS/delivery-status plumbing where required
* [ ] Connect useSend → AWS SES

### D8N

* [ ] Connect D8N staging → useSend
* [ ] Test normal transactional email
* [ ] Test signup email
* [ ] Test identifier verification email
* [ ] Implement/test password-recovery email
* [ ] Test failed delivery behaviour
* [ ] Test retries
* [ ] Separate staging and production email credentials

---

# Phase 4 — Cloudflare R2 / D8N Media

### Storage

* [ ] Create D8N staging R2 bucket
* [ ] Create D8N production R2 bucket
* [ ] Keep buckets private
* [ ] Create separate staging credentials
* [ ] Create separate production credentials

### Media Safety

* [ ] Replace production local-disk storage
* [ ] Implement authorized photo access
* [ ] Implement short-lived/revocable delivery
* [ ] Validate actual image format
* [ ] Enforce file-size limits
* [ ] Enforce image-dimension limits
* [ ] Safely re-encode images
* [ ] Remove EXIF/location metadata
* [ ] Add moderation state
* [ ] Ensure only approved media becomes public
* [ ] Implement durable purge jobs
* [ ] Test corrupted images
* [ ] Test spoofed MIME types
* [ ] Test oversized images
* [ ] Test metadata-bearing images

**Rule:** D8N production user media never depends on local VPS disk.

---

# Phase 5 — Acquire D8N Production Infrastructure

## Hetzner Europe

* [ ] Create/configure Hetzner project
* [ ] Select European location
* [ ] Purchase first D8N production server
* [ ] Install/configure operating system
* [ ] Harden SSH
* [ ] Configure firewall
* [ ] Configure Docker
* [ ] Configure deployment user
* [ ] Configure secrets
* [ ] Configure production domains
* [ ] Configure Cloudflare
* [ ] Configure HTTPS/TLS

### Initial Production Stack

Start boring:

**Hetzner Production Server**

* Rails/Puma
* PostgreSQL
* Separate worker process
* Solid Queue
* Monitoring agent

External:

* Cloudflare
* Cloudflare R2
* useSend / SES
* Error tracking
* Off-server backups

We do **not** initially buy:

* Kubernetes
* Microservices
* Database cluster
* Read replicas
* Redis cluster
* Multiple Rails machines
* Dedicated load balancer
* Huge dedicated servers

Measurements decide when those appear.

---

# Phase 6 — Production Operations

* [ ] Configure production PostgreSQL
* [ ] Configure DB connection pool
* [ ] Configure Rails/Puma
* [ ] Configure separate worker process
* [ ] Configure Solid Queue
* [ ] Configure health checks
* [ ] Configure application monitoring
* [ ] Configure error tracking
* [ ] Configure request metrics
* [ ] Configure database metrics
* [ ] Configure worker/queue metrics
* [ ] Configure disk monitoring
* [ ] Configure CPU/RAM alerts
* [ ] Configure automated database backups
* [ ] Store backups outside production server
* [ ] Perform actual database restore test
* [ ] Document deployment procedure
* [ ] Test rollback
* [ ] Test migrations
* [ ] Test server restart
* [ ] Test worker restart

---

# Phase 7 — Production Load Testing

**All serious load testing happens on Hetzner — NOT the Oracle server hosting Date9ja.**

### Establish Baseline

* [ ] Seed representative users
* [ ] Seed representative profiles
* [ ] Seed preferences
* [ ] Seed likes/matches
* [ ] Seed realistic discovery data

### Test Critical Paths

* [ ] Registration
* [ ] Login
* [ ] Session authentication
* [ ] Profile retrieval
* [ ] Profile updates
* [ ] Discovery
* [ ] Like
* [ ] Pass
* [ ] Match creation
* [ ] Messaging when implemented
* [ ] Photo upload
* [ ] Background jobs

### Measure

* [ ] Request latency
* [ ] p50 latency
* [ ] p95 latency
* [ ] p99 latency
* [ ] Error rate
* [ ] CPU
* [ ] RAM
* [ ] PostgreSQL connections
* [ ] Slow queries
* [ ] Puma thread utilisation
* [ ] Worker queue depth
* [ ] Worker latency
* [ ] Network
* [ ] Disk I/O

### Increase Gradually

* [ ] ~50 concurrent
* [ ] ~100 concurrent
* [ ] ~250 concurrent
* [ ] ~500 concurrent
* [ ] ~1,000 concurrent

We stop increasing when the system tells us something needs attention.

We **do not assume** D8N handles 1,000 concurrent users simply because Rails starts successfully.

---

# Phase 8 — Performance Tuning

Only fix problems measurements reveal.

Possible future actions:

* [ ] Tune Puma
* [ ] Tune PostgreSQL pool
* [ ] Add missing indexes
* [ ] Optimize discovery SQL
* [ ] Reduce session write amplification
* [ ] Tune workers
* [ ] Add PgBouncer if DB connections justify it
* [ ] Move PostgreSQL to separate server if justified
* [ ] Add second Rails node if justified
* [ ] Add load balancer if multiple app nodes exist
* [ ] Add dedicated worker machine if queues justify it

**No speculative scaling.**

---

# Phase 9 — Failure Testing

Before inviting significant numbers of users:

* [ ] Kill Rails and confirm recovery
* [ ] Kill worker and confirm recovery
* [ ] Restart server
* [ ] Restart PostgreSQL
* [ ] Simulate failed background job
* [ ] Simulate email provider failure
* [ ] Simulate R2/storage failure
* [ ] Test retry behaviour
* [ ] Test deployment rollback
* [ ] Test failed migration procedure
* [ ] Restore production-like DB from backup
* [ ] Confirm monitoring catches failures

---

# Phase 10 — HookUs Production Readiness

Before opening HookUs:

* [ ] Infrastructure green
* [ ] Security findings resolved
* [ ] Production media ready
* [ ] Email ready
* [ ] Password recovery ready
* [ ] Background workers durable
* [ ] Backups tested
* [ ] Monitoring working
* [ ] Error tracking working
* [ ] Basic moderation/reporting available
* [ ] Complete dating loop working
* [ ] Production load test completed
* [ ] Critical bottlenecks fixed
* [ ] Deployment tested
* [ ] Rollback tested

Then:

**HOOKUS PRIVATE BETA 🚀**

---

# Phase 11 — Date9ja Migration — LATER

Do not do this yet.

* [ ] Keep current Date9ja operating on Oracle
* [ ] Let HookUs prove D8N production architecture
* [ ] Collect real infrastructure metrics
* [ ] Learn actual CPU requirements
* [ ] Learn actual PostgreSQL requirements
* [ ] Learn actual worker requirements
* [ ] Learn actual storage requirements
* [ ] Design Date9ja migration
* [ ] Dry-run migration
* [ ] Validate user/account mapping
* [ ] Validate brand membership/profile mapping
* [ ] Migrate Date9ja into D8N
* [ ] Retire legacy Date9ja backend when safe

---

# Our Infrastructure Rule

**Build for the users we are about to have while leaving a clean path to the users we hope to have.**

Oracle is our temporary staging/dev utility server.

Hetzner Europe becomes our production proving ground.

HookUs proves D8N.

Date9ja migrates later.

Cloudflare/R2 handles the edge and media.

useSend + SES handles transactional email.

PostgreSQL remains the source of truth.

Rails remains a modular monolith.

We scale when measurements tell us to — not because an architecture diagram looks impressive.
