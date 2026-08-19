module Trust
  # Backward-compatibility shim for the original profile-report endpoint
  # (POST /profiles/:id/report). It now delegates to the unified Trust::FileReport
  # with a `profile` target, preserving the exact legacy contract: same idempotent
  # behavior, same brand isolation, same independence from blocking/visibility, and
  # the same neutral `profile_unavailable` code the endpoint has always returned
  # (FileReport speaks the generic `target_unavailable`; we translate it back here
  # so existing clients see no change).
  class ReportProfile
    Result = Data.define(:report, :created)

    def self.call(user:, brand:, target_public_id:, reason:, note: nil)
      result = FileReport.call(
        user:, brand:,
        target_type: "profile", target_id: target_public_id,
        reason:, details: note
      )
      Result.new(report: result.report, created: result.created)
    rescue AccessError => e
      raise AccessError, :profile_unavailable if e.code == :target_unavailable

      raise
    end
  end
end
