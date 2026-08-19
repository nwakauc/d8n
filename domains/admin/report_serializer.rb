module Admin
  # Moderator-facing report representation (used for both queue and detail). Data
  # minimization: parties are identified only by public id + display name — no
  # email, phone, credentials, session, private location, or media. Profiles that
  # were since removed still resolve (reports are retained) and serialize safely.
  class ReportSerializer
    def self.call(report:)
      {
        id: report.id,
        status: report.status,
        reason: report.reason,
        target_type: report.target_type,
        # Minimal, immutable moderation evidence captured at file time (message/
        # opener text, photo identity). Survives later deletion of the target;
        # moderator-only and never exposed to the reporter.
        evidence: report.evidence,
        reporter: party(report.reporter_profile),
        # The responsible person, derived server-side from the target (message
        # sender / photo owner / Hook sender), so a moderator always knows who
        # created the reported content.
        reported: party(report.reported_profile),
        note: report.note,
        resolution_note: report.resolution_note,
        reviewed_by_admin_user_id: report.reviewed_by_admin_user_id,
        reviewed_at: report.reviewed_at&.iso8601,
        created_at: report.created_at.iso8601,
        updated_at: report.updated_at.iso8601
      }
    end

    def self.party(profile)
      return if profile.blank?

      { id: profile.public_id, display_name: profile.display_name }
    end
    private_class_method :party
  end
end
