module Admin
  # Moderator-facing enforcement representation. `state` is the enforcement's own
  # status (active vs reverted), distinct from account/report status. Identifies the
  # target only by profile public id — no email, phone, credentials, or session.
  class EnforcementSerializer
    def self.call(enforcement:)
      {
        id: enforcement.id,
        state: enforcement.reverted? ? "reverted" : "active",
        kind: enforcement.kind,
        profile_id: enforcement.profile&.public_id,
        reason: enforcement.reason,
        note: enforcement.note,
        report_id: enforcement.report_id,
        admin_user_id: enforcement.admin_user_id,
        reverted_by_admin_user_id: enforcement.reverted_by_admin_user_id,
        created_at: enforcement.created_at.iso8601,
        reverted_at: enforcement.reverted_at&.iso8601
      }
    end
  end
end
