module Api
  module V1
    module Admin
      # Authorized correction of a member's canonical gender / interested_in
      # (looking_for) values -- writes the same canonical D8N representation
      # discovery/matching already reads live. Authorization + brand come from
      # BaseController.
      class IdentityCorrectionsController < BaseController
        requires_admin_capability ::Admin::Capabilities::IDENTITY_CORRECTION_MANAGE

        CODE_STATUS = {
          profile_unavailable: :not_found,
          invalid_field: :unprocessable_entity,
          invalid_value: :unprocessable_entity,
          invalid_reason: :unprocessable_entity,
          invalid_note: :unprocessable_entity
        }.freeze

        rescue_from ::Admin::ModerationError, with: :render_moderation_error

        def create
          correction = ::Admin::CorrectProfileIdentity.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            profile_public_id: params[:profile_id],
            field: params[:field],
            value: params[:value],
            reason: params[:reason],
            note: params[:note]
          )

          render json: { correction: payload(correction) }, status: :created
        end

        def index
          profile = Current.brand.profiles.kept.find_by(public_id: params[:profile_id])
          return render json: { error: "profile_unavailable" }, status: :not_found if profile.blank?

          corrections = AdminIdentityCorrection.where(brand: Current.brand, profile:).order(created_at: :desc).limit(100)
          render json: { identity_corrections: corrections.map { |c| payload(c) } }
        end

        private

        def payload(correction)
          {
            id: correction.id,
            profile_id: correction.profile.public_id,
            field: correction.field,
            previous_value: correction.previous_value["value"],
            new_value: correction.new_value["value"],
            reason: correction.reason,
            note: correction.note,
            admin_user_id: correction.admin_user_id,
            created_at: correction.created_at.iso8601
          }
        end

        def render_moderation_error(error)
          render json: { error: error.code }, status: CODE_STATUS.fetch(error.code, :unprocessable_entity)
        end
      end
    end
  end
end
