module Admin
  module RolePolicy
    NON_PRIVILEGED_ROLES = (Capabilities::ROLE_NAMES - Capabilities::PRIVILEGED_ROLE_NAMES).freeze

    module_function

    def grantable_role_names(context)
      case context.role.name
      when "founder"
        [ "super_admin", *NON_PRIVILEGED_ROLES ].freeze
      when "super_admin"
        NON_PRIVILEGED_ROLES
      else
        []
      end
    end

    def grantable?(context, role_name)
      grantable_role_names(context).include?(role_name.to_s)
    end

    def may_manage_assignment?(context, assignment)
      return false if assignment.admin_user_id == context.admin_user.id
      return false if assignment.admin_role.name == "founder"
      return false if assignment.admin_role.name == "super_admin" && context.role.name != "founder"

      true
    end
  end
end
