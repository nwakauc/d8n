module Admin
  # Loads one report for moderation, scoped to the moderator's brand, and records
  # a sensitive-read audit event. Cross-brand and unknown ids are indistinguishable
  # (`report_unavailable`). Only opaque ids are audited — never report content.
  class ReportDetail
    def self.call(admin_user:, brand:, report_id:)
      report = Report.where(brand:).includes(:reporter_profile, :reported_profile, :reviewed_by).find_by(id: report_id)
      raise ModerationError, :report_unavailable if report.blank?

      ModerationAudit.record(
        admin_user:, brand:, report:,
        event_type: "admin.report_viewed", severity: :info
      )
      report
    end
  end
end
