module Trust
  # Admin-applied negative trust entry (ADR 0025). Mirrors Date9ja's own
  # `TrustScore::Ledger.deduct!` exactly: there is no automatic negative
  # scoring anywhere in Date9ja (a suspension, an upheld report, etc. does
  # NOT by itself dock trust) — every deduction is a deliberate, audited,
  # freeform admin action with its own reason and point amount. This is that
  # same manual path for D8N, not a new automatic-penalty system.
  class RecordAdjustment
    Error = Class.new(StandardError) do
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    def self.call(admin_user:, brand:, user:, points:, reason_code:, idempotency_key:, note: nil)
      points = points.to_i
      raise Error, :invalid_adjustment_points unless points.negative?
      raise Error, :reason_code_required if reason_code.blank?
      raise Error, :idempotency_key_required if idempotency_key.blank?

      existing = TrustAdjustment.find_by(brand:, idempotency_key:)
      return existing if existing

      adjustment = TrustAdjustment.create!(
        brand:, user:, points:, reason_code:, idempotency_key:,
        occurred_at: Time.current, actor_admin_user: admin_user,
        metadata: { "note" => note }.compact
      )
      record_audit!(admin_user:, brand:, adjustment:)
      adjustment
    rescue ActiveRecord::RecordNotUnique
      TrustAdjustment.find_by!(brand:, idempotency_key:)
    end

    def self.record_audit!(admin_user:, brand:, adjustment:)
      SecurityEvent.create!(
        brand:,
        user: admin_user.user,
        event_type: "admin.trust_adjustment_applied",
        severity: :warning,
        metadata: {
          admin_user_id: admin_user.id,
          target_user_id: adjustment.user_id,
          trust_adjustment_id: adjustment.id,
          points: adjustment.points,
          reason_code: adjustment.reason_code
        }
      )
    end
    private_class_method :record_audit!
  end
end
