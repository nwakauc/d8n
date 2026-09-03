# frozen_string_literal: true

module Date9ja
  module Import
    # Authoritative Date9ja `ProfileVideo.moderation_status` enum
    # (/Users/uchechinwaka/pro/Date9ja/api/app/models/profile_video.rb):
    #   pending: 0, approved: 1, rejected: 2
    #
    # Identical shape to Date9ja::Import::PhotoModeration. PASS 1 only reads and
    # validates the source state. The pass-2 target mapping is recorded here for
    # the ADR / reconciliation contract but is NOT applied — pass 1 creates no
    # ProfileVideo and sets no runtime visibility.
    module VideoModeration
      SOURCE_ENUM = { 0 => "pending", 1 => "approved", 2 => "rejected" }.freeze

      # Documented pass-2 destination mapping (ADR 0023 — profile video reuses the
      # Date9ja immediate-publication policy, exactly like profile photos).
      # `pending` follows Media::VideoPolicy::IMMEDIATE; `rejected` is hidden.
      PASS_2_TARGET = {
        "pending" => { profile_video_status: :pending_review, visibility: :immediate_policy },
        "approved" => { profile_video_status: :approved, visibility: :visible },
        "rejected" => { profile_video_status: :rejected, visibility: :hidden }
      }.freeze

      module_function

      # Returns "pending" / "approved" / "rejected", or nil for any unmapped
      # value (caller fails closed).
      def label(raw)
        SOURCE_ENUM[Integer(raw, exception: false)]
      end
    end
  end
end
