module Api
  module V1
    module Admin
      # Manual, audited trust-point deductions (ADR 0025). There is no
      # automatic negative scoring anywhere in this system — same as Date9ja
      # — every deduction is a deliberate admin action with its own reason.
      class TrustAdjustmentsController < BaseController
        requires_admin_capability ::Admin::Capabilities::TRUST_ADJUSTMENTS_MANAGE, only: %i[index create]
        requires_admin_capability ::Admin::Capabilities::TRUST_ADJUSTMENTS_REVERSE, only: :reverse

        CODE_STATUS = {
          invalid_adjustment_points: :unprocessable_entity,
          reason_code_required: :unprocessable_entity,
          idempotency_key_required: :unprocessable_entity,
          user_unavailable: :not_found,
          adjustment_unavailable: :not_found,
          invalid_reason: :unprocessable_entity
        }.freeze
        QUEUE_LIMIT = 100

        def index
          adjustments = TrustAdjustment.where(brand: Current.brand, user_id: target_profile.user_id)
            .order(created_at: :desc).limit(QUEUE_LIMIT)

          render json: { trust_adjustments: adjustments.map { |adjustment| payload(adjustment) } }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "user_unavailable" }, status: :not_found
        end

        def create
          adjustment = Trust::RecordAdjustment.call(
            admin_user: Current.admin_user, brand: Current.brand, user: target_profile.user,
            points: params.require(:points), reason_code: params.require(:reason_code),
            idempotency_key: params.require(:idempotency_key), note: params[:note]
          )

          render json: { trust_adjustment: payload(adjustment) }, status: :created
        rescue ActiveRecord::RecordNotFound
          render json: { error: "user_unavailable" }, status: :not_found
        rescue Trust::RecordAdjustment::Error => e
          render json: { error: e.code }, status: CODE_STATUS.fetch(e.code)
        end

        def reverse
          adjustment = Trust::ReverseAdjustment.call(
            admin_user: Current.admin_user, brand: Current.brand,
            trust_adjustment_id: params[:id], reason: params[:reason]
          )

          render json: { trust_adjustment: payload(adjustment) }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "user_unavailable" }, status: :not_found
        rescue Trust::ReverseAdjustment::Error => e
          render json: { error: e.code }, status: CODE_STATUS.fetch(e.code)
        end

        private

        def target_profile
          @target_profile ||= Profile.kept.where(brand: Current.brand).find_by!(public_id: params.require(:profile_id))
        end

        def payload(adjustment)
          {
            id: adjustment.id,
            profile_id: target_profile.public_id,
            points: adjustment.points,
            reason_code: adjustment.reason_code,
            appeal_status: adjustment.appeal_status,
            occurred_at: adjustment.occurred_at&.iso8601
          }
        end
      end
    end
  end
end
