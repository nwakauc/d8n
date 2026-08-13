module Identity
  class SessionRevoker
    def self.call(session:, ip_address: nil, user_agent: nil)
      Session.transaction do
        session.lock!
        session.update!(revoked_at: Time.current) unless session.revoked?
        SecurityEvent.create!(
          brand: session.brand,
          user: session.user,
          event_type: "auth.session.revoked",
          severity: :info,
          ip_address:,
          user_agent:,
          metadata: { session_id: session.id }
        )
      end

      session
    end
  end
end
