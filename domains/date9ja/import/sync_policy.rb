module Date9ja
  module Import
    # Explicit write surface. Foreign keys are resolved through source bindings,
    # never copied as numeric IDs. Public IDs and runtime claim/audit fields stay
    # destination-owned. Unknown families/columns fail closed.
    module SyncPolicy
      FIELDS = {
        "User" => %w[first_name last_name],
        "IdentityIdentifier" => %w[user_id brand_id kind normalized_value verified_at deleted_at],
        "Credential" => %w[user_id identity_identifier_id kind status verified_at deleted_at],
        "BrandMembership" => %w[user_id brand_id status deleted_at],
        "Profile" => %w[user_id brand_id brand_membership_id display_name birthdate gender city country_code bio
          looking_for_text ideal_partner_description body_type children_count drinking fitness height_cm
          interest_in_nigerian_culture is_nigerian job_title languages languages_spoken metadata nationality
          occupation relocation_preferences smoking state_of_origin willing_to_relocate status visibility
          discovery_restricted_at discovery_restriction_reason discovery_restriction_note deleted_at],
        "ProfilePreference" => %w[user_id brand_id profile_id interested_in min_age max_age max_distance_km
          country preferred_attributes preferred_country_codes relationship_intent metadata deleted_at],
        "ProfilePhoto" => %w[user_id brand_id profile_id position status visibility processing_state processed_at metadata deleted_at],
        "ProfileVideo" => %w[user_id brand_id profile_id status visibility processing_state processed_at duration_seconds metadata deleted_at],
        "Like" => %w[brand_id liker_profile_id liked_profile_id kind deleted_at],
        "ProfilePass" => %w[brand_id passer_profile_id passed_profile_id deleted_at],
        "Match" => %w[brand_id profile_a_id profile_b_id status deleted_at],
        "Conversation" => %w[brand_id match_id status deleted_at],
        "Message" => %w[brand_id conversation_id sender_profile_id body kind read_at edited_at source_media_reference
          source_metadata reply_to_message_id reply_snapshot deleted_at],
        "MessageReaction" => %w[brand_id message_id reactor_profile_id emoji deleted_at],
        "ProfileBlock" => %w[brand_id blocker_profile_id blocked_profile_id deleted_at],
        "Report" => %w[brand_id reporter_profile_id reported_profile_id target_type target_id reason note status
          evidence reviewed_at resolution_note],
        "VerificationAssertion" => %w[brand_id user_id profile_id source_type source_id check_type status submitted_at
          reviewed_at reviewer_source_id evidence metadata],
        "TrustEvent" => %w[brand_id user_id profile_id event_type idempotency_key points occurred_at source_type source_id metadata],
        "TrustAdjustment" => %w[brand_id user_id points reason_code occurred_at metadata idempotency_key appeal_status resolved_at],
        "Date9jaHistoryRecord" => %w[brand_id user_id profile_id source_entity source_id record_type occurred_at payload status redacted_at]
      }.freeze

      # A native restriction/read acknowledgement/deletion is never relaxed by
      # reconstructed source state. Other dual edits are explicit conflicts.
      APPEND_ONLY = %w[TrustEvent TrustAdjustment].freeze

      RETAIN_DESTINATION = %w[read_at deleted_at].freeze

      NATURAL_KEYS = {
        "Like" => %w[brand_id liker_profile_id liked_profile_id],
        "ProfilePass" => %w[brand_id passer_profile_id passed_profile_id],
        "Match" => %w[brand_id profile_a_id profile_b_id],
        "Conversation" => %w[brand_id match_id],
        "ProfileBlock" => %w[brand_id blocker_profile_id blocked_profile_id],
        "VerificationAssertion" => %w[brand_id source_type source_id],
        "Date9jaHistoryRecord" => %w[brand_id source_entity source_id],
        "TrustEvent" => %w[brand_id idempotency_key],
        "TrustAdjustment" => %w[brand_id idempotency_key]
      }.freeze

      def self.fields(type)
        FIELDS.fetch(type) { raise FinalSync::Conflict, "unsupported_family" }
      end
    end
  end
end
