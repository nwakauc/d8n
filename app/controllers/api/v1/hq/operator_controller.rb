module Api
  module V1
    module Hq
      class OperatorController < BaseController
        skip_before_action :require_admin_mfa!

        def show
          context = Current.admin_context
          credential = Current.admin_user.admin_mfa_credentials.kept.active.first
          pending = Current.admin_user.admin_mfa_credentials.kept.pending.exists?

          render json: {
            operator: {
              admin_user_id: Current.admin_user.id,
              user_id: Current.user.id,
              status: Current.admin_user.status,
              current_brand: Current.brand.slug,
              role: context.role.name,
              effective_capabilities: context.capabilities,
              grantable_roles: ::Admin::RolePolicy.grantable_role_names(context),
              brand_assignments: brand_assignments,
              mfa: {
                state: credential.present? ? "active" : (pending ? "pending" : "not_enrolled"),
                required: true,
                verified: Current.session.admin_mfa_verified_for?(Current.admin_user),
                recovery_codes_remaining: credential&.recovery_code_digests&.length
              }
            }
          }
        end

        private

        def brand_assignments
          AdminAssignment.kept.active.includes(:brand, :admin_role)
            .references(:brand).where(admin_user: Current.admin_user).order("brands.slug").map do |assignment|
            {
              brand: assignment.brand.slug,
              role: assignment.admin_role.name,
              effective_capabilities: assignment.admin_role.capabilities
            }
          end
        end
      end
    end
  end
end
