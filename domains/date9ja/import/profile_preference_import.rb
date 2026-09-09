# frozen_string_literal: true

require "digest"

module Date9ja
  module Import
    # Second structural movement of Date9ja members into D8N: the half that
    # makes a migrated member discoverable.
    #
    #   Date9ja::Snapshot::UserSource
    #     -> decode profiles.gender          ("0"/"1" -> "man"/"woman")
    #     -> ProfilePreference               (interested_in, min_age, max_age)
    #     -> ProfileOptionSelection          (relationship_intent, has_children,
    #                                         wants_children)
    #     -> Migration::ReferenceMap binding (profile_preference)
    #     -> deterministic, PII-free ProfilePreferenceReconciliation
    #
    # WHY THIS EXISTS. The identity importer deliberately created no preference
    # rows, and `Matching::ProfileParticipant` requires min_age, max_age and a
    # non-empty interested_in — so every migrated member was excluded from
    # matching entirely. It also copied `users.gender` through unchanged, and
    # since the legacy column is an integer enum that wrote the strings "0"/"1"
    # into `profiles.gender`, which `Matching::EligibilityScope` compares
    # verbatim against `interested_in`. Both halves are fixed here.
    #
    # WHAT IT NEVER DOES.
    #   * It never invents a value. A field the member did not answer stays
    #     unset, and a legacy code with no approved D8N destination stays unset
    #     (ValueMapping fails closed). Both are recorded as reconciliation notes.
    #   * It never overwrites a member's own answer. Re-running only fills gaps
    #     and re-decodes gender; a value already in D8N is left alone.
    #   * It touches no sensitive column — those are still gated by
    #     FieldMapping::SENSITIVE_DENYLIST and never leave the snapshot.
    #
    # Every source row runs in its own savepointed transaction: a row that fails
    # leaves nothing behind and is retried cleanly on the next run.
    class ProfilePreferenceImport
      SOURCE_SYSTEM = "date9ja"
      IMPORTER_VERSION = "date9ja-profile-preference-v1"
      PREFERENCE_ENTITY = "profile_preference"

      # Legacy code -> D8N option group. Order is the order selections are
      # written, so a re-run produces the identical sequence.
      OPTION_GROUPS = {
        "relationship_intent" => :relationship_intention,
        "has_children" => :children_count,
        "wants_children" => :wants_children,
        # D8N contract-fidelity pass: every legacy preference/lifestyle enum now
        # has a D8N option group. All fail closed on an unknown code (none does
        # today — the mappings are total) and none is a publication gate.
        "children_count" => :children_count,
        "family_involvement_level" => :family_involvement_preference,
        "commitment_timeline" => :commitment_timeline,
        "marital_status" => :marital_status,
        "education_level" => :education
      }.freeze

      Result = Data.define(:reconciliation)

      class WrongBrand < StandardError; end
      class OptionSelectionFailure < StandardError
        attr_reader :reason

        def initialize(reason)
          @reason = reason
          super(reason)
        end
      end

      def self.call(...) = new(...).call

      def initialize(brand:, source:, importer_version: IMPORTER_VERSION)
        @brand = brand
        @source = source
        @importer_version = importer_version
        @reconciliation = ProfilePreferenceReconciliation.new
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

        raise WrongBrand, "profile & preference import requires the active date9ja brand"
      end

      def import_one(record)
        # Same eligibility rule as the identity importer, for the same reason:
        # a row it skipped has no Profile to hang a preference off.
        return reconciliation.skipped!("source_soft_deleted") if record.soft_deleted?
        return reconciliation.skipped!("source_banned") if record.banned?

        profile_reference = reference("profile", record)
        return reconciliation.skipped!("profile_not_imported") if profile_reference.nil?

        unless profile_reference.resolvable?
          reconciliation.anomaly!(:binding_conflicts)
          return reconciliation.failed!("dangling_binding")
        end

        profile = profile_reference.destination
        existing = reference(PREFERENCE_ENTITY, record)
        return already_imported_or_dangling(existing, profile, record) if existing

        persist(profile, record)
      rescue OptionSelectionFailure => error
        reconciliation.anomaly!(:malformed_rows)
        reconciliation.failed!(error.reason)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
        reconciliation.anomaly!(:malformed_rows)
        reconciliation.failed!("preference_invalid")
      rescue Migration::ReferenceMap::Error
        reconciliation.anomaly!(:binding_conflicts)
        reconciliation.failed!("binding_conflict")
      end

      # A prior run already bound a ProfilePreference for this member. Re-running
      # must be a no-op for anything already written, but it must still fill gaps
      # a previous run left open — a code that was unmapped then may be mapped
      # now that a decision has landed.
      def already_imported_or_dangling(existing, profile, record)
        unless existing.resolvable?
          reconciliation.anomaly!(:binding_conflicts)
          return reconciliation.failed!("dangling_binding")
        end

        decoded = false
        ActiveRecord::Base.transaction(requires_new: true) do
          decoded = decode_gender!(profile, record)
          fill_preference_gaps!(existing.destination, record)
          apply_option_selections!(profile, record)
        end
        reconciliation.already_imported!
        reconciliation.decoded_gender! if decoded
      end

      def persist(profile, record)
        preference = nil
        selections = 0
        decoded = false

        ActiveRecord::Base.transaction(requires_new: true) do
          decoded = decode_gender!(profile, record)

          preference = ProfilePreference.create!(
            profile:, user_id: profile.user_id, brand_id: brand.id,
            **preference_attributes(record)
          )
          Migration::ReferenceMap.bind!(
            source_system: SOURCE_SYSTEM, source_entity: PREFERENCE_ENTITY,
            source_id: record.source_id, destination: preference, brand:,
            importer_version:, fingerprint: preference_fingerprint(record)
          )
          selections = apply_option_selections!(profile, record)
        end

        reconciliation.imported!(
          preferences_created: 1, option_selections_created: selections,
          legacy_references_created: 1, genders_decoded: decoded ? 1 : 0
        )
      end

      # --- gender ------------------------------------------------------------

      # `profiles.gender` is what EligibilityScope matches against, so it has to
      # hold the same vocabulary as interested_in. The identity importer wrote
      # the raw legacy code; decode it in place. Only ever rewrites a value that
      # is still a legacy code — a member's own D8N value is never touched.
      # Returns true when it actually rewrote the column.
      def decode_gender!(profile, record)
        outcome = ValueMapping.gender(record.gender)
        if outcome.absent?
          reconciliation.note!("gender_absent")
          return false
        end
        if outcome.unmapped?
          reconciliation.note!("gender_unmapped")
          return false
        end
        return false if profile.gender == outcome.value

        # Guard: only a raw legacy code is replaced. If the profile already holds
        # something else, a member (or a later slice) set it and it stands.
        return false unless legacy_gender_code?(profile.gender)

        profile.update!(gender: outcome.value)
        true
      end

      def legacy_gender_code?(value) = value.to_s.match?(/\A\d+\z/)

      # --- preference --------------------------------------------------------

      def preference_attributes(record)
        { interested_in: interested_in_for(record) }.merge(age_range_for(record))
      end

      def interested_in_for(record)
        outcome = ValueMapping.interested_in(record.looking_for)
        if outcome.absent?
          reconciliation.note!("interested_in_absent")
          return []
        end
        if outcome.unmapped?
          reconciliation.note!("interested_in_unmapped")
          return []
        end

        outcome.value.dup
      end

      # Migrated verbatim when the pair is valid. `preferred_distance_km` is NULL
      # for every source row (census 240) and D-10 was resolved by relaxing the
      # requirement rather than inventing a distance, so max_distance_km is never
      # written here.
      def age_range_for(record)
        min = integer_or_nil(record.preferred_age_min)
        max = integer_or_nil(record.preferred_age_max)

        if min.nil? && max.nil?
          reconciliation.note!("age_range_absent")
          return { min_age: nil, max_age: nil }
        end

        # A half-answered range is NOT invalid data -- the member simply gave one
        # bound. Reporting it as `age_range_invalid` would contradict the Pass-1
        # census, which proved zero out-of-range and zero inverted values, and
        # would send a reviewer looking for corrupt data that does not exist.
        if min.nil? || max.nil?
          reconciliation.note!("age_range_partial")
          return { min_age: nil, max_age: nil }
        end

        unless valid_age_range?(min, max)
          reconciliation.note!("age_range_invalid")
          return { min_age: nil, max_age: nil }
        end

        { min_age: min, max_age: max }
      end

      def valid_age_range?(min, max)
        return false if min.nil? || max.nil?

        min.between?(ProfilePreference::MINIMUM_AGE, ProfilePreference::MAXIMUM_AGE) &&
          max.between?(ProfilePreference::MINIMUM_AGE, ProfilePreference::MAXIMUM_AGE) &&
          min <= max
      end

      def integer_or_nil(value)
        return nil if value.nil?
        return value if value.is_a?(Integer)

        text = value.to_s.strip
        text.match?(/\A-?\d+\z/) ? Integer(text, 10) : nil
      end

      # Fills only what a previous run left unset. Never overwrites a stored
      # answer — the member may have changed it in D8N since.
      def fill_preference_gaps!(preference, record)
        attrs = {}
        if preference.interested_in.blank?
          candidate = interested_in_for(record)
          attrs[:interested_in] = candidate if candidate.present?
        end
        if preference.min_age.nil? && preference.max_age.nil?
          range = age_range_for(record)
          attrs.merge!(range) if range[:min_age] || range[:max_age]
        end
        preference.update!(attrs) if attrs.any?
      end

      # --- option selections -------------------------------------------------

      # Recorded once per member so the reconciliation shows plainly that these
      # were never fabricated: the legacy source simply has nothing to migrate.
      NO_SOURCE_NOTES = %w[ max_distance_km_no_source meeting_pace_no_source ].freeze

      # Writes one selection per mappable group. Idempotent: a selection that
      # already exists is left exactly as it is, so a re-run never duplicates a
      # row and never overrules a member who changed their answer in D8N.
      def apply_option_selections!(profile, record)
        created = 0

        OPTION_GROUPS.each do |group_key, source_attribute|
          outcome = ValueMapping.lookup(group_key, record.public_send(source_attribute))
          if outcome.absent?
            reconciliation.note!("#{group_key}_absent")
            next
          end
          if outcome.unmapped?
            reconciliation.note!("#{group_key}_unmapped")
            next
          end

          created += 1 if select_option!(profile, group_key, outcome.value)
        end

        NO_SOURCE_NOTES.each { |note| reconciliation.note!(note) }
        created
      end

      def select_option!(profile, group_key, option_code)
        group = option_group(group_key)
        raise OptionSelectionFailure, "approved_option_group_missing" if group.nil?

        option = group.profile_options.kept.find_by(code: option_code)
        raise OptionSelectionFailure, "approved_option_missing" if option.nil?

        # Any kept selection in this group means the member has an answer —
        # theirs or a previous run's. Either way it stands.
        return false if ProfileOptionSelection.kept.exists?(profile:, profile_option_group: group)

        ProfileOptionSelection.create!(
          profile:, user_id: profile.user_id, brand_id: brand.id,
          profile_option_group: group, profile_option: option
        )
        true
      rescue ActiveRecord::RecordInvalid => error
        raise OptionSelectionFailure.new("option_selection_invalid"), cause: error
      end

      def option_group(key)
        @option_groups ||= {}
        return @option_groups[key] if @option_groups.key?(key)

        @option_groups[key] = ProfileOptionGroup.kept.find_by(brand_id: brand.id, key:)
      end

      # --- bindings ----------------------------------------------------------

      def reference(entity, record)
        Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: entity, source_id: record.source_id
        )
      end

      # Change detection for the preference binding only. Deliberately distinct
      # from UserRecord#fingerprint (the identity slice's) so adding this slice
      # cannot make every existing identity binding look drifted.
      def preference_fingerprint(record)
        material = [
          record.looking_for, record.preferred_age_min, record.preferred_age_max,
          record.preferred_distance_km, record.relationship_intention,
          record.wants_children, record.children_count,
          record.family_involvement_preference, record.commitment_timeline,
          record.marital_status, record.education
        ].map(&:to_s).join("|")
        Digest::SHA256.hexdigest(material)[0, 32]
      end
    end
  end
end
