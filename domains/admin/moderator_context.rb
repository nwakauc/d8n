module Admin
  # Authorizes a signed-in network User as a report moderator for one brand.
  #
  # Authorization is entirely server-derived: the user must map to a kept, active
  # AdminUser and hold a kept, active AdminAssignment for exactly the request's
  # brand (resolved from the host, never from a client-supplied brand id). Any
  # active admin role currently grants report moderation — differentiated admin
  # RBAC is deliberately deferred (see 90_later_when_justified.md). Returns the
  # AdminUser when authorized, otherwise nil.
  class ModeratorContext
    def self.resolve(user:, brand:)
      return if user.blank? || brand.blank?

      admin_user = AdminUser.kept.where(status: :active).find_by(user:)
      return if admin_user.blank?

      assigned = AdminAssignment.kept.where(status: :active, admin_user:, brand:).exists?
      assigned ? admin_user : nil
    end
  end
end
