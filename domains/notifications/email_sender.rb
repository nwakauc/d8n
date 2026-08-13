module Notifications
  class EmailSender
    Result = Data.define(:success?, :delivery)

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, recipient:, code:, user:, metadata: {})
      @brand = brand
      @recipient = recipient
      @code = code
      @user = user
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
      ).verification_code.deliver_now
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

    attr_reader :brand, :recipient, :code, :user, :metadata

    def provider
      configured = ENV.fetch("D8N_EMAIL_PROVIDER", Rails.env.production? ? "required" : "action_mailer")
      raise "D8N email provider is not configured" if configured == "required"

      configured
    end
  end
end
