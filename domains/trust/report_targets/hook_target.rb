module Trust
  module ReportTargets
    # A specific 🔥 Hook opener. Only the RECIPIENT may report a Hook, and only one
    # addressed to them: the lookup is scoped to (brand, recipient == viewer), so a
    # Hook sent to someone else is indistinguishable from one that never existed.
    # Status is intentionally not gated — a recipient can report a Hook that is
    # pending, accepted, declined, or expired, because they legitimately received
    # the opener in every case. The responsible profile is the sender, derived from
    # the Hook.
    #
    # Evidence snapshots the opener text and status so the flagged opener survives
    # even if the Hook is later swept/deleted. Opener text lives only on the report
    # row, never in logs or SecurityEvent metadata (see ADR 0018).
    class HookTarget
      def self.resolve(brand:, viewer:, target_public_id:)
        hook = Hook.kept.where(brand:, recipient_profile: viewer).find_by(public_id: target_public_id)
        sender = hook&.sender_profile
        raise AccessError, :target_unavailable if hook.blank? || sender.blank? || sender.id == viewer.id

        Resolution.new(
          target_type: "hook",
          target_id: hook.id,
          reported_profile: sender,
          evidence: {
            "hook_public_id" => hook.public_id,
            "sender_profile_id" => sender.id,
            "hook_status" => hook.status,
            "opener" => hook.message,
            "content_created_at" => hook.created_at.iso8601
          }
        )
      end
    end
  end
end
