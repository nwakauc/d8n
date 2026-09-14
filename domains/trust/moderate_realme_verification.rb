module Trust
  # Applies the manual review decision for a member-submitted RealMe
  # verification (selfie/liveness-video/government-ID), mirroring
  # Trust::ModerateProfilePhoto's shape. Automated face/document matching is
  # explicitly deferred (ADR 0032) — this is the human-review path: the admin
  # looks at `evidence` and decides.
  class ModerateRealmeVerification
    Error = Class.new(StandardError) do
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    DECISIONS = %w[approved rejected resubmission_requested].freeze

    def self.call(admin_user:, brand:, assertion_id:, decision:, note: nil)
      target = decision.to_s
      raise Error, :invalid_realme_verification_decision unless DECISIONS.include?(target)

      assertion = VerificationAssertion.where(brand:, source_type: "member_submission").find_by(id: assertion_id)
      raise Error, :realme_verification_unavailable if assertion.blank?

      transitioned = false
      VerificationAssertion.transaction do
        assertion.lock!
        raise Error, :realme_verification_conflict unless assertion.status == "pending"

        metadata = assertion.metadata.merge("review_note" => note.presence).compact
        assertion.update!(
          status: target,
          reviewed_at: Time.current,
          reviewer_source_id: "d8n_admin:#{admin_user.id}",
          metadata:
        )
        record_audit!(admin_user:, brand:, assertion:, decision: target)
        transitioned = true
      end

      Result.new(assertion:, transitioned:)
    end

    Result = Data.define(:assertion, :transitioned)

    def self.record_audit!(admin_user:, brand:, assertion:, decision:)
      SecurityEvent.create!(
        brand:,
        user: admin_user.user,
        event_type: "admin.realme_verification_moderated",
        severity: decision == "approved" ? :info : :warning,
        metadata: {
          admin_user_id: admin_user.id,
          target_user_id: assertion.user_id,
          verification_assertion_id: assertion.id,
          check_type: assertion.check_type,
          decision:,
          reason_code: "manual_moderation_decision"
        }
      )
    end
    private_class_method :record_audit!
  end
end
