module Trust
  # The single policy surface for "what may be reported, and for which reasons".
  #
  # Reporting V2 keeps ONE reusable reason taxonomy (Report.reasons) rather than a
  # separate list per target type. This object is the seam that lets us later
  # narrow the visible reasons for a given target without touching resolvers,
  # controllers, or the schema: today every target permits the full taxonomy, so
  # the frontend can show a tailored subset while the backend stays permissive
  # (rejecting a genuine report because a reason felt "off-type" is worse than
  # allowing it). Restricting a target later is a one-line change here.
  module ReportPolicy
    # Reasons currently offered for each target type. `Report.reasons.keys` means
    # "the whole taxonomy". Kept explicit so the intent is visible and a future
    # per-target restriction has an obvious home.
    def self.reasons_for(target_type)
      return [] unless Report.target_types.key?(target_type.to_s)

      Report.reasons.keys
    end

    def self.reason_allowed?(target_type:, reason:)
      reasons_for(target_type).include?(reason.to_s)
    end
  end
end
