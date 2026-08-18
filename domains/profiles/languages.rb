module Profiles
  # Controlled taxonomy + validator for structured profile languages
  # (`profiles.languages` jsonb: array of { code, proficiency, primary }).
  #
  # The allowed language set and labels are DATA (config/profiles/languages.yml),
  # never hardcoded into controllers or models — so the taxonomy can grow or be
  # curated without a code change, and other D8N brands reuse the same seam. This
  # is separate from the retained legacy free-text `languages_spoken` array, so no
  # existing payload is affected.
  class Languages
    PROFICIENCIES = %w[ native fluent conversational learning ].freeze
    MAX_ENTRIES = 15
    CONFIG_PATH = Rails.root.join("config", "profiles", "languages.yml")

    # Canonical, validated entries plus a flat list of human-readable errors.
    Result = Data.define(:entries, :errors)

    class << self
      def catalog
        @catalog ||= load_catalog
      end

      def codes
        @codes ||= catalog.map { |entry| entry.fetch(:code) }.to_set
      end

      def label_for(code)
        catalog.find { |entry| entry.fetch(:code) == code }&.fetch(:label)
      end

      def valid_code?(code)
        codes.include?(code)
      end

      # Presentation shape for stored entries: attaches the taxonomy label and
      # normalizes types. Unknown codes are dropped (fail closed). Used by all
      # profile serializers so structured languages render consistently.
      def serialize(entries)
        return [] unless entries.is_a?(Array)

        entries.filter_map do |entry|
          code = (entry["code"] || entry[:code]).to_s
          next unless valid_code?(code)

          {
            code:,
            label: label_for(code),
            proficiency: (entry["proficiency"] || entry[:proficiency]).presence,
            primary: ActiveModel::Type::Boolean.new.cast(entry["primary"] || entry[:primary]) || false
          }
        end
      end

      # Test/boot seam: drop the memoized taxonomy so an updated config reloads.
      def reset_cache!
        @catalog = nil
        @codes = nil
      end

      # Coerce arbitrary input (params or stored jsonb) into canonical entries,
      # deduplicated by code, and collect validation errors. Never raises: callers
      # (the Profile model) decide how to surface `errors`.
      def normalize(raw)
        return Result.new([], [ "must be an array" ]) unless raw.is_a?(Array)

        errors = []
        errors << "cannot have more than #{MAX_ENTRIES} entries" if raw.size > MAX_ENTRIES
        seen = {}

        raw.each do |entry|
          hash = entry.respond_to?(:to_h) ? entry.to_h : entry
          unless hash.is_a?(Hash)
            errors << "entries must be objects"
            next
          end

          code = (hash["code"] || hash[:code]).to_s.strip.downcase
          unless valid_code?(code)
            errors << "contains an unsupported language code"
            next
          end

          proficiency = (hash["proficiency"] || hash[:proficiency]).presence&.to_s
          if proficiency && !PROFICIENCIES.include?(proficiency)
            errors << "contains an invalid proficiency"
            next
          end

          primary = ActiveModel::Type::Boolean.new.cast(hash["primary"] || hash[:primary]) || false

          canonical = seen[code] ||= { "code" => code }
          canonical["proficiency"] = proficiency if proficiency
          canonical["primary"] = true if primary
        end

        entries = seen.values
        errors << "can have at most one primary language" if entries.count { |entry| entry["primary"] } > 1

        Result.new(entries, errors.uniq)
      end

      private

      def load_catalog
        YAML.safe_load_file(CONFIG_PATH).fetch("languages").map do |entry|
          { code: entry.fetch("code").to_s, label: entry.fetch("label").to_s }
        end.freeze
      end
    end
  end
end
