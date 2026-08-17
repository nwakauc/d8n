module Trust
  # Files a safety report from the current member against another current-brand
  # profile. Idempotent per open report, brand-isolated, and independent of
  # blocking and of the target's visibility/moderation state — reporting is an
  # audit signal for administrators, not an approval gate.
  class ReportProfile
    Result = Data.define(:report, :created)

    def self.call(user:, brand:, target_public_id:, reason:, note: nil)
      viewer = Matching::ProfileParticipant.match_member!(user:, brand:)
      reason_key = normalize_reason(reason)
      target = brand.profiles.kept.find_by(public_id: target_public_id)
      raise AccessError, :profile_unavailable if target.blank? || target.id == viewer.id

      report, created = find_or_file(brand:, viewer:, target:, reason: reason_key, note:)
      record_event(brand:, user:, viewer:, target:, reason: reason_key) if created

      Result.new(report:, created:)
    end

    def self.find_or_file(brand:, viewer:, target:, reason:, note:)
      existing = Report.open_reports.find_by(brand:, reporter_profile: viewer, reported_profile: target)
      return [ existing, false ] if existing.present?

      report = Report.create!(
        brand:, reporter_profile: viewer, reported_profile: target, reason:, note: note.presence
      )
      [ report, true ]
    rescue ActiveRecord::RecordNotUnique
      # Lost a race with a concurrent report; the other one is authoritative.
      [ Report.open_reports.find_by!(brand:, reporter_profile: viewer, reported_profile: target), false ]
    end
    private_class_method :find_or_file

    def self.normalize_reason(reason)
      key = reason.to_s
      raise AccessError, :invalid_reason unless Report.reasons.key?(key)

      key
    end
    private_class_method :normalize_reason

    def self.record_event(brand:, user:, viewer:, target:, reason:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "trust.profile_reported",
        severity: :warning,
        metadata: {
          reporter_profile_id: viewer.id,
          reported_profile_id: target.id,
          reason:
        }
      )
    end
    private_class_method :record_event
  end
end
