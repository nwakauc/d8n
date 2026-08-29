module Hq
  # Writes HQ's sensitive-read audit trail onto the existing SecurityEvent
  # infrastructure, mirroring Admin::ModerationAudit. Every privileged HQ read
  # (Member 360, security history, Trust & Safety aggregates) emits one of these
  # so "who accessed this sensitive surface, and when" is answerable -- per
  # SECURITY-AND-RBAC.md #4, sensitive reads require auditing just like writes.
  class SensitiveReadAudit
    # `user` is the optional target member. Aggregate reads have no single
    # target and therefore record only the actor, brand, event type, and a
    # deliberately small set of non-sensitive filter metadata.
    def self.record(admin_user:, brand:, event_type:, user: nil, extra: {})
      metadata = { admin_user_id: admin_user.id }
      metadata[:target_user_id] = user.id if user.present?

      SecurityEvent.create!(
        brand:,
        user: admin_user.user,
        event_type:,
        severity: :info,
        metadata: metadata.merge(extra)
      )
    end
  end
end
