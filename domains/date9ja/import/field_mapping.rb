# frozen_string_literal: true

require "date"

module Date9ja
  module Import
    # The ONLY place a Date9ja `users` value becomes a D8N attribute. Everything
    # is explicit: a legacy column not named here is not imported, and the
    # sensitive/gated columns are listed so a test can assert the firewall and a
    # future edit that maps one is obvious in review.
    module FieldMapping
      IMPORTER_VERSION = "date9ja-identity-v1"

      # Legacy Date9ja `users` columns that MUST NOT cross the Date9ja adapter
      # boundary (DECISIONS.md product/privacy rows still open, plus Aunty Phobie
      # config). `UserSource` never selects these and `UserRecord` never exposes
      # them; this constant makes the intent enforceable in a firewall test.
      SENSITIVE_DENYLIST = %w[
        tribe religion denomination ethnicity state_of_origin is_nigerian
        nationality preferred_religion preferred_tribes preferred_ethnicity
        intertribal_marriage_openness polygamy_openness genotype preferred_genotype
        aunty_phobie_language interest_in_nigerian_culture
      ].freeze

      # A denied legacy name may ALSO be the name of a D8N-native `profiles`
      # column: `fed4f35` added `is_nigerian` / `state_of_origin` / `nationality`
      # as native Date9ja onboarding fields (Profiles::FieldCatalog, conditional
      # on `is_nigerian`). Those columns are owned exclusively by a member
      # completing onboarding on D8N — no Date9ja importer reads or writes them,
      # and the legacy values stay "Awaiting Uchechi" (DECISIONS.md, ADR 0030),
      # dropped by the snapshot sanitizer (scripts/date9ja/sanitize_snapshot.sql).
      # The firewall test allows a denied name to appear in `Profile.column_names`
      # ONLY when it is declared here; any other collision is a defect. A
      # destination column existing is never, by itself, permission to import it.
      NATIVE_DESTINATION_FIELDS = %w[ is_nigerian state_of_origin nationality ].freeze

      # Non-sensitive legacy `users` columns this slice maps onto shared Profile.
      PROFILE_SOURCE_COLUMNS = %w[
        full_name display_name date_of_birth gender city country_of_residence about_me
        ideal_partner_description profile_hidden suspended_at onboarding_completed_at
      ].freeze

      module_function

      def email_verified_at(record) = record.confirmed_at.presence

      def phone_verified_at(record) = record.phone_verified_at.presence

      # A Date9ja account whose legacy bcrypt digest is missing or malformed can
      # still be migrated WITHOUT a usable password ONLY when it owns a recovery
      # channel the shared D8N runtime can actually complete end to end — first
      # access is then the one-time secure recovery flow (AUTHENTICATION.md §"If a
      # hash fails verification"). The password `Credential` is bound to the email
      # `IdentityIdentifier`, and `Identity::RecoveryRequester` / `PasswordReset`
      # resolve the credential THROUGH the requested identifier — so today only a
      # verified EMAIL is an operable recovery channel. A verified-phone-only
      # account is failed closed, not falsely marked recoverable.
      def operable_recovery_channel?(record) = record.confirmed_at.present?

      def password_changed_at(record) = record.created_at.presence || Time.current

      def membership_status(record) = record.suspended? ? :suspended : :active

      def profile_status(record)
        return :suspended if record.suspended?

        # This slice has not imported photos, preferences, location, or option
        # selections. Keep every imported profile unpublished until the complete
        # D8N publication contract can be evaluated by the later slices.
        :draft
      end

      def profile_visibility(_record) = :hidden

      # Returns the Profile attribute hash (excluding user/brand/membership).
      def profile_attributes(record)
        {
          display_name: clamp(record.display_name, 80),
          birthdate: parse_date(record.date_of_birth),
          gender: gender(record),
          city: clamp(record.city, 120),
          country_code: country_code(record.country_of_residence),
          bio: clamp(record.about_me, 1_000),
          looking_for_text: clamp(record.ideal_partner_description, 600),
          status: profile_status(record),
          visibility: profile_visibility(record)
        }.compact
      end

      # `users.gender` is an INTEGER enum (`{ man: 0, woman: 1 }`), not a word.
      # Copying it through unchanged wrote the strings "0"/"1" into
      # `profiles.gender`, which `Matching::EligibilityScope` then compared
      # verbatim against `interested_in` — so it matched nothing. Decode through
      # the one mapping table (D-1) instead. An unknown code is left nil rather
      # than guessed; `ProfilePreferenceImport` records it as a note.
      def gender(record)
        outcome = ValueMapping.gender(record.gender)
        outcome.ok? ? outcome.value : nil
      end

      def clamp(value, limit)
        string = value.to_s.strip
        return nil if string.empty?

        string[0, limit]
      end

      # Only accept an already-ISO-3166-alpha-2 value; a legacy free-text country
      # name is left unmapped (a later, product-approved geography pass fills it).
      def country_code(value)
        code = value.to_s.strip.upcase
        code.match?(/\A[A-Z]{2}\z/) ? code : nil
      end

      def parse_date(value)
        return value if value.is_a?(Date)
        return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)
        return nil if value.to_s.strip.empty?

        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
