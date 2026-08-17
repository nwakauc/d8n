module Notifications
  class EmailSender
    Result = Data.define(:success?, :delivery)

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, recipient:, code:, user:, mailer_action: :verification_code, metadata: {})
      @brand = brand
      @recipient = recipient
      @code = code
      @user = user
      @mailer_action = mailer_action
      @metadata = metadata
    end

    def call
      delivery = NotificationDelivery.create!(
        brand:,
        user:,
        channel: :email,
        provider: provider,
        recipient:,
        status: :pending,
        metadata:
      )

      IdentityVerificationMailer.with(
        brand_name: brand.name,
        recipient:,
        code:
      ).public_send(mailer_action).deliver_now
      delivery.update!(status: :sent, sent_at: Time.current)

      Result.new(true, delivery)
    rescue StandardError => e
      delivery&.update!(
        status: :failed,
        error_code: e.class.name,
        error_message: "Email delivery failed",
        failed_at: Time.current
      )
      Result.new(false, delivery)
    end

    private

    attr_reader :brand, :recipient, :code, :user, :mailer_action, :metadata

    def provider
      configured = ENV.fetch("D8N_EMAIL_PROVIDER", Rails.env.production? ? "required" : "action_mailer")
      raise "D8N email provider is not configured" if configured == "required"

      configured
    end
  end
end
