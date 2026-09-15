module Api
  module V1
    module Admin
      # Moderator "hide from discovery" (create) / "unhide" (destroy) — distinct
      # from suspend/ban (SuspensionsController): no account lock, no session
      # revocation. Authorization + brand come from BaseController.
      class DiscoveryRestrictionsController < BaseController
        requires_admin_capability ::Admin::Capabilities::DISCOVERY_RESTRICTIONS_MANAGE

        CODE_STATUS = {
          profile_unavailable: :not_found,
          invalid_reason: :unprocessable_entity,
          invalid_note: :unprocessable_entity,
          already_restricted: :conflict,
          not_restricted: :conflict
        }.freeze

        rescue_from ::Admin::ModerationError, with: :render_moderation_error

        def create
          profile = ::Admin::RestrictProfileDiscovery.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            profile_public_id: params[:profile_id],
            reason: params[:reason],
            note: params[:note]
          )

          render json: { profile: payload(profile) }, status: :created
        end

        def destroy
          profile = ::Admin::LiftProfileDiscoveryRestriction.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            profile_public_id: params[:profile_id]
          )

          render json: { profile: payload(profile) }
        end

        private

        def payload(profile)
          {
            profile_id: profile.public_id,
            discovery_restricted: profile.discovery_restricted_at.present?,
            discovery_restricted_at: profile.discovery_restricted_at&.iso8601,
            discovery_restriction_reason: profile.discovery_restriction_reason,
            discovery_restriction_note: profile.discovery_restriction_note,
            discovery_restricted_by_admin_user_id: profile.discovery_restricted_by_admin_user_id
          }
        end

        def render_moderation_error(error)
          render json: { error: error.code }, status: CODE_STATUS.fetch(error.code, :unprocessable_entity)
        end
      end
    end
  end
end
