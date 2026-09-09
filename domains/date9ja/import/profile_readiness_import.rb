# frozen_string_literal: true

module Date9ja
  module Import
    # Final migration-side profile pass. It fills only deterministic gaps, asks
    # the canonical Completion service for the truth, and records exactly one
    # PII-free disposition per eligible source member.
    class ProfileReadinessImport
      SOURCE_SYSTEM = "date9ja"
      SOURCE_ENTITY = "user"
      IMPORTER_VERSION = "date9ja-profile-readiness-v1"
      PUBLICATION_POLICIES = %i[classify_only publish_visible_onboarded].freeze

      Result = Data.define(:reconciliation)

      class WrongBrand < StandardError; end
      class StaleBrandContract < StandardError; end
      class InvalidPublicationPolicy < StandardError; end

      COMPLETION_REASONS = {
        "first_name" => "name_confirmation_required",
        "last_name" => "name_confirmation_required",
        "display_name" => "display_name_required",
        "birthdate" => "birthdate_required",
        "gender" => "gender_required",
        "country_code" => "country_unresolved",
        "city" => "city_required",
        "bio" => "bio_required",
        "preferences.interested_in" => "interested_in_required",
        "preferences.min_age" => "age_preference_required",
        "preferences.max_age" => "age_preference_required",
        "photos" => "photo_required",
        "location" => "location_confirmation_required"
      }.freeze

      OPTION_SOURCES = {
        "relationship_intent" => :relationship_intention,
        "has_children" => :children_count,
        "wants_children" => :wants_children
      }.freeze

      def self.call(...) = new(...).call

      def initialize(brand:, source:, publication_policy: :classify_only, importer_version: IMPORTER_VERSION)
        @brand = brand
        @source = source
        @publication_policy = publication_policy.to_sym
        @importer_version = importer_version
        @reconciliation = ProfileReadinessReconciliation.new
      end

      def call
        assert_contract!

        source.each do |record|
          reconciliation.measure!(:source_users_considered)
          if record.soft_deleted? || record.banned?
            reconciliation.measure!(:source_ineligible)
            suppress_previously_imported_ineligible!(record)
            next
          end

          reconciliation.measure!(:eligible)
          import_one(record)
        end

        Result.new(reconciliation)
      end

      private

      attr_reader :brand, :source, :publication_policy, :importer_version, :reconciliation

      def assert_contract!
        unless brand&.slug == SOURCE_SYSTEM && brand.active? && brand.deleted_at.nil?
          raise WrongBrand, "profile readiness requires the active date9ja brand"
        end
        unless PUBLICATION_POLICIES.include?(publication_policy)
          raise InvalidPublicationPolicy, publication_policy.to_s
        end

        actual = brand.profile_completion_requirements.deep_stringify_keys
        expected = Profiles::Date9jaProfileCatalog::REQUIREMENTS.deep_stringify_keys
        return if actual == expected

        raise StaleBrandContract,
          "Date9ja persisted completion requirements do not match the current profile catalogue"
      end

      def import_one(record)
        profile_reference = Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: "profile", source_id: record.source_id
        )
        unless profile_reference&.resolvable?
          persist_failure(record, "profile_not_imported")
          return reconciliation.disposition!(:failed, reasons: [ "profile_not_imported" ])
        end

        profile = profile_reference.destination
        existing_readiness = readiness_for(record)
        disposition = nil
        reasons = []
        publication_applied_at = existing_readiness&.publication_applied_at
        applied_fields = Array(existing_readiness&.applied_fields).dup

        ActiveRecord::Base.transaction(requires_new: true) do
          profile.lock!
          # ReferenceMap destinations can carry an association cached by an
          # earlier import pass. Re-read identity state while holding the
          # profile lock so member/operator edits win over that cached object.
          profile.user.reload
          before = Profiles::Completion.call(profile:)
          reconciliation.measure!(:complete_before) if before.complete?

          apply_names!(profile.user, record, applied_fields:)
          apply_profile_scalars!(profile, record, applied_fields:)
          apply_enrichment_scalars!(profile, record, applied_fields:)
          apply_location!(profile, applied_fields:)

          completion = Profiles::Completion.call(profile:)
          reconciliation.measure!(:complete_after) if completion.complete?
          measure_preference_and_options!(profile)
          reasons.concat(completion_reasons(completion, profile:, record:))

          disposition, state_reasons = classify(
            profile:, record:, completion:, existing_readiness:
          )
          reasons.concat(state_reasons)

          if publication_policy == :publish_visible_onboarded
            if disposition == :ready && !profile.active?
              Profiles::Publication.activate!(user: profile.user, brand:)
              publication_applied_at ||= Time.current
              reconciliation.measure!(:publications_applied)
            elsif disposition == :intentionally_hidden && profile.active? && profile.visible?
              # Source state turned unpublishable (hidden/suspended/restricted)
              # after an earlier publish — withdraw it defensively.
              Profiles::Publication.deactivate!(user: profile.user, brand:)
              reconciliation.measure!(:publications_withdrawn)
            end
          end

          persist_readiness!(
            record:, profile:, disposition:, reasons: reasons.uniq,
            publication_applied_at:, applied_fields:
          )
        end

        reconciliation.disposition!(disposition, reasons: reasons)
      rescue StandardError
        persist_failure(record, "technical_failure", profile: profile_reference&.destination)
        reconciliation.disposition!(:failed, reasons: [ "technical_failure" ])
      end

      def apply_names!(user, record, applied_fields:)
        reconciliation.measure!(:names_source_present) if record.full_name.present?
        if user.first_name.present? || user.last_name.present?
          reconciliation.measure!(:native_values_preserved)
          if user.first_name.present? && user.last_name.present?
            reconciliation.measure!(:names_preserved)
          else
            reconciliation.measure!(:names_unresolved)
          end
          return
        end
        if (applied_fields & %w[first_name last_name]).any?
          reconciliation.measure!(:names_unresolved)
          return
        end

        outcome = NameMapping.call(record.full_name)
        unless outcome.mapped?
          reconciliation.measure!(:names_unresolved)
          return
        end

        user.update!(first_name: outcome.first_name, last_name: outcome.last_name)
        applied_fields.concat(%w[first_name last_name]).uniq!
        reconciliation.measure!(:names_mapped)
      end

      def apply_profile_scalars!(profile, record, applied_fields:)
        attrs = {}

        # Date9ja uses the given name as the display name. Preserve a distinct
        # legacy display name if the member set one; otherwise fall back to
        # first_name (resolved by apply_names! just above). Never overwrite a
        # value the member/operator already holds.
        if profile.display_name.blank? && !applied_fields.include?("display_name")
          display_name = FieldMapping.clamp(record.display_name, 80) || profile.user.first_name
          if display_name.present?
            attrs[:display_name] = display_name
            applied_fields << "display_name"
          end
        end

        reconciliation.measure!(:countries_source_present) if record.country_of_residence.present?

        if profile.city.blank? && !applied_fields.include?("city")
          city = FieldMapping.clamp(record.city, 120)
          if city
            attrs[:city] = city
            applied_fields << "city"
          end
        else
          reconciliation.measure!(:native_values_preserved)
          source_city = FieldMapping.clamp(record.city, 120)
          applied_fields << "city" if profile.city.present? && profile.city == source_city
        end

        if profile.country_code.present?
          reconciliation.measure!(:native_values_preserved)
          reconciliation.measure!(:countries_preserved)
          source_country = CountryMapping.call(record.country_of_residence)
          if source_country.mapped? && profile.country_code == source_country.country_code
            applied_fields << "country_code"
          end
        elsif applied_fields.include?("country_code")
          reconciliation.measure!(:native_values_preserved)
          reconciliation.measure!(:countries_unresolved)
        else
          outcome = CountryMapping.call(record.country_of_residence)
          if outcome.mapped?
            attrs[:country_code] = outcome.country_code
            applied_fields << "country_code"
            reconciliation.measure!(:countries_mapped)
          else
            reconciliation.measure!(:countries_unresolved)
          end
        end

        applied_fields.uniq!
        profile.update!(attrs) if attrs.any?
      end

      # Non-sensitive profile enrichment values. Every one has a D8N destination
      # (Profiles::FieldCatalog) that Date9ja already enables. Gap-fill only:
      # a value the member or an operator already holds is never overwritten,
      # and a field this importer set that was later cleared is not refilled
      # (tracked through applied_fields, persisted on the readiness row). None of
      # these is a publication gate, so an unknown/absent value never hides a
      # member.
      ENRICHMENT_ENUM_SCALARS = { smoking: :smoking, drinking: :drinking, fitness: :fitness }.freeze

      def apply_enrichment_scalars!(profile, record, applied_fields:)
        attrs = {}

        ENRICHMENT_ENUM_SCALARS.each do |column, source_attr|
          unless enrichment_gap?(profile, column, applied_fields)
            reconciliation.measure!(:enrichment_values_preserved) if profile.public_send(column).present?
            next
          end

          outcome = ValueMapping.lookup(column.to_s, record.public_send(source_attr))
          record_enrichment_disposition(outcome.status)
          attrs[column] = outcome.value if outcome.ok?
          applied_fields << column.to_s if outcome.ok?
        end

        if enrichment_gap?(profile, :body_type, applied_fields)
          body_type = FieldMapping.clamp(record.body_type&.to_s&.gsub(/\s+/, " "), 80)
          if body_type
            attrs[:body_type] = body_type
            applied_fields << "body_type"
            reconciliation.measure!(:enrichment_values_mapped)
          end
        end

        if enrichment_gap?(profile, :occupation, applied_fields)
          occupation = FieldMapping.clamp(record.occupation&.to_s&.gsub(/\s+/, " "), 120)
          if occupation
            attrs[:occupation] = occupation
            applied_fields << "occupation"
            reconciliation.measure!(:enrichment_values_mapped)
          end
        end

        if profile.height_cm.nil? && !applied_fields.include?("height_cm")
          height = plausible_height_cm(record.height)
          if height
            attrs[:height_cm] = height
            applied_fields << "height_cm"
            reconciliation.measure!(:enrichment_values_mapped)
          elsif record.height.present?
            # Present but outside any plausible cm/inch band (source range is
            # 1..588) — junk, not migrated. Recorded, not hidden.
            reconciliation.measure!(:enrichment_values_unresolved)
          end
        end

        if profile.willing_to_relocate.nil? && !applied_fields.include?("willing_to_relocate")
          unless record.willing_to_relocate.nil?
            attrs[:willing_to_relocate] = record.willing_to_relocate
            applied_fields << "willing_to_relocate"
            reconciliation.measure!(:enrichment_values_mapped)
          end
        end

        apply_languages!(profile, record, applied_fields:, attrs:)
        apply_relocation_preferences!(profile, record, applied_fields:, attrs:)

        applied_fields.uniq!
        profile.update!(attrs) if attrs.any?
      end

      # Legacy `users.relocation_preferences` is a flat array of user-typed
      # place strings, separate from the `willing_to_relocate` boolean. It maps
      # to `profiles.relocation_preferences` (Profiles::FieldCatalog string_list,
      # <=10 entries, <=80 chars each). Carried as normalized free text — never
      # geocoded or coerced. Gap-fill only.
      RELOCATION_PREFERENCE_MAX_ENTRIES = 10
      RELOCATION_PREFERENCE_MAX_LENGTH = 80

      def apply_relocation_preferences!(profile, record, applied_fields:, attrs:)
        return if profile.relocation_preferences.present? || applied_fields.include?("relocation_preferences")

        normalized = Array(record.relocation_preferences)
          .filter_map { |value| FieldMapping.clamp(value.to_s.gsub(/\s+/, " "), RELOCATION_PREFERENCE_MAX_LENGTH) }
          .uniq
          .first(RELOCATION_PREFERENCE_MAX_ENTRIES)

        if normalized.any?
          attrs[:relocation_preferences] = normalized
          applied_fields << "relocation_preferences"
          reconciliation.measure!(:relocation_preferences_mapped)
        elsif Array(record.relocation_preferences).any?
          reconciliation.measure!(:relocation_preferences_unresolved)
        end
      end

      def apply_languages!(profile, record, applied_fields:, attrs:)
        return if profile.languages.present? || applied_fields.include?("languages")

        outcome = LanguageMapping.call(record.languages_spoken)
        if outcome.codes.any?
          attrs[:languages] = outcome.codes.map { |code| { "code" => code, "proficiency" => nil, "primary" => false } }
          applied_fields << "languages"
          reconciliation.measure!(:languages_mapped)
        elsif record.languages_spoken.any?
          reconciliation.measure!(:languages_unresolved)
        end
      end

      def enrichment_gap?(profile, column, applied_fields)
        profile.public_send(column).blank? && !applied_fields.include?(column.to_s)
      end

      def record_enrichment_disposition(status)
        case status
        when :ok then reconciliation.measure!(:enrichment_values_mapped)
        when :unmapped then reconciliation.measure!(:enrichment_values_unresolved)
        end
      end

      def plausible_height_cm(value)
        return nil if value.nil?

        integer = value.is_a?(Integer) ? value : Integer(value.to_s.strip, 10)
        integer.between?(100, 250) ? integer : nil
      rescue ArgumentError, TypeError
        nil
      end

      def apply_location!(profile, applied_fields:)
        # A brand that does not declare place selection (Date9ja stores
        # country/city as profile scalars and has no ProfileLocation / distance
        # contract — see Matching::EligibilityPolicy::LIQUIDITY_FIRST) never
        # receives a migration-created ProfileLocation. A member's own or an
        # operator's ProfileLocation is still left untouched.
        return unless D8n::Platform::BrandRegistry.fetch(brand:).place_selection_enabled?

        if ProfileLocation.kept.exists?(profile:)
          reconciliation.measure!(:native_values_preserved)
          reconciliation.measure!(:locations_preserved)
          return
        end
        if applied_fields.include?("location")
          reconciliation.measure!(:locations_unresolved)
          return
        end

        place = PlaceResolver.call(city: profile.city, country_code: profile.country_code)
        if place.nil?
          reconciliation.measure!(:locations_unresolved)
          return
        end

        Profiles::CurrentPlace.select!(
          user: profile.user,
          brand:,
          place_id: place.id,
          country_codes: D8n::Platform::BrandRegistry.fetch(brand:).place_country_codes
        )
        applied_fields << "location"
        reconciliation.measure!(:locations_mapped)
      end

      def measure_preference_and_options!(profile)
        preference = ProfilePreference.kept.find_by(profile:)
        if preference&.min_age.present? && preference&.max_age.present?
          reconciliation.measure!(:age_ranges_preserved)
        else
          reconciliation.measure!(:age_ranges_unresolved)
        end

        OPTION_SOURCES.each_key do |group_key|
          group = ProfileOptionGroup.kept.find_by(brand:, key: group_key)
          satisfied = group && ProfileOptionSelection.kept.exists?(profile:, profile_option_group: group)
          suffix = satisfied ? :satisfied : :unresolved
          reconciliation.measure!("#{group_key}_#{suffix}".to_sym)
        end
      end

      def completion_reasons(completion, profile:, record:)
        completion.missing.filter_map do |missing|
          key = missing.to_s
          next option_reason(key.delete_prefix("options."), profile:, record:) if key.start_with?("options.")

          COMPLETION_REASONS.fetch(key, "completion_requirement_unresolved")
        end.uniq
      end

      def option_reason(group_key, profile:, record:)
        source_attribute = OPTION_SOURCES[group_key]
        return "#{group_key}_catalogue_unavailable" if source_attribute.nil?

        outcome = ValueMapping.lookup(group_key, record.public_send(source_attribute))
        return "#{group_key}_missing" if outcome.absent?
        return "#{group_key}_unmapped" if outcome.unmapped?

        group = ProfileOptionGroup.kept.find_by(brand:, key: group_key)
        option = group&.profile_options&.kept&.find_by(code: outcome.value)
        return "#{group_key}_catalogue_unavailable" if group.nil? || option.nil?

        # The mapping is approved and the catalogue is healthy, but Pass 2 did
        # not produce the selection. Treat that as technical drift, not a new
        # product decision.
        "#{group_key}_selection_missing"
      end

      def classify(profile:, record:, completion:, existing_readiness:)
        return [ :remediation_required, [] ] unless completion.complete?

        if existing_readiness&.publication_applied_at.present? && !(profile.active? && profile.visible?)
          reconciliation.measure!(:native_values_preserved)
          return [ :intentionally_hidden, [ "native_visibility_preserved" ] ]
        end

        # Source-side hard states are moderator/lifecycle actions and override any
        # later destination state — a member Date9ja has hidden, suspended, or
        # discovery-restricted is never shown on D8N, even if a prior pass
        # published them.
        if profile.suspended? || profile.brand_membership.suspended? || profile.user.suspended? || record.suspended?
          return [ :intentionally_hidden, [ "source_suspended" ] ]
        end
        return [ :intentionally_hidden, [ "source_discovery_restricted" ] ] if record.discovery_restricted?
        return [ :intentionally_hidden, [ "legacy_profile_hidden" ] ] if record.profile_hidden

        unless profile.user.active? && profile.brand_membership.active?
          return [ :intentionally_hidden, [ "destination_unavailable" ] ]
        end

        # Identity import never activates a profile. An already active/visible
        # destination reflects a later native/operator decision and is kept.
        if profile.active? && profile.visible?
          reconciliation.measure!(:native_values_preserved)
          return [ :ready, [ "native_visibility_preserved" ] ]
        end

        # Date9ja's own discovery predicate (`index_users_on_discovery_eligible`:
        # not deleted/banned/suspended/discovery_restricted and profile_hidden =
        # false) does NOT require `onboarding_completed_at`. A member Date9ja
        # shows in discovery is shown on D8N.
        [ :ready, [] ]
      end

      def suppress_previously_imported_ineligible!(record)
        profile = Migration::ReferenceMap.resolved(
          source_system: SOURCE_SYSTEM, source_entity: "profile", source_id: record.source_id
        )
        return if profile.nil?

        reason = record.banned? ? "source_banned" : "source_soft_deleted"
        ActiveRecord::Base.transaction(requires_new: true) do
          Profiles::Publication.deactivate!(user: profile.user, brand:) if profile.active? || profile.visible?
          persist_readiness!(
            record:, profile:, disposition: :intentionally_hidden,
            reasons: [ reason ], publication_applied_at: readiness_for(record)&.publication_applied_at,
            applied_fields: Array(readiness_for(record)&.applied_fields)
          )
        end
      rescue StandardError
        # Identity import normally never creates these profiles. A pre-existing
        # row is defence-in-depth; failure remains visible in the source
        # ineligible count and can be inspected via ordinary lifecycle checks.
        reconciliation.measure!(:ineligible_suppression_failed)
      end

      def persist_readiness!(record:, profile:, disposition:, reasons:, publication_applied_at:, applied_fields:)
        readiness = readiness_for(record) || Migration::ProfileReadiness.new(
          source_system: SOURCE_SYSTEM, source_entity: SOURCE_ENTITY, source_id: record.source_id
        )
        readiness.assign_attributes(
          brand:, user: profile.user, profile:, disposition:, reason_codes: reasons,
          applied_fields:,
          importer_version:, source_fingerprint: record.readiness_fingerprint,
          assessed_at: Time.current, publication_applied_at:
        )
        readiness.save!
      end

      def persist_failure(record, reason, profile: nil)
        readiness = readiness_for(record) || Migration::ProfileReadiness.new(
          source_system: SOURCE_SYSTEM, source_entity: SOURCE_ENTITY, source_id: record.source_id
        )
        readiness.assign_attributes(
          brand:, user: profile&.user, profile:, disposition: :failed,
          reason_codes: [ reason ], applied_fields: Array(readiness.applied_fields), importer_version:,
          source_fingerprint: record.readiness_fingerprint, assessed_at: Time.current
        )
        readiness.save!
      rescue StandardError
        # The aggregate reconciliation still accounts for the failure. Never
        # leak the underlying exception or source row into logs/evidence.
        nil
      end

      def readiness_for(record)
        Migration::ProfileReadiness.find_by(
          source_system: SOURCE_SYSTEM, source_entity: SOURCE_ENTITY, source_id: record.source_id
        )
      end
    end
  end
end
