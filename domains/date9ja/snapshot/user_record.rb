# frozen_string_literal: true

require "digest"

module Date9ja
  module Snapshot
    # A single Date9ja `users` row, reduced to exactly the fields this importer
    # slice is allowed to see. Sensitive / gated legacy columns (tribe, religion,
    # denomination, ethnicity, state_of_origin, nationality, genotype, preferred_*
    # …) are never selected by UserSource and have no attribute here.
    UserRecord = Data.define(
      :id, :public_id, :email, :phone, :encrypted_password,
      :confirmed_at, :phone_verified_at, :created_at, :deleted_at,
      :suspended_at, :banned_at, :profile_hidden, :onboarding_completed_at,
      :date_of_birth, :gender, :full_name, :display_name, :city, :country_of_residence,
      :about_me, :ideal_partner_description,
      # Preference / option-group inputs, added with the profile & preference
      # importer slice. Legacy enum CODES and integers -- decoded by
      # Date9ja::Import::ValueMapping, never interpreted here.
      :looking_for, :preferred_age_min, :preferred_age_max, :preferred_distance_km,
      :relationship_intention, :wants_children, :children_count
    ) do
      BOOLEAN = ActiveModel::Type::Boolean.new

      def self.from_raw(raw)
        row = raw.transform_keys(&:to_s)
        new(
          id: row["id"],
          public_id: row["public_id"],
          email: row["email"],
          phone: row["phone"],
          encrypted_password: row["encrypted_password"],
          confirmed_at: row["confirmed_at"],
          phone_verified_at: row["phone_verified_at"],
          created_at: row["created_at"],
          deleted_at: row["deleted_at"],
          suspended_at: row["suspended_at"],
          banned_at: row["banned_at"],
          profile_hidden: BOOLEAN.cast(row["profile_hidden"]) || false,
          onboarding_completed_at: row["onboarding_completed_at"],
          date_of_birth: row["date_of_birth"],
          gender: row["gender"],
          full_name: row["full_name"],
          display_name: row["display_name"],
          city: row["city"],
          country_of_residence: row["country_of_residence"],
          about_me: row["about_me"],
          ideal_partner_description: row["ideal_partner_description"],
          looking_for: row["looking_for"],
          preferred_age_min: row["preferred_age_min"],
          preferred_age_max: row["preferred_age_max"],
          preferred_distance_km: row["preferred_distance_km"],
          relationship_intention: row["relationship_intention"],
          wants_children: row["wants_children"],
          children_count: row["children_count"]
        )
      end

      def source_id = id.to_s

      def soft_deleted? = deleted_at.present?

      def banned? = banned_at.present?

      def suspended? = suspended_at.present?

      # Change-detection fingerprint for LegacyReference.source_fingerprint.
      # Deliberately excludes email/phone/free-text so nothing identifying is
      # written to the D8N database in plaintext.
      def fingerprint
        material = [
          confirmed_at, phone_verified_at, deleted_at, suspended_at, banned_at,
          profile_hidden, onboarding_completed_at, date_of_birth, gender, city,
          country_of_residence
        ].map(&:to_s).join("|")
        Digest::SHA256.hexdigest(material)[0, 32]
      end

      # Separate fingerprint for the readiness pass. It includes only a digest
      # of source inputs; names and location text never enter D8N evidence/logs.
      def readiness_fingerprint
        material = [
          full_name, city, country_of_residence, profile_hidden,
          onboarding_completed_at, suspended_at, banned_at, deleted_at,
          preferred_age_min, preferred_age_max, relationship_intention,
          wants_children, children_count
        ].map(&:to_s).join("|")
        Digest::SHA256.hexdigest(material)[0, 32]
      end
    end
  end
end
