# frozen_string_literal: true

module Date9ja
  module Import
    # Preserves the SENSITIVE Date9ja profile values — religion / tribe /
    # ethnicity / denomination / genotype / state_of_origin / nationality /
    # is_nigerian / the openness flags / the matching-preference arrays /
    # interest_in_nigerian_culture.
    #
    # Governing rule: sensitivity governs HOW, not WHETHER. Every one of these
    # has a D8N destination (Profiles::CapabilityCatalog option group,
    # Profiles::FieldCatalog scalar, or ProfilePreference#preferred_attributes),
    # all owner-only.
    #
    # WHAT IT NEVER DOES.
    #   * Never invents a value. A field the member did not answer stays unset;
    #     a legacy value with no reviewed D8N code stays unset (quarantined).
    #     Both are recorded as reconciliation notes.
    #   * Never overwrites a member/operator/earlier value. Gap-fill only.
    #   * Never widens exposure — every destination is owner-only.
    #   * Never logs a raw member value. Evidence is a PII-free fingerprint.
    #
    # It reads through the dedicated `SensitiveUserSource` (the ONLY adapter for
    # these columns) so the firewall around the ordinary import path is intact.
    # On the sanitized rehearsal snapshot every value is NULL/'{}', so this pass
    # writes nothing and every field is noted `_absent`.
    class SensitiveProfileImport
      SOURCE_SYSTEM = "date9ja"
      IMPORTER_VERSION = "date9ja-sensitive-profile-v1"

      SCALAR_MAPPINGS = {
        "state_of_origin" => NigerianStateMapping,
        "nationality" => CountryMapping
      }.freeze

      OPTION_GROUP_MAPPINGS = {
        "tribe" => -> { SensitiveVocabularies::TRIBE },
        "ethnicity" => -> { SensitiveVocabularies::ETHNICITY },
        "religion" => -> { SensitiveVocabularies::RELIGION },
        "denomination" => -> { SensitiveVocabularies::DENOMINATION },
        "genotype" => -> { SensitiveVocabularies::GENOTYPE },
        "intertribal_marriage_openness" => -> { SensitiveVocabularies::INTERTRIBAL_MARRIAGE_OPENNESS },
        "polygamy_openness" => -> { SensitiveVocabularies::POLYGAMY_OPENNESS }
      }.freeze

      PREFERRED_ATTRIBUTE_SOURCES = {
        "religion" => :preferred_religion,
        "tribe" => :preferred_tribes,
        "ethnicity" => :preferred_ethnicity,
        "genotype" => :preferred_genotype
      }.freeze

      Result = Data.define(:reconciliation)

      class WrongBrand < StandardError; end
      class SensitiveWriteFailure < StandardError; end

      def self.call(...) = new(...).call

      def initialize(brand:, source:, importer_version: IMPORTER_VERSION)
        @brand = brand
        @source = source
        @importer_version = importer_version
        @reconciliation = SensitiveProfileReconciliation.new
        @groups = {}
      end

      def call
        assert_brand!
        @source.each do |record|
          reconciliation.considered
          import_one(record)
        end
        Result.new(reconciliation)
      end

      private

      attr_reader :brand, :importer_version, :reconciliation

      def assert_brand!
        return if brand&.slug == SOURCE_SYSTEM && brand.active? && brand.deleted_at.nil?

        raise WrongBrand, "sensitive profile import requires the active date9ja brand"
      end

      def import_one(record)
        return reconciliation.skipped!("source_soft_deleted") if record.soft_deleted?
        return reconciliation.skipped!("source_banned") if record.banned?

        # The identity pass already owns the Profile <-> "profile" binding; this
        # pass reuses it to resolve and does NOT create a binding of its own
        # (ReferenceMap destinations are single-claim). Idempotence comes from
        # the gap-fill checks below, not a marker — a rerun re-processes and
        # writes nothing new.
        profile = reference("profile", record)&.destination
        return reconciliation.skipped!("profile_not_imported") if profile.nil?

        counters = { scalars_written: 0, option_selections_created: 0, preference_attributes_written: 0 }
        ActiveRecord::Base.transaction(requires_new: true) do
          counters = apply_all!(profile, record)
        end
        reconciliation.imported!(**counters)
      rescue SensitiveWriteFailure, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
        reconciliation.failed!("sensitive_write_invalid")
      end

      def apply_all!(profile, record)
        scalars = apply_is_nigerian!(profile, record)
        scalars += apply_scalar_mappings!(profile, record)
        scalars += apply_free_text!(profile, record)
        scalars += apply_v2_onboarding_answers!(profile, record)
        selections = apply_option_groups!(profile, record)
        prefs = apply_preferred_attributes!(profile, record)
        { scalars_written: scalars, option_selections_created: selections, preference_attributes_written: prefs }
      end

      # --- scalars ---------------------------------------------------------

      def apply_is_nigerian!(profile, record)
        if record.is_nigerian.nil?
          reconciliation.note!("is_nigerian_absent")
          return 0
        end
        unless profile.is_nigerian.nil?
          reconciliation.note!("is_nigerian_preserved")
          return 0
        end

        profile.update!(is_nigerian: record.is_nigerian)
        reconciliation.note!("is_nigerian_mapped")
        1
      end

      def apply_scalar_mappings!(profile, record)
        written = 0
        SCALAR_MAPPINGS.each do |column, mapping|
          source_value = record.public_send(column)
          if source_value.blank?
            reconciliation.note!("#{column}_absent")
            next
          end
          if profile.public_send(column).present?
            reconciliation.note!("#{column}_preserved")
            next
          end

          outcome = mapping.call(source_value)
          unless outcome.mapped?
            reconciliation.note!("#{column}_unmapped")
            next
          end

          value = column == "state_of_origin" ? outcome.state : outcome.country_code
          profile.update!(column => value)
          reconciliation.note!("#{column}_mapped")
          written += 1
        end
        written
      end

      def apply_free_text!(profile, record)
        raw = record.interest_in_nigerian_culture
        if raw.blank?
          reconciliation.note!("interest_in_nigerian_culture_absent")
          return 0
        end
        if profile.interest_in_nigerian_culture.present?
          reconciliation.note!("interest_in_nigerian_culture_preserved")
          return 0
        end

        profile.update!(interest_in_nigerian_culture: raw.to_s.strip[0, 1_000])
        reconciliation.note!("interest_in_nigerian_culture_mapped")
        1
      end

      # The non-genotype V2 onboarding questionnaire answers (faith_practice,
      # family_involvement, language_at_home, settlement, money_providing,
      # children, lifestyle, conflict, custom_religion, ...). Curated D8N option
      # semantics for each question are a later product decision; until then the
      # answers are preserved verbatim in an owner-only profile metadata key so
      # nothing is lost at cutover. Gap-fill: never overwrite an existing copy.
      V2_ONBOARDING_METADATA_KEY = "date9ja_v2_onboarding"

      def apply_v2_onboarding_answers!(profile, record)
        answers = record.v2_onboarding_answers
        answers = {} unless answers.is_a?(Hash)
        if answers.empty?
          reconciliation.note!("v2_onboarding_answers_absent")
          return 0
        end

        metadata = profile.metadata.is_a?(Hash) ? profile.metadata : {}
        if metadata.key?(V2_ONBOARDING_METADATA_KEY)
          reconciliation.note!("v2_onboarding_answers_preserved")
          return 0
        end

        profile.update!(metadata: metadata.merge(V2_ONBOARDING_METADATA_KEY => answers.transform_keys(&:to_s)))
        reconciliation.note!("v2_onboarding_answers_mapped")
        1
      end

      # --- option groups (single-select) ----------------------------------

      def apply_option_groups!(profile, record)
        created = 0
        OPTION_GROUP_MAPPINGS.each do |group_key, mapping_proc|
          source_value = record.public_send(group_key)
          outcome = mapping_proc.call.call(source_value)

          if outcome.absent?
            reconciliation.note!("#{group_key}_absent")
            next
          end

          group = option_group(group_key)
          next if group.nil?
          if ProfileOptionSelection.kept.exists?(profile:, profile_option_group: group)
            reconciliation.note!("#{group_key}_preserved")
            next
          end
          unless outcome.mapped?
            if group_key == "genotype" && outcome.unmapped? && source_value.present?
              preserve_unclassified_genotype!(profile, source_value)
              outcome = ControlledVocabularyMapping::Outcome.new(status: :mapped, code: "other")
            end
          end
          unless outcome.mapped?
            reconciliation.note!("#{group_key}_unmapped")
            next
          end

          option = group.profile_options.kept.find_by(code: outcome.code)
          raise SensitiveWriteFailure, "missing option #{group_key}:#{outcome.code}" if option.nil?

          ProfileOptionSelection.create!(
            profile:, user_id: profile.user_id, brand_id: brand.id,
            profile_option_group: group, profile_option: option
          )
          reconciliation.note!("#{group_key}_mapped")
          created += 1
        end
        created
      end

      def preserve_unclassified_genotype!(profile, value)
        metadata = profile.metadata.is_a?(Hash) ? profile.metadata : {}
        return if metadata.key?("date9ja_genotype_raw")

        profile.update!(metadata: metadata.merge("date9ja_genotype_raw" => value.to_s))
        reconciliation.note!("genotype_unclassified_preserved")
      end

      # --- matching preferences (preferred_attributes hash) --------------

      def apply_preferred_attributes!(profile, record)
        preference = ProfilePreference.kept.find_by(profile:)
        return 0 if preference.nil?

        current = preference.preferred_attributes.deep_dup
        written = 0
        PREFERRED_ATTRIBUTE_SOURCES.each do |key, source_attr|
          values = Array(record.public_send(source_attr))
          if values.empty?
            reconciliation.note!("preferred_#{plural(key)}_absent")
            next
          end
          if current.key?(key)
            reconciliation.note!("preferred_#{plural(key)}_preserved")
            next
          end

          outcome = SensitiveVocabularies::PREFERRED.fetch(key).call_many(values)
          if outcome.codes.empty?
            if key == "genotype"
              metadata = profile.metadata.is_a?(Hash) ? profile.metadata : {}
              unless metadata.key?("date9ja_preferred_genotype_raw")
                profile.update!(metadata: metadata.merge("date9ja_preferred_genotype_raw" => values.map(&:to_s)))
                reconciliation.note!("preferred_genotype_unclassified_preserved")
              end
            end
            reconciliation.note!("preferred_#{plural(key)}_unmapped")
            next
          end

          current[key] = outcome.codes
          reconciliation.note!("preferred_#{plural(key)}_#{outcome.status == :partial ? 'partial' : 'mapped'}")
          written += 1
        end

        preference.update!(preferred_attributes: current) if written.positive?
        written
      end

      # Source columns are `preferred_tribes` / `preferred_religion` etc.; note
      # codes follow the source column name.
      def plural(key) = { "tribe" => "tribes", "religion" => "religion",
        "ethnicity" => "ethnicity", "genotype" => "genotype" }.fetch(key)

      def option_group(key)
        return @groups[key] if @groups.key?(key)

        @groups[key] = ProfileOptionGroup.kept.find_by(brand_id: brand.id, key:)
      end

      def reference(entity, record)
        Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: entity, source_id: record.source_id
        )
      end
    end
  end
end
