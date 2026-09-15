# Date9ja Production Configuration

Date9ja uses the shared D8N production deployment and the legacy-compatible
public endpoints `https://api.date9ja.love` and `https://www.date9ja.love`.
`config/deploy.production.yml` contains the non-secret topology and declares all
secret names. Secret values belong in the deployment secret store, never in the
repository, image, logs, or command history.

## Required non-secret values

These are committed in `config/deploy.production.yml`:

| Variable | Required production setting |
| --- | --- |
| `DATE9JA_API_HOST` | `api.date9ja.love` |
| `D8N_ALLOWED_HOSTS` | Exact comma-separated API hosts including `api.date9ja.love`; no wildcard |
| `D8N_CORS_ORIGINS` | Exact HTTPS frontend origins including `https://www.date9ja.love`; no wildcard |
| `D8N_DATE9JA_APP_URL` | `https://www.date9ja.love` |
| `D8N_DATE9JA_EMAIL_FROM` | A Date9ja address on a sender/domain verified by Resend |
| `D8N_DEFAULT_MAILER_HOST` | The platform's real default URL host; never `example.com` |
| `D8N_EMAIL_PROVIDER` | `resend` |
| `D8N_R2_ENABLED` | `true` |
| `D8N_DEPLOYMENT_ENV` | `production` |
| `D8N_R2_BRANDS` | Must include `date9ja` |
| `D8N_DATABASE_HOST` | Primary PostgreSQL host |
| `D8N_DATABASE_PORT` | Numeric PostgreSQL port |
| `D8N_DATABASE_NAME` | Primary database name |
| `D8N_DATABASE_USERNAME` | Application database role |
| `D8N_QUEUE_DATABASE_NAME` | Separate Solid Queue database name |

## Required secrets

- `RAILS_MASTER_KEY`
- `D8N_DATABASE_PASSWORD`
- `D8N_R2_ENDPOINT`
- `D8N_R2_DATE9JA_PRODUCTION_ACCESS_KEY_ID`
- `D8N_R2_DATE9JA_PRODUCTION_SECRET_ACCESS_KEY`
- `D8N_R2_DATE9JA_PRODUCTION_BUCKET`
- `RESEND_API_KEY`
- `D8N_AR_ENCRYPTION_PRIMARY_KEY`
- `D8N_AR_ENCRYPTION_DETERMINISTIC_KEY`
- `D8N_AR_ENCRYPTION_KEY_DERIVATION_SALT`

`D8N_R2_ENDPOINT` is shared endpoint configuration; the Date9ja access key,
secret, and bucket must be production-specific and bucket-scoped. The bucket
must remain private. Configure the bucket's browser CORS rules separately for
the direct-upload operations the frontend actually uses; do not make the bucket
or a custom development URL public.

## Explicitly not configured for Date9ja

Do not create `TWILIO_DATE9JA_MESSAGING_SERVICE_SID` for launch. Date9ja has no
`verify.contact.phone` or `notify.sms` capability. New phone/password signup is
rejected; migrated phone/password credentials may still log in, but cannot
start phone verification or phone password recovery. New users register by
email and confirm email through Resend. Email confirmation does not satisfy the
separate RealMe policy.

## Boot and cutover checks

The production initializer validates the Date9ja host, allowlist, CORS origin,
app URL, sender, Resend adapter/key, R2 service and credentials, Active Record
encryption keys, and both database configurations. It raises an actionable
variable-name-only error before the server or worker can serve with incomplete
configuration. Rails separately consumes `RAILS_MASTER_KEY`, and
`bin/docker-entrypoint` runs `db:prepare` for both primary and queue databases
before starting a server or worker.

Supplying syntactically complete configuration does not prove external state.
Before traffic cutover, verify DNS/TLS, Resend sender/domain verification, the
private R2 bucket policy and upload/read/delete flow, primary and queue database
connectivity, and Date9ja's DB-backed `BrandDomain` row.
