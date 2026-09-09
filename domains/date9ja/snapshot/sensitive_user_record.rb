# frozen_string_literal: true

require "digest"

module Date9ja
  module Snapshot
    # One Date9ja `users` row reduced to the sensitive identity / culture /
    # health-adjacent columns. Read only by `SensitiveProfileImport` through
    # `SensitiveUserSource`. Values are legacy strings / string arrays / an
    # integer-or-boolean openness flag — decoded by the explicit
    # Date9ja::Import mapping tables, never interpreted here.
    SensitiveUserRecord = Data.define(
      :id, :deleted_at, :banned_at,
      :is_nigerian, :state_of_origin, :nationality, :tribe, :ethnicity, :religion, :denomination,
      :genotype, :intertribal_marriage_openness, :polygamy_openness, :interest_in_nigerian_culture,
      :preferred_religion, :preferred_tribes, :preferred_ethnicity, :preferred_genotype
    ) do
      def self.from_raw(raw)
        row = raw.transform_keys(&:to_s)
        new(
          id: row["id"],
          deleted_at: row["deleted_at"],
          banned_at: row["banned_at"],
          is_nigerian: cast_optional_boolean(row["is_nigerian"]),
          state_of_origin: presence(row["state_of_origin"]),
          nationality: presence(row["nationality"]),
          tribe: presence(row["tribe"]),
          ethnicity: presence(row["ethnicity"]),
          religion: presence(row["religion"]),
          denomination: presence(row["denomination"]),
          genotype: presence(row["genotype"]),
          intertribal_marriage_openness: presence(row["intertribal_marriage_openness"]),
          polygamy_openness: presence(row["polygamy_openness"]),
          interest_in_nigerian_culture: presence(row["interest_in_nigerian_culture"]),
          preferred_religion: normalize_string_list(row["preferred_religion"]),
          preferred_tribes: normalize_string_list(row["preferred_tribes"]),
          preferred_ethnicity: normalize_string_list(row["preferred_ethnicity"]),
          preferred_genotype: normalize_string_list(row["preferred_genotype"])
        )
      end

      def self.presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def self.cast_optional_boolean(value)
        return nil if value.nil? || value.to_s.strip.empty?

        ActiveModel::Type::Boolean.new.cast(value)
      end

      # Reuses the same brace-literal / Array handling as UserRecord.
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

      # PII-free change-detection digest — a hash of the sensitive material, so
      # nothing identifying is written to D8N evidence in plaintext.
      def fingerprint
        material = [
          is_nigerian, state_of_origin, nationality, tribe, ethnicity, religion, denomination,
          genotype, intertribal_marriage_openness, polygamy_openness,
          interest_in_nigerian_culture,
          preferred_religion.join(","), preferred_tribes.join(","),
          preferred_ethnicity.join(","), preferred_genotype.join(",")
        ].map(&:to_s).join("|")
        Digest::SHA256.hexdigest(material)[0, 32]
      end
    end
  end
end
