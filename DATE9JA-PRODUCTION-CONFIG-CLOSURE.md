# Changes Made

- Added `api.date9ja.love` to the production Kamal proxy and explicit Rails Host allowlist.
- Added `DATE9JA_API_HOST` production provisioning input; the existing idempotent `brands:ensure_date9ja` task now maps the canonical host at web boot.
- Added `https://www.date9ja.love` to explicit credentialed CORS configuration.
- Added private `r2_date9ja_production` Active Storage service and production R2 secret wiring.
- Added Date9ja Resend sender and application/deep-link URL configuration.
- Replaced the production `example.com` mailer host fallback with an explicit platform mailer host setting.
- Removed the generic `from@example.com` mailer fallback; every D8N transactional mailer supplies its brand sender explicitly.
- Removed Date9ja `notify.sms` capability and disabled new Date9ja phone/password registration while retaining migrated phone/password login.
- Added capability guards in registration, verification-request, recovery-request, and login response projection so a disabled phone-verification capability cannot create an OTP, enqueue SMS, or advertise a phone-verification step.
- Added a fail-fast production validator for Date9ja topology, CORS, R2, Resend, encryption, and primary/queue database configuration. Errors contain variable/service names only, never values.

# Files Changed

- `config/deploy.production.yml`
- `config/storage.yml`
- `config/environments/production.rb`
- `config/initializers/date9ja_production_configuration.rb`
- `lib/d8n/date9ja_production_configuration.rb`
- `app/controllers/api/v1/auth/passwords_controller.rb`
- `domains/d8n/platform/brands/date9ja.rb`
- `domains/identity/password_registration.rb`
- `domains/identity/verification_requester.rb`
- `domains/identity/recovery_requester.rb`
- `docs/operations/date9ja-production-configuration.md`
- `docs/operations/private-media-storage.md`
- configuration, tenant, storage, email, recovery, and Date9ja SMS policy tests under `test/`

The pre-existing `DATE9JA-BACKEND-PRODUCTION-READINESS.md` audit artifact was not modified.

# Date9ja Production Environment Variables

Exact committed topology values and secret names are documented in
[`docs/operations/date9ja-production-configuration.md`](docs/operations/date9ja-production-configuration.md).

Date9ja-specific values/names are:

```text
DATE9JA_API_HOST=api.date9ja.love
D8N_DATE9JA_APP_URL=https://www.date9ja.love
D8N_DATE9JA_EMAIL_FROM=<Resend-verified Date9ja sender>
D8N_R2_DATE9JA_PRODUCTION_ACCESS_KEY_ID=<secret>
D8N_R2_DATE9JA_PRODUCTION_SECRET_ACCESS_KEY=<secret>
D8N_R2_DATE9JA_PRODUCTION_BUCKET=<private bucket>
```

The shared required values are `D8N_R2_ENDPOINT`, `RESEND_API_KEY`, the three
`D8N_AR_ENCRYPTION_*` keys, database variables, `D8N_ALLOWED_HOSTS`,
`D8N_CORS_ORIGINS`, `D8N_DEFAULT_MAILER_HOST`, `D8N_R2_ENABLED=true`,
`D8N_DEPLOYMENT_ENV=production`, and `D8N_R2_BRANDS` containing `date9ja`.
`RAILS_MASTER_KEY` remains a Kamal secret consumed by Rails.

# Phone/SMS Decision

Date9ja does not require phone/SMS verification at launch. Its contract has no
`verify.contact.phone` or `notify.sms`. New phone/password registration returns
`auth_method_unavailable` before creating a user, OTP challenge, notification
delivery, or job. Migrated phone/password credentials can still log in. Phone
verification and phone password recovery are capability-blocked, so a global
Twilio fallback cannot create Date9ja spend. Email confirmation uses Resend and
is independent of RealMe.

No `TWILIO_DATE9JA_MESSAGING_SERVICE_SID` is configured or required.

# Tests Added

- Canonical Date9ja host and unknown-host resolution.
- Production proxy/API host, Host allowlist, CORS, R2, sender, URL, and secret-name wiring.
- Production bucket resolution and missing Date9ja R2 configuration.
- Date9ja Resend sender and deep-link base URL.
- Date9ja phone registration and direct verification-request SMS suppression.
- Date9ja phone recovery cannot fall through to a global SMS sender.
- Production validator acceptance, missing-variable reporting, topology drift, wildcard CORS, placeholder sender, database collision, and missing storage service.

# Test Results

- Targeted Date9ja/config/auth set: **66 runs, 402 assertions, 0 failures, 0 errors**.
- Full configuration/tenant set: **62 runs, 387 assertions, 0 failures, 0 errors**.
- Full Rails suite: **2,382 runs, 26,762 assertions, 4 failures, 0 errors**.
- RuboCop on changed Ruby files: **18 files, no offenses**.
- Zeitwerk: **passed (“All is good!”)**.
- Brakeman 8.0.5: **0 warnings**.

The four full-suite failures are pre-existing and outside this closure:

1. OpenAPI route inventory parity.
2. Two Date9ja profile-contract expectations for `faith_family_expectations`.
3. DateZA welcome-email template expectation.

The full suite had six failures during an intermediate run because synthetic
unsupported-brand concurrency fixtures did not have platform contracts; the
capability guard was narrowed to public, configured brands and the affected
32-test set is now green.

# Remaining Unverified Production Checks

NOT VERIFIED — repository tests cannot prove:

- DNS for `api.date9ja.love` and `www.date9ja.love`, TLS certificate issuance, or proxy routing.
- Real Resend API key validity and sender/domain verification.
- Real R2 endpoint credentials, bucket existence/private policy, and upload/read/delete smoke flow.
- Production primary and queue database connectivity/credentials and the DB-backed `BrandDomain` row after deployment.
- Frontend same-site browser cookie/CSRF behavior against the deployed reverse-proxy topology.
- Real worker startup and delivery against provider resources.

These are deployment-resource checks, not missing repository wiring. The boot
validator will fail before serving if the required names/values are absent or
internally inconsistent.

# Blocker Status

**CLOSED**

The repository contains the Date9ja production tenant host, explicit host/CORS
allowlists, private R2 service and resolver wiring, Resend sender/app URL,
SMS-safe registration/recovery policy, and fail-fast validation. Remaining work
is limited to supplying real secret values and confirming DNS/provider/database
resources in the deployment environment.

# Production Checklist

- [ ] DNS/TLS for Date9ja API and frontend confirmed
- [ ] Date9ja R2 bucket and bucket-scoped credentials confirmed
- [ ] Resend production key and verified sender confirmed
- [ ] Primary and queue database connectivity confirmed
- [ ] `brands:ensure_date9ja` creates the production `BrandDomain`
- [ ] Workers boot with the same validated environment
- [ ] Browser cookie/CSRF smoke test completed
- [x] Explicit production API host committed
- [x] Explicit Host allowlist committed
- [x] Explicit Date9ja CORS origin committed
- [x] Private Date9ja R2 service committed
- [x] Date9ja email sender/app URL committed
- [x] Phone/SMS launch policy enforced and tested
- [x] Missing configuration fails fast without secret leakage
