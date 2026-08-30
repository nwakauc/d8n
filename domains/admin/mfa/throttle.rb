module Admin
  module Mfa
    module Throttle
      WINDOW = 10.minutes
      LIMIT = 5

      module_function

      def check!(admin_user:)
        failures = SecurityEvent.where(
          user: admin_user.user,
          event_type: %w[admin.mfa_challenge_failed admin.mfa_enrollment_failed admin.mfa_reset_failed]
        ).where(created_at: WINDOW.ago..)
        return if failures.count < LIMIT

        oldest = failures.order(:created_at).first
        retry_after = [ (oldest.created_at + WINDOW - Time.current).ceil, 1 ].max
        raise Error.new(:admin_mfa_rate_limited, retry_after:)
      end
    end
  end
end
