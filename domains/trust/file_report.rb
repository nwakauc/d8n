module Trust
  # The single entry point for filing any safety report — profile, message, photo,
  # or Hook. It owns the invariants that are identical across every target type:
  #
  #   * the reporter is the AUTHENTICATED current-brand member (never the body);
  #   * the reason is a known code permitted for the target type;
  #   * the target type is known, and its resolver authorizes access and derives
  #     the responsible profile + evidence entirely server-side;
  #   * duplicate suppression: at most one OPEN report per (reporter, target),
  #     idempotent under concurrency (unique index + retry);
  #   * a content-free SecurityEvent audit signal on first creation;
  #   * an optional atomic "report and block" of the responsible profile.
  #
  # Per-target authorization/evidence lives in Trust::ReportTargets::* — this class
  # stays target-agnostic so a new target type is one resolver, not a rewrite.
  class FileReport
    Result = Data.define(:report, :created, :blocked)

    def self.call(user:, brand:, target_type:, target_id:, reason:, details: nil, block: false)
      viewer = Matching::ProfileParticipant.match_member!(user:, brand:)
      resolver = ReportTargets.resolver_for(target_type)
      raise AccessError, :invalid_target_type if resolver.nil?

      reason_key = normalize_reason(target_type:, reason:)
      resolution = resolver.resolve(brand:, viewer:, target_public_id: target_id)
      report, created = find_or_file(brand:, viewer:, resolution:, reason: reason_key, details:)
      record_event(brand:, user:, viewer:, resolution:, reason: reason_key) if created

      blocked = block ? block_responsible(user:, brand:, resolution:) : false
      Result.new(report:, created:, blocked:)
    end

    # Idempotent per open (reporter, target). A lost race on the unique index
    # resolves to the winning open report, so simultaneous double-submits never
    # create two moderation records.
    def self.find_or_file(brand:, viewer:, resolution:, reason:, details:)
      attrs = {
        brand:, reporter_profile: viewer, reported_profile: resolution.reported_profile,
        target_type: resolution.target_type, target_id: resolution.target_id
      }
      existing = Report.open_reports.find_by(attrs)
      return [ existing, false ] if existing.present?

      report = Report.create!(**attrs, reason:, note: normalize_details(details), evidence: resolution.evidence)
      [ report, true ]
    rescue ActiveRecord::RecordNotUnique
      [ Report.open_reports.find_by!(attrs), false ]
    end
    private_class_method :find_or_file

    def self.normalize_reason(target_type:, reason:)
      key = reason.to_s
      raise AccessError, :invalid_reason unless Report.reasons.key?(key)
      raise AccessError, :invalid_reason unless ReportPolicy.reason_allowed?(target_type:, reason: key)

      key
    end
    private_class_method :normalize_reason

    # Optional reporter context: untrusted, length-bounded, NFC-normalized, stored
    # as plain text (never rendered as HTML by the API), and blank -> nil so it
    # never masquerades as evidence. Reused for the legacy `note` column.
    def self.normalize_details(details)
      normalized = details.to_s.unicode_normalize(:nfc).strip
      normalized = normalized[0, Report::NOTE_MAX_LENGTH] if normalized.length > Report::NOTE_MAX_LENGTH
      normalized.presence
    end
    private_class_method :normalize_details

    # Content-free: identifies records only. Target/opener/message/photo content is
    # NEVER placed here — it lives solely in the report's evidence column.
    def self.record_event(brand:, user:, viewer:, resolution:, reason:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "trust.report_created",
        severity: :warning,
        metadata: {
          reporter_profile_id: viewer.id,
          reported_profile_id: resolution.reported_profile.id,
          target_type: resolution.target_type,
          target_id: resolution.target_id,
          reason:
        }
      )
    end
    private_class_method :record_event

    # "Report and block": the report is already persisted; blocking the responsible
    # profile is a separate, idempotent action. Both are individually idempotent,
    # so a partial failure is safely retryable by the client.
    def self.block_responsible(user:, brand:, resolution:)
      Trust::BlockProfile.call(user:, brand:, target_public_id: resolution.reported_profile.public_id)
      true
    end
    private_class_method :block_responsible
  end
end
