module Hq
  # Writes HQ's sensitive-read audit trail onto the existing SecurityEvent
  # infrastructure, mirroring Admin::ModerationAudit. Every privileged HQ read
  # (Member 360, security history, enforcement history) emits one of these so
  # "who looked up this member, and when" is itself answerable -- per
  # SECURITY-AND-RBAC.md #4, sensitive reads require auditing just like writes.
  class SensitiveReadAudit
    def self.record(admin_user:, brand:, user:, event_type:, extra: {})
      SecurityEvent.create!(
        brand:,
        user: admin_user.user,
        event_type:,
        severity: :info,
        metadata: {
          admin_user_id: admin_user.id,
          target_user_id: user.id
        }.merge(extra)
      )
    end
  end
end
