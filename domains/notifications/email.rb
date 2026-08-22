module Notifications
  # Mirrors Notifications::Sms: a provider-independent seam for transactional
  # email. Domains call EmailSender; only the gateway behind this module knows a
  # vendor. Provider is chosen by D8N_EMAIL_PROVIDER (resend in production once
  # configured; action_mailer/test in development/test; `required` fails closed).
  module Email
    def self.gateway
      case provider_name
      when "resend"
        ResendGateway
      when "action_mailer"
        ActionMailerGateway
      when "test"
        TestGateway
      else
        RequiredGateway
      end
    end

    def self.provider_name
      ENV.fetch("D8N_EMAIL_PROVIDER", Rails.env.production? ? "required" : "action_mailer")
    end

    # Network-free readiness check the OTP/recovery/verification domains call BEFORE
    # enqueuing async delivery, so a misconfigured provider fails closed at request
    # time (503 / silent) rather than enqueuing a job that can never succeed.
    def self.configured?
      gateway.configured?
    end

    # Product senders are brand-specific. Production must explicitly configure a
    # sender such as D8N_DATEZA_EMAIL_FROM; development/test get a non-routable
    # local default. The legacy D8N_EMAIL_FROM remains scoped to identity mail.
    def self.product_from_address(brand)
      configured = ENV["D8N_#{brand.slug.upcase}_EMAIL_FROM"].presence
      return configured if configured
      return if Rails.env.production?

      "#{brand.name} <no-reply@#{brand.slug}.test>"
    end

    # Renders the transactional code email ONCE from the shared mailer so every
    # gateway sends byte-identical subject/body and no vendor re-implements copy.
    def self.build_message(brand:, recipient:, code:, mailer_action:)
      IdentityVerificationMailer.with(
        brand_name: brand.name,
        recipient:,
        code:
      ).public_send(mailer_action)
    end

    def self.build_product_message(notification:, recipient:, from_address:)
      ProductNotificationMailer.with(
        notification_type: notification.notification_type,
        recipient:,
        from_address:
      ).welcome
    end
  end
end
