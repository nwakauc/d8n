module Admin
  # Writes moderation audit trails onto the existing SecurityEvent infrastructure.
  # Records who (admin + linked user), when (created_at), what (event_type + opaque
  # ids/status), and never any report content (reporter/resolution notes are
  # excluded on purpose). `has_note` records only that a note was supplied.
  class ModerationAudit
    def self.record(admin_user:, brand:, report:, event_type:, severity:, extra: {})
      SecurityEvent.create!(
        brand:,
        user: admin_user.user,
        event_type:,
        severity:,
        metadata: {
          admin_user_id: admin_user.id,
          report_id: report.id,
          reported_profile_id: report.reported_profile_id
        }.merge(extra)
      )
    end
  end
end
