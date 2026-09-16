module Trust
  # Overturns a manual trust deduction (Trust::RecordAdjustment). Never deletes
  # or mutates the original adjustment's points/reason/actor/timestamp -- only
  # records the appeal decision (`appeal_status: "overturned"`,
  # `resolved_by_admin_user`, `resolved_at`, a reversal reason in `metadata`).
  # Trust::Ledger already sums only rows where `counts_toward_score?` is true,
  # so the member's score reflects the reversal on the very next read with no
  # separate recalculation step and no compensating positive adjustment.
  class ReverseAdjustment
    Error = Class.new(StandardError) do
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    def self.call(admin_user:, brand:, trust_adjustment_id:, reason: nil)
      adjustment = TrustAdjustment.find_by(brand:, id: trust_adjustment_id)
      raise Error, :adjustment_unavailable if adjustment.blank?

      # Idempotent: reversing an already-overturned adjustment is a no-op that
      # returns the existing (already-reversed) row rather than raising or
      # re-applying anything.
      return adjustment if adjustment.overturned?

      adjustment.with_lock do
        adjustment.reload
        return adjustment if adjustment.overturned?

        adjustment.update!(
          appeal_status: :overturned,
          resolved_at: Time.current,
          resolved_by_admin_user: admin_user,
          metadata: adjustment.metadata.merge("reversal_reason" => normalize_reason(reason)).compact
        )
      end

      record_audit!(admin_user:, adjustment:)
      adjustment
    end

    def self.normalize_reason(reason)
      text = reason.to_s.strip
      raise Error, :invalid_reason if text.length > 500

      text.presence
    end
    private_class_method :normalize_reason

    def self.record_audit!(admin_user:, adjustment:)
      SecurityEvent.create!(
        brand: adjustment.brand,
        user: admin_user.user,
        event_type: "admin.trust_adjustment_reversed",
        severity: :info,
        metadata: {
          admin_user_id: admin_user.id,
          target_user_id: adjustment.user_id,
          trust_adjustment_id: adjustment.id,
          points: adjustment.points,
          has_reversal_reason: adjustment.metadata["reversal_reason"].present?
        }
      )
    end
    private_class_method :record_audit!
  end
end
