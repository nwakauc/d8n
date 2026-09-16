module Api
  module V1
    module Admin
      class RealmeVerificationsController < BaseController
        requires_admin_capability ::Admin::Capabilities::REALME_VERIFICATIONS_MODERATE

        CODE_STATUS = {
          realme_verification_unavailable: :not_found,
          invalid_realme_verification_decision: :unprocessable_entity,
          realme_verification_conflict: :conflict
        }.freeze
        QUEUE_LIMIT = 100
        EVIDENCE_URL_EXPIRES_IN = 5.minutes

        before_action :set_active_storage_url_options, only: :index

        # The manual-review queue (ADR 0034): every pending member-submitted
        # assertion for this brand, oldest first. This is the only way for a
        # moderator to discover what is awaiting a decision.
        def index
          assertions = VerificationAssertion.where(
            brand: Current.brand, source_type: "member_submission", status: "pending"
          ).includes(evidence_attachment: :blob).order(:submitted_at, :id).limit(QUEUE_LIMIT)

          render json: { assertions: assertions.map { |assertion| queue_payload(assertion) } }
        end

        def update
          result = Trust::ModerateRealmeVerification.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            assertion_id: params[:id],
            decision: params[:status],
            note: params[:note]
          )

          render json: { assertion: assertion_payload(result.assertion), transitioned: result.transitioned }
        rescue Trust::ModerateRealmeVerification::Error => e
          render json: { error: e.code }, status: CODE_STATUS.fetch(e.code)
        end

        private

        def assertion_payload(assertion)
          {
            id: assertion.id,
            user_id: assertion.user_id,
            check_type: assertion.check_type,
            status: assertion.status,
            reviewed_at: assertion.reviewed_at&.iso8601
          }
        end

        def queue_payload(assertion)
          {
            id: assertion.id,
            user_id: assertion.user_id,
            check_type: assertion.check_type,
            submitted_at: assertion.submitted_at&.iso8601,
            evidence: evidence_payload(assertion)
          }
        end

        # Short-lived, signed access to the raw evidence for review — this is
        # the ONLY reader of it besides the submitting member; it is never
        # delivered to any other member.
        def evidence_payload(assertion)
          return unless assertion.evidence.attached?

          {
            content_type: assertion.evidence.blob.content_type,
            url: assertion.evidence.url(expires_in: EVIDENCE_URL_EXPIRES_IN),
            url_expires_in: EVIDENCE_URL_EXPIRES_IN.to_i
          }
        end
      end
    end
  end
end
