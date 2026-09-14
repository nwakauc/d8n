module Trust
  # Live, going-forward trust-point awarding (ADR 0025 architecture; the
  # actual point values come from Trust::Date9jaSchedule). Mirrors Date9ja's
  # own `TrustScore::Ledger.award!`: idempotent on `idempotency_key` — calling
  # this twice for the same key (e.g. a retried request) creates exactly one
  # TrustEvent, never a duplicate award.
  class AwardEvent
    def self.call(user:, brand:, event_type:, points:, idempotency_key:, profile: nil, source: nil, metadata: {})
      return if user.blank? || brand.blank?

      TrustEvent.create!(
        brand:, user:, profile:,
        event_type:, points:, idempotency_key:,
        source_type: source&.class&.name, source_id: source&.id,
        occurred_at: Time.current, metadata:
      )
    rescue ActiveRecord::RecordNotUnique
      TrustEvent.find_by(brand:, idempotency_key:)
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors.of_kind?(:idempotency_key, :taken)

      TrustEvent.find_by(brand:, idempotency_key:)
    end
  end
end
