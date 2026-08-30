module Admin
  # Compatibility adapter retained for callers outside the HQ/admin controller
  # bases. New code must authorize a concrete capability through
  # Admin::AuthorizationContext instead of treating every role as moderator.
  class ModeratorContext
    def self.resolve(user:, brand:)
      context = AuthorizationContext.resolve(user:, brand:)
      return if context.blank?
      return unless context.allowed?(Capabilities::REPORTS_READ)

      context.admin_user
    end
  end
end
