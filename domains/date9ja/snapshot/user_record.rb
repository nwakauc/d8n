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
      :suspended_at, :banned_at, :discovery_restricted_at, :profile_hidden, :onboarding_completed_at,
      :date_of_birth, :gender, :full_name, :display_name, :city, :country_of_residence,
      :about_me, :ideal_partner_description,
      # Preference / option-group inputs, added with the profile & preference
      # importer slice. Legacy enum CODES and integers -- decoded by
      # Date9ja::Import::ValueMapping, never interpreted here.
      :looking_for, :preferred_age_min, :preferred_age_max, :preferred_distance_km,
      :relationship_intention, :wants_children, :children_count,
      # Non-sensitive profile/preference enrichment values, added with the
      # D8N contract-fidelity pass. Legacy enum CODES / integers / a flat
      # language array -- decoded by Date9ja::Import::ValueMapping /
      # LanguageMapping, never interpreted here. None is a sensitive column
      # (FieldMapping::SENSITIVE_DENYLIST is unchanged).
      :smoking, :drinking, :fitness, :education, :commitment_timeline,
      :marital_status, :family_involvement_preference, :occupation, :body_type,
      :height, :willing_to_relocate, :languages_spoken
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
          discovery_restricted_at: row["discovery_restricted_at"],
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
          children_count: row["children_count"],
          smoking: row["smoking"],
          drinking: row["drinking"],
          fitness: row["fitness"],
          education: row["education"],
          commitment_timeline: row["commitment_timeline"],
          marital_status: row["marital_status"],
          family_involvement_preference: row["family_involvement_preference"],
          occupation: row["occupation"],
          body_type: row["body_type"],
          height: row["height"],
          willing_to_relocate: cast_optional_boolean(row["willing_to_relocate"]),
          languages_spoken: normalize_string_list(row["languages_spoken"])
        )
      end

      # Preserves the tri-state the source has (true / false / not answered).
      def self.cast_optional_boolean(value)
        return nil if value.nil? || value.to_s.strip.empty?

        BOOLEAN.cast(value)
      end

      # Postgres `character varying[]` arrives either as a Ruby Array (type-cast
      # exec_query, and synthetic test rows) or as the raw braced literal
      # `{English,"Nigerian Pidgin"}`. Both are reduced to a plain string array;
      # anything else (nil, a scalar) becomes []. No element is interpreted here.
      def self.normalize_string_list(value)
        return value.map(&:to_s) if value.is_a?(Array)
        return [] unless value.is_a?(String)

        inner = value.strip.delete_prefix("{").delete_suffix("}")
        return [] if inner.empty?

        inner.scan(/"(?:[^"\\]|\\.)*"|[^,]+/).map do |token|
          token = token.strip
          token.start_with?('"') && token.end_with?('"') ? token[1..-2].gsub('\\"', '"') : token
        end.reject(&:empty?)
      end

      def source_id = id.to_s

      def soft_deleted? = deleted_at.present?

      def banned? = banned_at.present?

      def suspended? = suspended_at.present?

      # Moderator-owned hard discovery restriction (Date9ja
      # `index_users_on_discovery_eligible` excludes it, independent of
      # profile_hidden/suspension). D8N has no discovery-restriction feature yet,
      # so a restricted member is imported but never published — fail closed.
      def discovery_restricted? = discovery_restricted_at.present?

      # Change-detection fingerprint for LegacyReference.source_fingerprint.
      # Deliberately excludes email/phone/free-text so nothing identifying is
      # written to the D8N database in plaintext.
      def fingerprint
        material = [
          confirmed_at, phone_verified_at, deleted_at, suspended_at, banned_at,
          discovery_restricted_at, profile_hidden, onboarding_completed_at, date_of_birth, gender, city,
          country_of_residence
        ].map(&:to_s).join("|")
        Digest::SHA256.hexdigest(material)[0, 32]
      end

      # Separate fingerprint for the readiness pass. It includes only a digest
      # of source inputs; names and location text never enter D8N evidence/logs.
      def readiness_fingerprint
        material = [
          full_name, city, country_of_residence, profile_hidden,
          onboarding_completed_at, suspended_at, banned_at, deleted_at, discovery_restricted_at,
          preferred_age_min, preferred_age_max, relationship_intention,
          wants_children, children_count,
          smoking, drinking, fitness, education, commitment_timeline,
          marital_status, family_involvement_preference, occupation, body_type,
          height, willing_to_relocate, languages_spoken.join(",")
        ].map(&:to_s).join("|")
        Digest::SHA256.hexdigest(material)[0, 32]
      end
    end
  end
end
