module Admin
  # Resolves one fail-closed, brand-scoped administrative authorization
  # context. Multiple active assignments are treated as invalid rather than
  # combining privileges ambiguously.
  class AuthorizationContext
    Result = Data.define(:admin_user, :assignment, :role, :capabilities) do
      def allowed?(capability)
        capabilities.include?(capability.to_s)
      end

      def mfa_enrolled?
        admin_user.admin_mfa_credentials.kept.active.exists?
      end
    end

    def self.resolve(user:, brand:)
      return if user.blank? || brand.blank?

      admin_user = AdminUser.kept.active.find_by(user:)
      return if admin_user.blank?

      assignments = AdminAssignment.kept.active.includes(:admin_role)
        .where(admin_user:, brand:).limit(2).to_a
      return unless assignments.one?

      assignment = assignments.first
      role = assignment.admin_role
      return if role.deleted_at.present? || !Capabilities.known_role?(role.name)

      Result.new(
        admin_user:,
        assignment:,
        role:,
        capabilities: Capabilities.for_role(role.name)
      )
    end
  end
end
