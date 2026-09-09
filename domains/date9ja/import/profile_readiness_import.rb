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
          apply_location!(profile, applied_fields:)

          completion = Profiles::Completion.call(profile:)
          reconciliation.measure!(:complete_after) if completion.complete?
          measure_preference_and_options!(profile)
          reasons.concat(completion_reasons(completion, profile:, record:))

          disposition, state_reasons = classify(
            profile:, record:, completion:, existing_readiness:
          )
          reasons.concat(state_reasons)

          if disposition == :ready && publication_policy == :publish_visible_onboarded && !profile.active?
            Profiles::Publication.activate!(user: profile.user, brand:)
            publication_applied_at ||= Time.current
            reconciliation.measure!(:publications_applied)
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

        if profile.suspended? || profile.brand_membership.suspended? || profile.user.suspended? || record.suspended?
          return [ :intentionally_hidden, [ "source_suspended" ] ]
        end
        unless profile.user.active? && profile.brand_membership.active?
          return [ :intentionally_hidden, [ "destination_unavailable" ] ]
        end

        # Identity import never activates a profile. An already active/visible
        # destination therefore reflects a later native/operator decision and
        # takes precedence over the legacy snapshot.
        if profile.active? && profile.visible?
          reconciliation.measure!(:native_values_preserved)
          return [ :ready, [ "native_visibility_preserved" ] ]
        end
        return [ :intentionally_hidden, [ "legacy_profile_hidden" ] ] if record.profile_hidden
        return [ :remediation_required, [ "legacy_visibility_decision_required" ] ] if record.onboarding_completed_at.blank?

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
