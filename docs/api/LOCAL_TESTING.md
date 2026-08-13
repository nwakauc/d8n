# Testing the D8N API Locally

This guide assumes:

- the D8N Rails API runs at `http://localhost:3000`;
- the HookUs frontend runs at `http://localhost:3001`;
- PostgreSQL is available locally;
- local requests should resolve to the HookUs brand.

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
For example, `PhoneOtpRequest` tells you that the OTP request body requires a
`phone` string. The operation itself supplies an editable example based on that
schema after you select **Try it out**.

## 3. Authenticate With A Local Phone OTP

Authentication has two API calls:

1. request an OTP;
2. verify that OTP to receive a bearer token.

In Swagger, expand `POST /api/v1/auth/phone/request_otp`, select **Try it out**,
and use a development-only phone number that you control:

```json
{
  "phone": "+27821234567"
}
```

Select **Execute**. Expect HTTP `202`. The response is intentionally generic and
never returns the OTP.

The default development SMS provider is a null provider, so it records delivery
without sending a real SMS. For local manual testing only, set the newest
challenge for the same phone to the known code `123456`:

```sh
bin/rails runner '
abort "development only" unless Rails.env.development?
brand = Brand.kept.find_by!(slug: "hookus")
phone = Identity::PhoneNormalizer.call("+27821234567")
challenge = OtpChallenge.phone_otp.where(brand:, identifier: phone).order(created_at: :desc).first!
challenge.update!(code_digest: OtpChallenge.digest_code("123456"))
puts "Local OTP set to 123456"
'
```

Do not use this technique in staging or production.

Next, expand `POST /api/v1/auth/phone/verify_otp` and execute:

```json
{
  "phone": "+27821234567",
  "code": "123456",
  "device_name": "Local Swagger"
}
```

Expect HTTP `201`. Copy the `token` value from the response. Select
**Authorize** at the top of Swagger, paste the token itself, and select
**Authorize**. Do not type the `Bearer ` prefix; Swagger adds it to requests.

Confirm authentication with `GET /api/v1/me`. Expect HTTP `200` and a response
whose brand slug is `hookus`.

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

## 6. Connect HookUs On Port 3001

HookUs should send API traffic to Rails, not to its own development server:

```txt
HookUs UI:  http://localhost:3001
D8N API:    http://localhost:3000
```

A browser considers those different origins because their ports differ. This
repository does not currently enable cross-origin requests in Rails. The safest
local setup is a development proxy in the HookUs frontend:

```txt
browser calls /api/v1/...
HookUs dev server on :3001 proxies /api/... to http://localhost:3000/api/...
```

That keeps browser requests same-origin from the frontend's perspective and does
not weaken the API's CORS policy. Configure the proxy in the HookUs repository,
where its framework and environment conventions are defined. Preserve the path,
method, body, `Authorization` header, and response status. Do not add a client-
controlled brand header.

If HookUs instead calls `http://localhost:3000` directly from browser JavaScript,
the browser will block it until D8N has an explicit development-only CORS policy
for `http://localhost:3001`. Treat that as a separate reviewed security change;
do not enable every origin with `*`.

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

### HookUs works in Apidog but fails in the browser

That normally indicates the port-3001-to-port-3000 CORS boundary. Use the HookUs
development proxy described above, or implement a narrowly scoped development
CORS policy as a separate reviewed change.

## 8. Reset Between Manual Test Scenarios

Prefer a new development phone number or wait for the documented throttle window.
Do not delete production-like data merely to bypass authentication controls. If a
full local database reset is genuinely needed, confirm that the selected Rails
environment is development before running any destructive database command.
