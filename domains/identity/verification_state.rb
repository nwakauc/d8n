module Identity
  # Safe client projection for the identifier attached to the current session.
  # It deliberately returns a masked destination, never the normalized value.
  class VerificationState
    Result = Data.define(
      :kind,
      :verified,
      :masked_destination,
      :code_dispatched,
      :resend_available_in
    )

    def self.call(...)
      new(...).call
    end

    def initialize(session:, brand:, now: Time.current)
      @session = session
      @brand = brand
      @now = now
    end

    def call
      identifier = session_identifier
      return if identifier.blank?

      challenge = latest_challenge(identifier)
      Result.new(
        identifier.kind,
        identifier.verified_at.present?,
        mask(identifier),
        code_dispatched?(challenge),
        resend_available_in(challenge)
      )
    end

    private

    attr_reader :session, :brand, :now

    def session_identifier
      credential = session&.credential
      identifier = credential&.identity_identifier
      return if credential.blank? || identifier.blank?
      return unless credential.user_id == session.user_id && identifier.user_id == session.user_id
      return if identifier.deleted_at.present?

      identifier
    end

    def latest_challenge(identifier)
      OtpChallenge.where(
        brand:,
        identity_identifier: identifier,
        kind: "#{identifier.kind}_verification"
      ).order(created_at: :desc).first
    end

    def code_dispatched?(challenge)
      return false if challenge.blank? || challenge.consumed? || challenge.expired?
      return true if challenge.delivery_code.present?

      NotificationDelivery.sent.where(
        brand:,
        user_id: session.user_id
      ).where("metadata ->> 'challenge_id' = ?", challenge.id.to_s).exists?
    end

    def resend_available_in(challenge)
      return 0 if challenge.blank?

      seconds = (challenge.created_at + OtpThrottle::IDENTIFIER_COOLDOWN - now).ceil
      [ seconds, 0 ].max
    end

    def mask(identifier)
      value = identifier.normalized_value
      return mask_email(value) if identifier.email?

      digits = value.gsub(/\D/, "")
      last = digits.last(3)
      prefix = value.start_with?("+") ? "+" : ""
      "#{prefix}#{'•' * [ digits.length - last.length, 4 ].max}#{last}"
    end

    def mask_email(value)
      local, domain = value.split("@", 2)
      return "••••" if local.blank? || domain.blank?

      "#{local.first}#{'•' * [ local.length - 1, 3 ].max}@#{domain}"
    end
  end
end
