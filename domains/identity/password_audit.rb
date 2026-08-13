module Identity
  class PasswordAudit
    def self.record!(brand:, purpose:, result:, identifier:, identifier_kind:, ip_address:, user_agent:,
      user: nil, identity_identifier: nil, credential: nil, retry_after: nil, metadata: {})
      AuthAttempt.create!(
        brand:,
        user:,
        identity_identifier:,
        credential:,
        kind: :password,
        result:,
        identifier: identifier.presence || "invalid",
        ip_address:,
        user_agent:,
        metadata: { purpose: }.merge(metadata)
      )

      SecurityEvent.create!(
        brand:,
        user:,
        event_type: "auth.#{purpose}.#{result}",
        severity: result.to_sym == :succeeded ? :info : :warning,
        ip_address:,
        user_agent:,
        metadata: {
          identifier_kind: identifier_kind.to_s.presence || "unknown",
          identifier_last4: identifier.to_s.last(4),
          retry_after:
        }.compact.merge(metadata)
      )
    end
  end
end
