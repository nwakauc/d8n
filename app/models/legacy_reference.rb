# One immutable binding between a row in a foreign system and the D8N record it
# was imported as (ADR 0022). Written only by Migration::ReferenceMap during
# import/reconciliation; never read by consumer-facing code, and raw source
# identifiers never leave this table.
class LegacyReference < ApplicationRecord
  # Null for a platform-owned destination (e.g. User); required for a
  # brand-owned one so a cross-tenant binding is a query, not an audit.
  belongs_to :brand, optional: true

  validates :source_system, :source_entity, :source_id, :destination_type, :destination_id,
    :importer_version, presence: true
  validates :source_id, :source_fingerprint, :importer_version, length: { maximum: 255 }
  validate :source_system_is_known
  validate :source_entity_is_valid
  validate :destination_type_is_known
  validate :brand_matches_destination_ownership

  # DB enforces both directions too (idx_legacy_references_source_key /
  # _destination_key); these give friendly errors before hitting the constraint.
  validates :source_id,
    uniqueness: { scope: [ :source_system, :source_entity ], case_sensitive: true }
  validates :destination_id,
    uniqueness: { scope: [ :source_system, :destination_type ], case_sensitive: true }

  before_update :reject_rebinding

  scope :for_source, ->(system) { where(source_system: system.to_s) }

  # The concrete D8N record, or nil if it has since been hard-deleted. A nil here
  # is a reconciliation finding, not a validation error — the binding stays.
  def destination
    return @destination if defined?(@destination)

    klass = destination_type.safe_constantize
    @destination = klass&.find_by(id: destination_id)
  end

  def resolvable?
    destination.present?
  end

  # Safe to log: the source id is reduced to a short digest so an operator can
  # correlate rows without the raw legacy identifier appearing anywhere.
  def redacted_key
    digest = Digest::SHA256.hexdigest("#{source_system}:#{source_entity}:#{source_id}")[0, 12]
    "#{source_system}:#{source_entity}:#{digest}"
  end

  private

  def source_system_is_known
    return if Migration::SourceSystems.known?(source_system)

    errors.add(:source_system, "is not a known migration source system")
  end

  def source_entity_is_valid
    return if source_entity.blank? # presence validation handles the empty case
    return if Migration::SourceSystems.valid_entity?(source_entity)

    errors.add(:source_entity, "is not a valid source entity name")
  end

  def destination_type_is_known
    return if destination_type.blank?
    return if Migration::DestinationTypes.known?(destination_type)

    errors.add(:destination_type, "is not a bindable D8N destination type")
  end

  def brand_matches_destination_ownership
    return if destination_type.blank? || !Migration::DestinationTypes.known?(destination_type)

    if Migration::DestinationTypes.brand_owned?(destination_type) && brand_id.blank?
      errors.add(:brand, "is required for a brand-owned destination")
    elsif Migration::DestinationTypes.platform?(destination_type) && brand_id.present?
      errors.add(:brand, "must be null for a platform-owned destination")
    end
  end

  def reject_rebinding
    immutable = changed & %w[source_system source_entity source_id destination_type destination_id brand_id]
    return if immutable.empty?

    raise ActiveRecord::ReadOnlyRecord,
      "legacy reference binding is immutable (#{redacted_key}); rebinding needs an explicit data migration"
  end
end
