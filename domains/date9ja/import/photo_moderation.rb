# frozen_string_literal: true

module Date9ja
  module Import
    # Authoritative Date9ja `Photo.moderation_status` enum
    # (/Users/uchechinwaka/pro/Date9ja/api/app/models/photo.rb):
    #   pending: 0, approved: 1, rejected: 2
    #
    # PASS 1 only reads and validates the source state. The pass-2 target
    # mapping is recorded here for the ADR / reconciliation contract but is NOT
    # applied — pass 1 creates no ProfilePhoto and sets no runtime visibility.
    module PhotoModeration
      SOURCE_ENUM = { 0 => "pending", 1 => "approved", 2 => "rejected" }.freeze

      # Documented pass-2 destination mapping (ADR 0027 / RECONCILIATION.md).
      # `pending` visibility follows Date9ja's immediate-publication policy
      # (Media::PhotoPolicy::IMMEDIATE); `rejected` is hidden.
      PASS_2_TARGET = {
        "pending" => { profile_photo_status: :pending_review, visibility: :immediate_policy },
        "approved" => { profile_photo_status: :approved, visibility: :visible },
        "rejected" => { profile_photo_status: :rejected, visibility: :hidden }
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
