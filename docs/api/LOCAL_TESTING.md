# Testing the D8N API Locally

This guide assumes:

- the D8N Rails API runs at `http://localhost:3000`;
- the HookUs frontend runs at `http://localhost:3001`;
- PostgreSQL is available locally;
- local requests should resolve to the intended brand through its host.

Rails on port 3000 is the API. HookUs on port 3001 is an API client. Swagger UI
is served by Rails, while Apidog is a separate API client.

## 1. Prepare And Start The API

From the D8N repository, prepare the database and install the local HookUs brand
mapping:

```sh
bin/rails db:prepare
bin/rails brands:seed_hookus_dev
```

The brand task creates the HookUs brand when necessary and maps the `localhost`
request host to it. D8N deliberately resolves brands from trusted hosts; do not
send a `brand_id` or invent an `X-Brand` header.

To provision DateZA independently on the same D8N database, run:

```sh
bin/rails brands:seed_dateza_dev
```

This maps `dateza.test` to the canonical `DateZA`/`dateza` tenant without
changing the HookUs `localhost` mapping. No production DateZA domain is created.
Use `DATEZA_DEV_HOST` only when a different development host is required.

Test DateZA host resolution explicitly:

```sh
curl --resolve dateza.test:3000:127.0.0.1 \
  http://dateza.test:3000/api/v1/auth/methods
```

Start Rails on port 3000:

```sh
bin/rails server -p 3000
```

In another terminal, confirm that it responds:

```sh
curl -i http://localhost:3000/api/v1/health
```

Also confirm that the runtime OpenAPI contract is available:

```sh
curl -i http://localhost:3000/api/v1/openapi.json
```

## 2. Test With Swagger UI

Open this URL in a browser:

```txt
http://localhost:3000/api/docs
```

At the top of Swagger, select **Current API origin** if it is not already
selected. Requests should be sent to `http://localhost:3000`, not
`https://localhost` and not port 3001.

Start with `GET /api/v1/health`:

1. Expand the endpoint.
2. Select **Try it out**.
3. Select **Execute**.
4. Expect HTTP `200`.

If the displayed request URL starts with `https://localhost`, reload Swagger and
select **Current API origin** from the Servers list.

### Understand The Schemas Section

The **Schemas** section at the bottom of Swagger describes reusable request and
response shapes. It is reference material, not a separate endpoint to execute.
For example, `IdentifierVerificationRequest` tells you that post-signup
verification requires a `kind` of `phone` or `email`. The operation itself
supplies an editable example after you select **Try it out**.

## 3. Register And Optionally Verify Your Identifier

For the fastest local signup, use `POST /api/v1/auth/password/register` in
Swagger with either a phone number or email address and a password of at least six
characters:

```json
{
  "identifier": "+27821234567",
  "password": "secret",
  "device_name": "Local Swagger"
}
```

The `201` response contains a bearer token immediately. Its
`identifier.verified` value is `false` because signup does not pretend that D8N
has proven phone or inbox control. Paste the returned token into **Authorize**
without adding the `Bearer ` prefix. Use `POST /api/v1/auth/password/login` for
later sessions. The response's `onboarding.next_step` will initially be
`profile`; use `GET /api/v1/profile/configuration`, then
`PATCH /api/v1/profile`, and continue according to the updated onboarding state.

That is the default API/Swagger mode. To test persistent browser authentication,
add `"session_mode": "browser"` and send requests with cookie credentials. The
response then contains no bearer token; it sets `d8n_web_session` as HttpOnly and
returns `browser_session.csrf_token`. Call `GET /api/v1/me` without an
Authorization header to simulate a page reload. For logout or any other unsafe
cookie-authenticated request, send that value as `X-CSRF-Token`.

Identifier verification happens only after password signup. Keep the bearer
token authorized in Swagger, expand `POST /api/v1/auth/verification`, select
**Try it out**, and request the channel already attached to the account:

```json
{
  "kind": "phone"
}
```

Select **Execute**. Expect HTTP `202`. The response is intentionally generic and
never returns the code.

The default development SMS provider is a null provider, so it records delivery
without sending a real SMS. For local manual testing only, set the newest
challenge owned by your signed-in user to the known code `123456`:

```sh
bin/rails runner '
abort "development only" unless Rails.env.development?
brand = Brand.kept.find_by!(slug: "hookus")
challenge = OtpChallenge.phone_verification.where(brand:).order(created_at: :desc).first!
challenge.update!(code_digest: OtpChallenge.digest_code("123456"))
puts "Local verification code set to 123456"
'
```

Do not use this technique in staging or production.

Next, expand `PATCH /api/v1/auth/verification` and execute:

```json
{
  "kind": "phone",
  "code": "123456"
}
```

Expect HTTP `200` with `identifier.verified: true`. This endpoint does not return
or create another session. Email verification follows the same two requests with
`kind: "email"`; development/test delivery uses Action Mailer, while production
must configure `D8N_EMAIL_PROVIDER` and an actual Action Mailer transport.

Confirm authentication with `GET /api/v1/me`. Expect HTTP `200` and a response
whose brand slug is `hookus`.

To test the authenticated settings flow, use `PATCH /api/v1/auth/password` while
the bearer token is still authorized:

```json
{
  "current_password": "secret",
  "password": "new-secret",
  "password_confirmation": "new-secret"
}
```

Expect HTTP `200`. The current browser session remains usable; other sessions
issued through the same password credential are revoked. This is not the future
signed-out forgot-password recovery flow.

The token is secret and brand-bound. Do not paste it into source code, commit it,
or use it against another brand host.

## 4. Continue Through The API

Once authorized, a useful manual test order is:

1. `GET /api/v1/me` to confirm identity, session, and brand.
2. `GET /api/v1/profile/configuration` to learn HookUs fields and allowed values.
3. `GET /api/v1/profile` to inspect the current profile.
4. `PATCH /api/v1/profile` to fill in profile fields.
5. Use the preferences, options, location, and photo endpoints as needed.
6. `POST /api/v1/profile/publication` after the completion response says the
   profile is complete.
7. `GET /api/v1/discovery`, then use returned public profile UUIDs for likes,
   passes, and blocks.
8. Use returned public match UUIDs for match and conversation endpoints.

Swagger shows the exact request body and documented responses for each operation.
Dating endpoints use public profile UUIDs; do not substitute internal user or
profile database IDs.

## 5. Test With Apidog

Apidog can import the same contract used by Swagger:

```txt
http://localhost:3000/api/v1/openapi.json
```

In Apidog:

1. Create or open a project and import data from an OpenAPI URL.
2. Enter the runtime contract URL above.
3. Create a local environment and set its service/base URL to
   `http://localhost:3000`.
4. Run `GET /api/v1/health` and expect HTTP `200`.
5. Run the two OTP calls from the authentication section above.
6. Store the returned token in a private local environment variable such as
   `token`.
7. Configure Bearer Token authentication with `{{token}}` for protected calls.
8. Run `GET /api/v1/me` and confirm the `hookus` brand.

If Apidog imports `/` as the server URL, override it in the local environment
with `http://localhost:3000`. Do not add `brand_id`; the `localhost` host mapping
selects HookUs.

The Apidog desktop app is not subject to browser CORS enforcement. Its web client
or browser extension may be, depending on how requests are sent.

## 6. Connect Browser Frontends

Browser frontends should send API traffic to Rails, not to their own development
servers:

```txt
HookUs UI:  http://localhost:3001
DateZA UI:  http://localhost:5173
D8N API:    http://localhost:3000
```

A browser considers those different origins because their ports differ. D8N's
development CORS policy explicitly permits `http://localhost:3001` and
`http://127.0.0.1:3001` for HookUs, and `http://localhost:5173` for DateZA, so
these clients may call `http://localhost:3000/api/v1/...` directly. The approved
deployed DateZA origin is `https://dateza.vercel.app`. Restart Rails after
changing the Gemfile or CORS configuration.

Production has no default cross-origin allowlist. Set a comma-separated list of
exact trusted frontend origins when browser clients need direct API access:

```sh
D8N_CORS_ORIGINS=https://hookus.example.com,https://www.hookus.example.com,https://dateza.vercel.app
```

Do not use `*`. D8N accepts bearer authorization, `Content-Type`, and
`X-CSRF-Token` from exact allowed origins, exposes `Retry-After`, and enables
credentialed requests for those origins only. Browser frontends must use
`credentials: "include"`. Production cookies are `Secure` and `SameSite=None`;
development/test cookies are `SameSite=Lax`. HookUs (`localhost` on different
ports) is same-site. DateZA's `localhost` frontend and `dateza.test` API are not,
so DateZA persistent-cookie development requires a same-origin frontend proxy
that preserves the upstream `dateza.test` host (or local HTTPS with a secure
cross-site cookie setup). Direct cross-origin DateZA development remains suitable
for bearer mode, not persistent cookie mode.

A same-origin development proxy remains an optional alternative:

```txt
browser calls /api/v1/...
HookUs dev server on :3001 proxies /api/... to http://localhost:3000/api/...
```

Configure the proxy in the HookUs repository, where its framework and environment
conventions are defined. Preserve the path, method, body, `Authorization` header,
and response status. Do not add a client-controlled brand header.

## 7. Common Failures

### Swagger says `Failed to fetch`

- Open Swagger itself at `http://localhost:3000/api/docs`.
- Select **Current API origin**.
- Confirm the request URL begins with `http://localhost:3000`.
- Confirm Rails is running and `GET /api/v1/health` works in a terminal.

This is usually a wrong scheme or port. Swagger served on Rails does not require
CORS to call the same Rails origin.

### The API returns `404 {"error":"brand_required"}`

Run:

```sh
bin/rails brands:seed_hookus_dev
```

Then retry with `localhost`, not an unrelated hostname or IP address.

### OTP verification returns `401 {"error":"invalid_code"}`

- Request a fresh OTP first.
- Use exactly the same normalized phone number for request and verification.
- Set the newest local challenge to `123456` using the development-only command.
- Remember that challenges expire, are single-use, and count failed attempts.

### OTP request returns `429 {"error":"rate_limited"}`

Respect the `Retry-After` response header before trying again. Rate limiting is
part of the real authentication behavior and remains enabled in development.

### A protected endpoint returns `401 unauthorized`

- Authorize with the raw token returned by OTP verification.
- In Swagger, do not manually include `Bearer ` in the authorization dialog.
- In Apidog or HookUs, send `Authorization: Bearer YOUR_TOKEN`.
- Request a new token if it expired or its session was revoked.

### A frontend works in Apidog but fails in the browser

Confirm Rails was restarted after dependency installation, inspect the preflight
response, and confirm the frontend is running from an exact approved origin.
HookUs local origins are `http://localhost:3001` and
`http://127.0.0.1:3001`; DateZA local is `http://localhost:5173`. Any other
frontend origin must be explicitly listed in `D8N_CORS_ORIGINS`.

## 8. Reset Between Manual Test Scenarios

Prefer a new development phone number or wait for the documented throttle window.
Do not delete production-like data merely to bypass authentication controls. If a
full local database reset is genuinely needed, confirm that the selected Rails
environment is development before running any destructive database command.
