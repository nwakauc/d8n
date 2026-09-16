module Migration
  # Current, PII-free readiness result for one source member. This is migration
  # control-plane state only; runtime profile completion and publication remain
  # owned by Profiles::Completion and Profiles::Publication.
  class ProfileReadiness < ApplicationRecord
    self.table_name = "migration_profile_readinesses"

    belongs_to :brand
    belongs_to :user, optional: true
    belongs_to :profile, optional: true

    enum :disposition, {
      ready: 0,
      intentionally_hidden: 1,
      remediation_required: 2,
      failed: 3
    }, prefix: true

    validates :source_system, :source_entity, :source_id, :importer_version, :assessed_at, presence: true
    validates :source_system, inclusion: { in: Migration::SourceSystems::KNOWN }
    validates :source_entity,
      format: { with: Migration::SourceSystems::ENTITY_FORMAT },
      length: { maximum: Migration::SourceSystems::ENTITY_MAX_LENGTH }
    validates :source_id, :source_fingerprint, :importer_version, length: { maximum: 255 }
    validates :source_id, uniqueness: { scope: [ :source_system, :source_entity ] }
    validates :profile_id, uniqueness: true, allow_nil: true
    validate :coded_arrays_are_safe
    validate :profile_matches_scope
    validate :resolved_disposition_has_destination

    before_validation :normalize_coded_arrays

    private

    def normalize_coded_arrays
      self.reason_codes = normalize_codes(reason_codes) if reason_codes.is_a?(Array)
      self.applied_fields = normalize_codes(applied_fields) if applied_fields.is_a?(Array)
    end

    def normalize_codes(values) = values.map(&:to_s).uniq.sort

    def coded_arrays_are_safe
      { reason_codes:, applied_fields: }.each do |attribute, values|
        unless values.is_a?(Array)
          errors.add(attribute, "must be an array")
          next
        end
        unless values.all? { |code| code.match?(/\A[a-z][a-z0-9_]*\z/) && code.length <= 80 }
          errors.add(attribute, "contains an invalid code")
        end
      end
    end

    def profile_matches_scope
      return if profile.nil? && user.nil?
      if profile.nil? || user.nil?
        errors.add(:profile, "and user must either both be present or both be absent")
        return
      end
      return if profile.user_id == user_id && profile.brand_id == brand_id

      errors.add(:profile, "must belong to the same user and brand")
    end

    def resolved_disposition_has_destination
      return if disposition_failed? || (profile.present? && user.present?)

      errors.add(:profile, "is required for a resolved disposition")
    end
  end
end
