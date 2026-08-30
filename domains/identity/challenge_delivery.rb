module Identity
  # Turns a persisted OtpChallenge + its plaintext code into one delivery attempt,
  # owning the channel choice (phone -> SMS, email -> email) and the transactional
  # copy for every challenge kind. Both the async worker (Notifications::
  # DeliverChallengeJob) and any future synchronous caller go through here, so the
  # message wording lives in exactly one place.
  #
  # The plaintext `code` is passed in memory only; it is never persisted by this
  # class beyond the provider call. Delivery metadata is content-free.
  class ChallengeDelivery
    Result = Data.define(:success?, :retryable)

    def self.call(...)
      new(...).call
    end

    def initialize(challenge:, code:)
      @challenge = challenge
      @code = code
    end

    def call
      identifier = challenge.identity_identifier
      return Result.new(success?: false, retryable: false) if identifier.nil?

      sender_result = identifier.phone? ? deliver_sms(identifier) : deliver_email(identifier)
      Result.new(success?: sender_result.success?, retryable: sender_result.retryable)
    end

    private

    attr_reader :challenge, :code

    def deliver_sms(identifier)
      Notifications::SmsSender.call(
        brand: challenge.brand,
        user: identifier.user,
        recipient: phone_recipient(identifier),
        body: sms_body,
        metadata:
      )
    end

    def deliver_email(identifier)
      Notifications::EmailSender.call(
        brand: challenge.brand,
        user: identifier.user,
        recipient: email_recipient(identifier),
        code:,
        mailer_action:,
        metadata:,
        idempotency_key: "otp-challenge-#{challenge.id}"
      )
    end

    def email_recipient(identifier)
      challenge.email_change? ? challenge.identifier : identifier.normalized_value
    end

    def phone_recipient(identifier)
      challenge.phone_change? ? challenge.identifier : identifier.normalized_value
    end

    def metadata
      { purpose: challenge.metadata["purpose"], challenge_id: challenge.id }.compact
    end

    def sms_body
      "#{challenge.brand.name} #{recovery? ? 'password recovery' : 'verification'} code: #{code}"
    end

    def mailer_action
      return :recovery_code if recovery?
      return :email_change_code if challenge.email_change?

      :verification_code
    end

    def recovery?
      challenge.password_recovery?
    end
  end
end
