module Trust
  # The derived trust score: a PURE, rebuildable function of TrustEvent/
  # TrustAdjustment rows (ADR 0025) — never a stored mutable counter, so it
  # can never drift and is always safe to recompute from the ledger.
  class Ledger
    def self.score(user:, brand:)
      return 0 if user.blank? || brand.blank?

      # Matches Date9ja's own Ledger.rebuild! ([total, 0].max) — a member's
      # visible score never reads negative even if adjustments outweigh events.
      [ event_points(user:, brand:) + adjustment_points(user:, brand:), 0 ].max
    end

    # Ordered (most recent first) explanation entries for the "score plus
    # explanation" surface (DECISIONS.md). An overturned adjustment is
    # included for transparency but flagged `applies: false` — it stays in
    # the audit trail without silently vanishing from the member's own view.
    def self.breakdown(user:, brand:)
      return [] if user.blank? || brand.blank?

      events = TrustEvent.where(brand:, user:).map do |event|
        {
          kind: "event", type: event.event_type, label: event_label(event),
          points: event.points, applies: true, occurred_at: event.occurred_at
        }
      end

      adjustments = TrustAdjustment.where(brand:, user:).map do |adjustment|
        {
          kind: "adjustment", type: adjustment.reason_code, label: Trust::EventLabels.for_adjustment(adjustment.reason_code),
          points: adjustment.points, applies: adjustment.counts_toward_score?, occurred_at: adjustment.occurred_at
        }
      end

      (events + adjustments).sort_by { |entry| entry.fetch(:occurred_at) }.reverse
    end

    # A primary-photo award carries `metadata["primary"] => true` (set at
    # award time — see Trust::ModerateProfilePhoto) so the breakdown can say
    # "primary" rather than the generic photo label, matching Date9ja's own
    # distinct primary/non-primary labels without a second event_type.
    def self.event_label(event)
      return "Approved primary photo" if event.event_type == Trust::Date9jaSchedule::PHOTO_EVENT_TYPE && event.metadata["primary"]

      Trust::EventLabels.for_event(event.event_type)
    end
    private_class_method :event_label

    def self.event_points(user:, brand:)
      TrustEvent.where(brand:, user:).sum(:points)
    end
    private_class_method :event_points

    def self.adjustment_points(user:, brand:)
      TrustAdjustment.where(brand:, user:, appeal_status: %w[not_requested pending upheld]).sum(:points)
    end
    private_class_method :adjustment_points
  end
end
