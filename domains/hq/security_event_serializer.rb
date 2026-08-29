module Hq
  # Moderator-facing SecurityEvent representation. `metadata` is whatever the
  # writer chose to record (opaque ids/status per existing convention, e.g.
  # Admin::ModerationAudit) -- never raw message/report content.
  class SecurityEventSerializer
    def self.call(event:)
      {
        id: event.id,
        event_type: event.event_type,
        severity: event.severity,
        metadata: event.metadata,
        ip_address: event.ip_address,
        created_at: event.created_at.iso8601
      }
    end
  end
end
