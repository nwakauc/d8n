module Admin
  class OperatorManagement
    STATUSES = %w[active suspended revoked].freeze

    def self.assign(actor_context:, brand:, email:, role_name:, session: nil)
      raise OperatorError, :invalid_role unless RolePolicy.grantable?(actor_context, role_name)

      user = user_for_email(email)
      raise OperatorError, :operator_unavailable if user.blank?
      unless BrandMembership.kept.active.exists?(user:, brand:)
        raise OperatorError, :operator_brand_membership_required
      end

      role = AdminRole.kept.find_by(name: role_name)
      raise OperatorError, :invalid_role if role.blank?

      admin_user = nil
      assignment = nil
      ActiveRecord::Base.transaction do
        admin_user = AdminUser.find_or_initialize_by(user:)
        admin_user.assign_attributes(status: :active, deleted_at: nil) if admin_user.new_record?
        admin_user.save!
        raise OperatorError, :self_management_forbidden if admin_user == actor_context.admin_user

        current = current_assignment(admin_user:, brand:)
        raise OperatorError, :operator_already_assigned if current&.active?

        current&.update!(deleted_at: Time.current)
        assignment = AdminAssignment.create!(admin_user:, brand:, admin_role: role, status: :active)
        audit!(
          actor_context:, brand:, event_type: "admin.operator_assigned",
          target: admin_user, before: current, after: assignment, session:
        )
      end

      assignment
    end

    def self.update(actor_context:, brand:, admin_user_id:, role_name: nil, status: nil, session: nil)
      assignment = current_assignment(admin_user: target_admin(admin_user_id), brand:)
      raise OperatorError, :operator_unavailable if assignment.blank?
      unless RolePolicy.may_manage_assignment?(actor_context, assignment)
        raise OperatorError, :operator_management_forbidden
      end

      target_status = status.presence || assignment.status
      raise OperatorError, :invalid_status unless STATUSES.include?(target_status)
      target_role_name = role_name.presence || assignment.admin_role.name
      if target_role_name != assignment.admin_role.name && !RolePolicy.grantable?(actor_context, target_role_name)
        raise OperatorError, :invalid_role
      end
      if target_status == "active" && !RolePolicy.grantable?(actor_context, target_role_name)
        raise OperatorError, :operator_management_forbidden
      end

      role = AdminRole.kept.find_by(name: target_role_name)
      raise OperatorError, :invalid_role if role.blank?

      replacement = nil
      ActiveRecord::Base.transaction do
        before = assignment.dup
        if role == assignment.admin_role
          assignment.update!(status: target_status)
          replacement = assignment
        else
          assignment.update!(status: :revoked, deleted_at: Time.current)
          replacement = AdminAssignment.create!(
            admin_user: assignment.admin_user,
            brand:,
            admin_role: role,
            status: target_status
          )
        end
        audit!(
          actor_context:, brand:, event_type: "admin.operator_assignment_changed",
          target: assignment.admin_user, before:, after: replacement, session:
        )
      end

      replacement
    end

    def self.current_assignment(admin_user:, brand:)
      return if admin_user.blank?

      AdminAssignment.kept.includes(:admin_role).find_by(admin_user:, brand:)
    end
    private_class_method :current_assignment

    def self.target_admin(id)
      AdminUser.kept.find_by(id:)
    end
    private_class_method :target_admin

    def self.user_for_email(email)
      login = Identity::LoginIdentifier.call(email)
      return unless login&.kind == :email

      IdentityIdentifier.kept.email.where.not(verified_at: nil)
        .find_by(normalized_value: login.normalized_value)&.user
    end
    private_class_method :user_for_email

    def self.audit!(actor_context:, brand:, event_type:, target:, before:, after:, session:)
      SecurityEvent.create!(
        brand:,
        user: actor_context.admin_user.user,
        event_type:,
        severity: :warning,
        ip_address: session&.ip_address,
        user_agent: session&.user_agent,
        metadata: {
          admin_user_id: actor_context.admin_user.id,
          session_id: session&.id,
          target_admin_user_id: target.id,
          before_role: before&.admin_role&.name,
          before_status: before&.status,
          after_role: after.admin_role.name,
          after_status: after.status
        }.compact
      )
    end
    private_class_method :audit!
  end
end
