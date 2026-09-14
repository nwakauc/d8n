module Trust
  # Date9ja's real live trust-award point table (ADR 0025: "point values are
  # migration parity, not new rules"). Verified directly against the Date9ja
  # source (`TrustScore::Ledger`/`Backfill`/`ActivityAwarder`,
  # `Realme::VerificationCheckService#award_trust_for_approval!`,
  # `TrustScoreMembershipMilestonesJob`) — not invented. Event-type strings
  # match exactly so imported history and newly-awarded live events share one
  # vocabulary (see Trust::EventLabels).
  #
  # `profile_video_approved` (+40 in Date9ja) is deliberately NOT wired to a
  # live award here — D8N has no profile-video moderation/approval action yet
  # (Trust::ModerateProfilePhoto has no video counterpart), so there is no
  # honest hook point. Add it when that feature ships.
  module Date9jaSchedule
    REALME_CHECK_POINTS = {
      "selfie" => { points: 100, event_type: "realme_selfie_approved" },
      "video" => { points: 200, event_type: "realme_video_approved" },
      "government_id" => { points: 500, event_type: "realme_government_id_approved" }
    }.freeze

    IDENTIFIER_VERIFICATION_POINTS = {
      "email" => { points: 25, event_type: "realme_email_approved" },
      "phone" => { points: 50, event_type: "realme_phone_approved" }
    }.freeze

    PHOTO_PRIMARY_POINTS = 25
    PHOTO_OTHER_POINTS = 15
    PHOTO_EVENT_TYPE = "profile_photo_approved".freeze

    PROFILE_COMPLETED_POINTS = 110
    COMPATIBILITY_COMPLETED_POINTS = 40

    MEMBERSHIP_MILESTONES = [
      { key: "one_month", duration: 1.month, points: 20 },
      { key: "three_months", duration: 3.months, points: 50 },
      { key: "six_months", duration: 6.months, points: 80 },
      { key: "one_year", duration: 1.year, points: 150 }
    ].freeze

    module_function

    def for_realme_check(check_type) = REALME_CHECK_POINTS[check_type.to_s]
    def for_identifier_verification(kind) = IDENTIFIER_VERIFICATION_POINTS[kind.to_s]
  end
end
