# frozen_string_literal: true

module Date9ja
  module Import
    # The ONLY place a legacy Date9ja enum CODE becomes a D8N value.
    #
    # Two different kinds of knowledge live here and are kept apart deliberately:
    #
    #   FACT     — what the legacy code means. Quoted from `api/app/models/user.rb`
    #              in the Date9ja repository, e.g. `enum :gender, { man: 0, woman: 1 }`.
    #              Measured and confirmed against the snapshot by the Pass-1 census
    #              (`scripts/date9ja/source_census.sql`, ord 210-223).
    #   DECISION — which D8N string that meaning becomes. Recorded in
    #              PROFILE-VALUE-MAPPING.md section 6 and resolved by Uchechi.
    #              Every table below cites the decision that authorised it.
    #
    # A code with no APPROVED destination is NOT guessed. `lookup` returns
    # `:unmapped` and the importer records a reason code and leaves the field
    # unset — the member keeps whatever they had, and nothing is invented. This
    # is the same fail-closed rule as photo moderation (ADR 0027) and video
    # duration (ADR 0029).
    module ValueMapping
      # Outcome of a single lookup. `:ok` carries a value; `:absent` means the
      # source column was NULL (the member never answered); `:unmapped` means the
      # code is real but has no approved D8N destination yet.
      Outcome = Data.define(:status, :value, :code) do
        def ok? = status == :ok
        def absent? = status == :absent
        def unmapped? = status == :unmapped
      end

      # --- discovery-critical (D-1: "man" / "woman", RESOLVED) ---------------
      #
      # FACT: `enum :gender, { man: 0, woman: 1 }` — integer/int4, NULL for 0 of
      # 288 source rows. Both `gender` and `looking_for` use this one vocabulary,
      # and Date9ja's own matching scope is reciprocal in exactly D8N's shape.
      GENDER = { 0 => "man", 1 => "woman" }.freeze

      # D-9 RESOLVED: migrate `looking_for` exactly as the member stored it.
      #
      # A member whose `looking_for` equals their own gender is a member seeking
      # their own gender. That is an orientation, not a data defect, and this
      # importer treats it as an ordinary value: no reason code, no quarantine,
      # no flag, no re-ask. The Pass-1 census observed that the onboarding form
      # pre-filled this control, which is why the *distribution* is skewed — but
      # a distribution cannot tell you which individual answers were deliberate,
      # and D8N does not get to overrule a member about who they are looking for.
      INTERESTED_IN = { 0 => [ "man" ].freeze, 1 => [ "woman" ].freeze }.freeze

      # --- option groups -----------------------------------------------------
      #
      # FACT: `enum :relationship_intention,
      #   { marriage: 0, courtship: 1, serious_relationship: 2, dating: 3,
      #     friendship: 4, activity_partner: 5 }`
      #
      # D8N CONTRACT FIDELITY (2026-09-09): D8N now represents every legacy value.
      # `serious_relationship` reuses `long_term_relationship` (exact synonym);
      # `courtship`, `dating` and `activity_partner` were added as first-class
      # D8N option codes for Date9ja rather than folded onto a near-neighbour.
      # This is a total, lossless mapping — nothing fails closed.
      RELATIONSHIP_INTENT = {
        0 => "marriage",
        1 => "courtship",
        2 => "long_term_relationship",
        3 => "dating",
        4 => "friendship",
        5 => "activity_partner"
      }.freeze

      # FACT: `enum :children_count, { none: 0, one: 1, two: 2, three_or_more: 3 }`
      #
      # This is an ENUM, not a number — code 3 means "three or more". The Pass-1
      # census flagged that copying it into an integer column would be wrong. It
      # is not being copied into one: D8N's `has_children` asks a yes/no
      # question, and every legacy code answers it exactly. `none` is an
      # explicitly chosen value, distinct from NULL, so it is a real "no".
      HAS_CHILDREN = { 0 => "no", 1 => "yes", 2 => "yes", 3 => "yes" }.freeze

      # FACT: `enum :wants_children, { yes: 0, no: 1, open: 2 }`
      #
      # D8N CONTRACT FIDELITY (2026-09-09): `open` was added as a first-class D8N
      # `wants_children` option (distinct from `maybe`), so every legacy value
      # maps exactly. `has_children` (below) still records children-count as a
      # yes/no; the exact bucket is preserved separately by CHILDREN_COUNT.
      WANTS_CHILDREN = { 0 => "yes", 1 => "no", 2 => "open" }.freeze

      # FACT: `enum :children_count, { none: 0, one: 1, two: 2, three_or_more: 3 }`
      # Preserved into the `children_count` option group as the exact bucket —
      # "three_or_more" is a category, never coerced to the integer 3.
      CHILDREN_COUNT = { 0 => "none", 1 => "one", 2 => "two", 3 => "three_or_more" }.freeze

      # FACT: `enum :family_involvement_preference, { low: 0, medium: 1, high: 2 }`
      # An intensity scale — mapped to the `family_involvement_level` group,
      # which D8N added for exactly this (not the nominal `family_involvement`).
      FAMILY_INVOLVEMENT_LEVEL = { 0 => "low", 1 => "medium", 2 => "high" }.freeze

      # FACT: `enum :commitment_timeline,
      #   { asap: 0, within_1_year: 1, one_to_two_years: 2,
      #     two_to_three_years: 3, not_sure: 4 }`
      COMMITMENT_TIMELINE = {
        0 => "asap", 1 => "within_1_year", 2 => "one_to_two_years",
        3 => "two_to_three_years", 4 => "not_sure"
      }.freeze

      # FACT: `enum :marital_status, { single: 0, divorced: 1, widowed: 2 }`
      MARITAL_STATUS = { 0 => "single", 1 => "divorced", 2 => "widowed" }.freeze

      # FACT: `enum :education, { secondary: 0, ond_hnd: 1, bsc: 2, msc: 3, phd: 4 }`
      # `ond_hnd` (Nigerian OND/HND tertiary diploma) maps to the `diploma` code
      # D8N added for it; the rest are exact synonyms of existing codes.
      EDUCATION = {
        0 => "high_school", 1 => "diploma", 2 => "undergraduate",
        3 => "postgraduate", 4 => "doctorate"
      }.freeze

      # FACT: `enum :smoking/:drinking/:fitness, { never: 0, occasionally: 1, regularly: 2 }`
      # D8N's `profiles.smoking/drinking/fitness` are free strings validated to
      # exactly this vocabulary (Profiles::FieldCatalog). Labels carried verbatim.
      LIFESTYLE_FREQUENCY = { 0 => "never", 1 => "occasionally", 2 => "regularly" }.freeze

      # No legacy source exists for `meeting_pace` — proven by census measure 202
      # returning `none` (no unclassified source column) and by the absence of any
      # meeting-pace concept among Date9ja's 16 `users` enums. D-7 RESOLVED by
      # relaxing the requirement; nothing is ever fabricated for it.
      NO_SOURCE_OPTION_GROUPS = %w[ meeting_pace ].freeze

      TABLES = {
        "gender" => GENDER,
        "interested_in" => INTERESTED_IN,
        "relationship_intent" => RELATIONSHIP_INTENT,
        "has_children" => HAS_CHILDREN,
        "wants_children" => WANTS_CHILDREN,
        "children_count" => CHILDREN_COUNT,
        "family_involvement_level" => FAMILY_INVOLVEMENT_LEVEL,
        "commitment_timeline" => COMMITMENT_TIMELINE,
        "marital_status" => MARITAL_STATUS,
        "education_level" => EDUCATION,
        "smoking" => LIFESTYLE_FREQUENCY,
        "drinking" => LIFESTYLE_FREQUENCY,
        "fitness" => LIFESTYLE_FREQUENCY
      }.freeze

      module_function

      # Decodes one legacy code for one field. `code` is whatever the snapshot
      # holds: an Integer, a numeric String, or nil.
      def lookup(field, code)
        table = TABLES.fetch(field.to_s) { raise ArgumentError, "no mapping table for #{field.inspect}" }
        normalized = normalize_code(code)
        return Outcome.new(status: :absent, value: nil, code: nil) if normalized.nil?

        if table.key?(normalized)
          Outcome.new(status: :ok, value: table.fetch(normalized), code: normalized)
        else
          Outcome.new(status: :unmapped, value: nil, code: normalized)
        end
      end

      def gender(code) = lookup("gender", code)

      def interested_in(code) = lookup("interested_in", code)

      # Legacy codes are small non-negative integers. Anything else — a float, a
      # word, whitespace, an out-of-range value — is not a code we recognise and
      # must not be coerced into one.
      def normalize_code(code)
        case code
        when nil then nil
        when Integer then code
        else
          text = code.to_s.strip
          return nil if text.empty?

          text.match?(/\A-?\d+\z/) ? Integer(text, 10) : :invalid
        end
      end
      private_class_method :normalize_code
    end
  end
end
