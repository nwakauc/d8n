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
      # D-5 OPEN. Only the three codes with an unambiguous D8N counterpart are
      # mapped. `courtship` (1), `dating` (3) and `activity_partner` (5) have no
      # D8N option that means the same thing, and D8N's `open_to_dating` /
      # `still_figuring_it_out` have no legacy counterpart. Folding one onto the
      # other would rewrite what a member said about what they want, so those
      # codes fail closed until D-5 is resolved.
      RELATIONSHIP_INTENT = {
        0 => "marriage",
        2 => "long_term_relationship",
        4 => "friendship"
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
      # D-6 PARTIALLY OPEN. `yes` and `no` map exactly. Legacy `open` (45
      # members) does not: D8N offers `maybe` and `open_to_partner_with_children`,
      # which mean different things, and the legacy label does not say which the
      # member meant. Fails closed rather than choosing for them.
      WANTS_CHILDREN = { 0 => "yes", 1 => "no" }.freeze

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
        "wants_children" => WANTS_CHILDREN
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
