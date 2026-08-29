# D8N Product Notification Architecture

## Scope and boundary

D8N product notifications are brand-owned records for product events such as a
welcome, match, message, verification-status, moderation, security, or future
subscription update. They are separate from Identity's `OtpChallenge` flows.
Authentication may reuse low-level email/SMS gateways, but OTPs, verification
codes, and recovery codes never become `Notification` rows or inbox items.

## Implemented flow

```txt
membership transaction
  -> NotificationEvent (durable outbox, stable idempotency key)
  -> after-commit ProcessEventJob
  -> Notifications::Policy
  -> Notification (in-app source of truth)
  -> one logical NotificationDelivery per channel/device
  -> DeliverProductNotificationJob
  -> email or push gateway
```

`Notifications::RecoverPendingJob` re-enqueues outbox events and product delivery
rows that remained pending after an enqueue failure. It runs every minute in
production. Provider work never runs inside the registration transaction.

## Implemented types and policy

DateZA currently enables these product-notification policies:

| Event | Brand | Notification type | Channels |
| --- | --- | --- | --- |
| `membership_registered` | DateZA | `dateza.welcome` | In-app; email when an email exists; push for active devices |
| `like_received` | DateZA | `dateza.like_received` | In-app; email; push for active devices |
| `match_created` | DateZA | `dateza.match_created` | In-app; email; push for active devices |
| `opener_received` | DateZA | `dateza.opener_received` | In-app; email; push for active devices |
| `message_received` | DateZA | `dateza.message_received` | In-app; debounced email/push |

`Notifications::Types` owns stable type codes, safe presentation copy, and an
allow-list of payload fields. The DateZA welcome payload is empty. Dating-event
payloads contain only opaque actor/target identifiers; message text and media
never enter the durable event, notification, delivery metadata, or logs. Email
presentation resolves current authorized records at delivery time and falls back
to generic copy when a block, closure, deletion, or privacy boundary prevents
access. Adding a new event requires an explicit policy/type entry and privacy
review; frontend prose is not the sole semantic identifier.

## Tenant and recipient integrity

`NotificationEvent`, `Notification`, `NotificationPreference`, and
`DeviceRegistration` each carry `brand_id`, `user_id`, and
`brand_membership_id`. Composite foreign keys prove that the membership belongs to
that exact brand/user pair. API queries require the active membership resolved from
the host brand and bearer-session user. Unknown and cross-brand public ids return
the same neutral not-found response.

## Preferences

V1 stores `product_email_enabled` and `push_enabled`, defaulting to true. There is
no preferences API yet. `security_email` and `transactional_email` are explicitly
non-disableable through this generic product preference model. Authentication
challenge delivery has its own policy and throttles.

## Device and push status

`DeviceRegistration` supports `ios`, `android`, and reserved future `web`
platforms. Tokens are encrypted at rest and have a keyed digest for active
brand-level uniqueness. Disabled, revoked, deleted, wrong-brand, or wrong-member
devices are never selected. A device enrollment/revocation API is deliberately not
included in this backend ticket.

No production push provider is approved. `Notifications::Push` therefore exposes
a provider boundary, a test adapter, and a production-safe `required` adapter that
records `provider_not_configured`. No APNs/FCM assumptions or credentials are in
the domain model.

## Email configuration

Identity mail keeps the existing provider configuration. Product email additionally
requires a brand sender in production:

```txt
D8N_EMAIL_PROVIDER=resend
RESEND_API_KEY=<secret>
D8N_DATEZA_EMAIL_FROM=DateZA <no-reply@date-za.com>
D8N_DATEZA_APP_URL=https://www.date-za.com
D8N_SMS_PROVIDER=twilio
TWILIO_ACCOUNT_SID=<secret>
TWILIO_API_KEY_SID=<secret>
TWILIO_CLIENT_SECRET=<secret>
TWILIO_DATEZA_MESSAGING_SERVICE_SID=<secret>
```

The brand sender must be a verified identity accepted by the selected email
provider. Identity verification, password recovery, and product notification mail
all select this sender from the persisted brand. The legacy `D8N_EMAIL_FROM` key is
accepted only for HookUs; no other brand falls back to it. Never put provider keys
in repository files or logs. Development/test use non-routable `<brand>.test`
sender defaults. DateZA product templates use brand-owned copy, logo, colors, a
safe current sender profile image when available, and a direct brand-app CTA.
Message previews are whitespace-normalized and capped at 100 characters. Media-
only messages use semantic copy; private message media is never embedded. The
first message in a conversation burst sends immediately, while further email/
push interruptions for the same recipient and conversation are suppressed for
the debounce window.

DateZA verification and product mail use dedicated multipart templates selected
from the persisted brand slug/type. They reuse the canonical DateZA heart mark,
wordmark, warm-white canvas, ink, and pink (`#E8375A`) from the DateZA frontend.
The HTML uses a table-based 600px responsive layout with inline styles and an
Outlook width fallback; all critical copy and codes remain text, and multipart
plain-text bodies are retained. The readable wordmark remains when a client omits
inline SVG. CTA paths are composed from opaque public identifiers and the
brand-owned `D8N_DATEZA_APP_URL`; DateZA has an explicit production default.

SMS readiness is also brand-aware: valid Twilio account credentials are
insufficient unless the resolved brand has a messaging-service SID (or an
explicit generic/from fallback). Kamal's top-level staging env is shared by web
and job roles so these secrets must be populated once and will reach the Solid
Queue worker as well as Rails web.

## Planned, not implemented

- Device enrollment/revocation API and frontend permission flow.
- Production APNs/FCM (or other) adapter and invalid-token feedback handling.
- Preference-management API, quiet hours, digesting, and campaign/newsletter tools.
- RealMe/moderation/security/subscription event policies.
- Realtime/websocket inbox delivery and notification UI.
