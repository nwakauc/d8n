module Admin
  module OperatorSerializer
    module_function

    def call(assignment:)
      admin_user = assignment.admin_user
      {
        admin_user_id: admin_user.id,
        user_id: admin_user.user_id,
        admin_status: admin_user.status,
        assignment_status: assignment.status,
        role: assignment.admin_role.name,
        effective_capabilities: assignment.active? ? assignment.admin_role.capabilities : [],
        mfa_enrolled: admin_user.admin_mfa_credentials.any? do |credential|
          credential.deleted_at.nil? && credential.active?
        end
      }
    end
  end
end
