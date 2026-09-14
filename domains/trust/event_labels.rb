module Trust
  # Human-readable labels for the trust-score "explanation" breakdown
  # (ADR 0025 / DECISIONS.md "score plus explanation"). Keys match the real
  # `event_type` strings Date9ja's own trust ledger uses (verified against
  # the Date9ja source — see Trust::Date9jaSchedule) so imported history and
  # newly-awarded live events share identical labels. Anything else (a value
  # this map hasn't been told about yet) falls back to a generic
  # humanization rather than breaking the breakdown.
  module EventLabels
    EVENT_TYPES = {
      "realme_email_approved" => "Email verification",
      "realme_phone_approved" => "Phone verification",
      "realme_selfie_approved" => "Selfie verification",
      "realme_video_approved" => "Video verification",
      "realme_government_id_approved" => "Government ID verification",
      "profile_photo_approved" => "Approved profile photo",
      "profile_video_approved" => "Approved profile video",
      "profile_completed" => "Complete profile",
      "compatibility_completed" => "Compatibility answers",
      "membership_one_month" => "One month membership",
      "membership_three_months" => "Three months membership",
      "membership_six_months" => "Six months membership",
      "membership_one_year" => "One year membership"
    }.freeze

    module_function

    def for_event(event_type)
      EVENT_TYPES.fetch(event_type.to_s) { event_type.to_s.humanize }
    end

    # Adjustments already carry an operator-authored reason_code; this only
    # normalizes its display, it never invents a stronger claim.
    def for_adjustment(reason_code)
      reason_code.to_s.humanize
    end
  end
end
