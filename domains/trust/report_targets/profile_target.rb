module Trust
  module ReportTargets
    # A plain profile report: the target IS the responsible person. Deliberately
    # independent of blocking and of the target's visibility/moderation state —
    # this preserves the original TS-02 behavior (a report is an audit signal, not
    # an access gate) so the legacy profile-report endpoint is unchanged. No
    # content snapshot: the reported_profile row is itself the evidence.
    class ProfileTarget
      def self.resolve(brand:, viewer:, target_public_id:)
        target = brand.profiles.kept.find_by(public_id: target_public_id)
        raise AccessError, :target_unavailable if target.blank? || target.id == viewer.id

        Resolution.new(target_type: "profile", target_id: nil, reported_profile: target, evidence: {})
      end
    end
  end
end
