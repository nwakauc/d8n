module Admin
  # Audit trail for enforcement actions on the existing SecurityEvent
  # infrastructure. Records who (admin + linked user), what (event + opaque ids),
  # and when. Never records session tokens or the reason text — only `has_reason`.
  class EnforcementAudit
    def self.record(admin_user:, enforcement:, event_type:, severity:, extra: {})
      SecurityEvent.create!(
        brand: enforcement.brand,
        user: admin_user.user,
        event_type:,
        severity:,
        metadata: {
          admin_user_id: admin_user.id,
          enforcement_id: enforcement.id,
          target_user_id: enforcement.user_id,
          target_profile_id: enforcement.profile_id,
          report_id: enforcement.report_id,
          has_reason: enforcement.reason.present?,
          has_note: enforcement.note.present?,
          kind: enforcement.kind
        }.merge(extra)
      )
    end
  end
end
