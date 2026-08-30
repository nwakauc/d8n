module Admin
  module Mfa
    module Audit
      module_function

      def record!(admin_user:, brand:, event_type:, session: nil, severity: :info, metadata: {})
        SecurityEvent.create!(
          brand:,
          user: admin_user.user,
          event_type:,
          severity:,
          ip_address: session&.ip_address,
          user_agent: session&.user_agent,
          metadata: {
            admin_user_id: admin_user.id,
            session_id: session&.id
          }.compact.merge(metadata)
        )
      end
    end
  end
end
