module Admin
  # Applies a narrow moderation lifecycle transition to a report and records the
  # decision. Only `status` and an optional short `resolution_note` may change;
  # reporter, target, brand, reason, and timestamps are never touched here.
  #
  # Lifecycle (server-enforced):
  #   open      -> reviewing | dismissed
  #   reviewing -> actioned  | dismissed | open   (open = release back to the queue)
  #   actioned / dismissed   -> terminal
  #
  # `actioned` means "resolved as warranting action"; it does NOT suspend or ban
  # the account. Account enforcement is a separate capability (TS-04) that will
  # attach here later. A transition out of a terminal state (e.g. another moderator
  # already resolved it) is a conflict, not an invalid request.
  class TransitionReport
    ALLOWED = {
      "open" => %w[reviewing dismissed],
      "reviewing" => %w[actioned dismissed open]
    }.freeze
    TERMINAL = %w[actioned dismissed].freeze

    def self.call(admin_user:, brand:, report_id:, target_status:, note: nil)
      target = target_status.to_s
      raise ModerationError, :invalid_status unless Report.statuses.key?(target)
      raise ModerationError, :invalid_note if note.present? && note.to_s.length > 2_000

      report = Report.where(brand:).find_by(id: report_id)
      raise ModerationError, :report_unavailable if report.blank?

      transition!(report:, admin_user:, target:, note:)
      record(admin_user:, brand:, report:, target:, note:)
      report
    end

    def self.transition!(report:, admin_user:, target:, note:)
      report.with_lock do
        current = report.status
        raise ModerationError, :report_conflict if TERMINAL.include?(current)
        raise ModerationError, :invalid_transition unless ALLOWED.fetch(current, []).include?(target)

        attributes = { status: target, reviewed_by: admin_user, reviewed_at: Time.current }
        attributes[:resolution_note] = note if note.present?
        report.update!(attributes)
      end
    end
    private_class_method :transition!

    def self.record(admin_user:, brand:, report:, target:, note:)
      ModerationAudit.record(
        admin_user:, brand:, report:,
        event_type: "admin.report_transitioned",
        severity: target == "actioned" ? :warning : :info,
        extra: { to_status: target, has_note: note.present? }
      )
    end
    private_class_method :record
  end
end
