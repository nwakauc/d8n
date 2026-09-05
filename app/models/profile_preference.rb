class ProfilePreference < ApplicationRecord
  # Shared domain constants (also used by Matching::Find::Filter and the
  # geography catalogues). Their values agree with — and are pinned by test to —
  # the canonical Profiles::FieldCatalog scalar constraints for the matching
  # preference fields.
  MINIMUM_AGE = Profile::MINIMUM_AGE
  MAXIMUM_AGE = 120
  MAX_DISTANCE_KM = 500

  belongs_to :profile
  belongs_to :user
  belongs_to :brand

  scope :kept, -> { where(deleted_at: nil) }

  validates :profile_id, uniqueness: { conditions: -> { kept } }
  validates :user_id, uniqueness: { scope: :brand_id, conditions: -> { kept } }

  # Canonical scalar constraints — values owned by Profiles::FieldCatalog; the
  # rules stay explicit. Range ordering and interested_in shape stay hand-written.
  catalog = Profiles::FieldCatalog
  validates :min_age, numericality: catalog.numericality("min_age"), allow_nil: true
  validates :max_age, numericality: catalog.numericality("max_age"), allow_nil: true
  validates :max_distance_km, numericality: catalog.numericality("max_distance_km"), allow_nil: true
  validates :relationship_intent, length: { maximum: catalog.max_length("relationship_intent") }, allow_blank: true
  validates :country, length: { maximum: catalog.max_length("country") }, allow_blank: true
  validate :age_range_is_ordered
  validate :profile_matches_scope
  validate :interested_in_is_array

  before_validation :normalize_preferences

  private

  def age_range_is_ordered
    return if min_age.blank? || max_age.blank?
    return if min_age <= max_age

    errors.add(:max_age, "must be greater than or equal to min_age")
  end

  def profile_matches_scope
    return if profile.blank?
    return if profile.user_id == user_id && profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same user and brand")
  end

  def interested_in_is_array
    unless interested_in.is_a?(Array)
      errors.add(:interested_in, "must be an array")
      return
    end

    limits = Profiles::FieldCatalog.list_limits("interested_in")
    if interested_in.size > limits.fetch(:max_entries)
      errors.add(:interested_in, "cannot have more than #{limits.fetch(:max_entries)} entries")
    end
    if interested_in.any? { |value| !value.is_a?(String) || value.length > limits.fetch(:item_max_length) }
      errors.add(:interested_in, "contains an invalid value")
    end
  end

  def normalize_preferences
    self.country = country.to_s.strip.upcase.presence
    self.relationship_intent = relationship_intent.to_s.strip.presence
    return unless interested_in.is_a?(Array)

    self.interested_in = interested_in.map do |value|
      value.is_a?(String) ? value.strip.presence : value
    end.compact.uniq
  end
end
