module Notifications
  # Performs the provider network call for an OTP/recovery/verification code AFTER
  # the domain transaction has committed, so the request never holds a DB
  # transaction or advisory lock across a slow provider.
  #
  # Security: the only argument is the challenge id. The plaintext code is read
  # from the challenge's encrypted `delivery_code` column at run time and never
  # appears in job arguments, logs, or SecurityEvent metadata. On a successful (or
  # permanently failed) send the ciphertext is cleared, which also makes a duplicate
  # run a no-op — proportional, beta-safe idempotency without distributed locks.
  #
  # Retries: only transient provider failures retry, with bounded backoff kept well
  # inside the 10-minute code lifetime; every attempt re-checks that the code is
  # still deliverable, so an expired/consumed/already-sent code is never delivered.
  class DeliverChallengeJob < ApplicationJob
    class TransientDeliveryError < StandardError; end

    queue_as :default

    retry_on TransientDeliveryError, wait: ->(executions) { (executions**2).seconds }, attempts: 5

    def perform(challenge_id)
      challenge = OtpChallenge.find_by(id: challenge_id)
      return log(challenge_id, "skipped", reason: "missing") if challenge.nil?
      return log(challenge_id, "skipped", reason: "not_deliverable") unless challenge.deliverable?

      result = Identity::ChallengeDelivery.call(challenge:, code: challenge.delivery_code)

      if result.success?
        challenge.clear_delivery_code!
        log(challenge_id, "sent")
      elsif result.retryable
        log(challenge_id, "retry")
        raise TransientDeliveryError
      else
        # Permanent failure: stop delivering this code. The failed NotificationDelivery
        # already carries the provider error category for operators.
        challenge.clear_delivery_code!
        log(challenge_id, "failed")
      end
    end

    private

    # Content-free structured log: identifies the challenge and outcome only — never
    # the code, recipient, or provider payload.
    def log(challenge_id, outcome, reason: nil)
      Rails.logger.info(
        "[notifications.deliver_challenge] challenge_id=#{challenge_id} outcome=#{outcome} " \
          "reason=#{reason.inspect} attempt=#{executions}"
      )
    end
  end
end
