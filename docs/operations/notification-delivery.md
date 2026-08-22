# Product Notification Delivery Runbook

## Inspect without exposing content

Use ids, brand, type, channel, provider, status, attempt count, timestamps, and
generic error categories. Do not print notification payloads, recipients, device
tokens, email bodies, private messages, OTPs, or provider credentials.

Useful Rails-console queries:

```ruby
NotificationEvent.where(processed_at: nil).order(:created_at).limit(100)
NotificationDelivery.where.not(notification_id: nil).failed.order(failed_at: :desc).limit(100)
NotificationDelivery.where.not(notification_id: nil).group(:brand_id, :channel, :provider, :status).count
```

## Recovery

1. Confirm the web registration/membership committed and locate its
   `NotificationEvent` by `idempotency_key`.
2. Confirm Solid Queue health and worker availability.
3. Run `Notifications::RecoverPendingJob.perform_later` to re-enqueue never-started
   events/deliveries. The production recurring schedule normally does this every
   minute.
4. For a failed logical delivery, inspect `error_code`, `metadata["retryable"]`,
   `attempt_count`, and `last_attempted_at`. Active Job automatically retries
   transient provider responses up to five attempts.
5. Fix permanent configuration failures before deliberately requeueing the exact
   delivery id. `DeliverProductNotificationJob` no-ops for rows already marked
   sent/skipped and reuses the stable provider idempotency key.

Do not create a replacement notification to retry delivery. That would create a
second inbox item and a new provider idempotency key.

## Common failure categories

- `provider_not_configured`: select/configure the approved adapter.
- `sender_not_configured`: configure the brand-specific verified email sender.
- `device_unavailable`: the device was disabled/revoked/deleted after selection;
  do not retry it.
- `timeout`, rate limit, or provider 5xx: transient; verify queued retry state.

Escalate sustained failures by brand/channel/provider. Provider message ids are
operational correlation values only and must never enter the consumer API.
