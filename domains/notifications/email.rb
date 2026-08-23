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
    def self.configured?(brand:)
      gateway.configured?(brand:)
    end

    # Every transactional sender is brand-specific. Production must explicitly
    # configure D8N_<BRAND>_EMAIL_FROM. D8N_EMAIL_FROM predates multi-brand mail
    # and is accepted only for HookUs so another consumer brand can never inherit
    # HookUs's verified sender identity.
    def self.from_address(brand)
      configured = ENV["D8N_#{brand.slug.upcase}_EMAIL_FROM"].presence
      return configured if configured
      legacy_hookus_sender = ENV["D8N_EMAIL_FROM"].presence
      return legacy_hookus_sender if brand.slug == "hookus" && legacy_hookus_sender
      return if Rails.env.production?

      "#{brand.name} <no-reply@#{brand.slug}.test>"
    end

    def self.product_from_address(brand) = from_address(brand)

    # Renders the transactional code email ONCE from the shared mailer so every
    # gateway sends byte-identical subject/body and no vendor re-implements copy.
    def self.build_message(brand:, recipient:, code:, mailer_action:)
      IdentityVerificationMailer.with(
        brand_name: brand.name,
        recipient:,
        code:,
        from_address: from_address(brand)
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
