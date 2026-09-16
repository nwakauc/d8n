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
  validate :preferred_country_codes_are_valid
  validate :preferred_attributes_are_valid

  # A generic owner-only matching-preference store, keyed by attribute. The
  # lossless home for Date9ja's `preferred_religion` / `preferred_tribes` /
  # `preferred_ethnicity` / `preferred_genotype` arrays.
  PREFERRED_ATTRIBUTE_KEYS = %w[religion tribe ethnicity genotype].freeze
  PREFERRED_ATTRIBUTE_MAX_VALUES = 20

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

  # A MULTI-country residence preference, distinct from the scalar `country`.
  # Each element is an ISO-3166 alpha-2 code; shape and limits mirror
  # `interested_in` (Profiles::FieldCatalog "preferred_country_codes").
  def preferred_country_codes_are_valid
    unless preferred_country_codes.is_a?(Array)
      errors.add(:preferred_country_codes, "must be an array")
      return
    end

    limits = Profiles::FieldCatalog.list_limits("preferred_country_codes")
    if preferred_country_codes.size > limits.fetch(:max_entries)
      errors.add(:preferred_country_codes, "cannot have more than #{limits.fetch(:max_entries)} entries")
    end
    if preferred_country_codes.any? { |value| !value.is_a?(String) || !value.match?(/\A[A-Z]{2}\z/) }
      errors.add(:preferred_country_codes, "contains an invalid country code")
    end
  end

  def preferred_attributes_are_valid
    unless preferred_attributes.is_a?(Hash)
      errors.add(:preferred_attributes, "must be an object")
      return
    end

    extra = preferred_attributes.keys.map(&:to_s) - PREFERRED_ATTRIBUTE_KEYS
    errors.add(:preferred_attributes, "has unknown keys: #{extra.join(', ')}") if extra.any?

    preferred_attributes.each_value do |values|
      unless values.is_a?(Array) && values.size <= PREFERRED_ATTRIBUTE_MAX_VALUES &&
          values.all? { |v| v.is_a?(String) && v.length <= 40 }
        errors.add(:preferred_attributes, "values must be arrays of at most #{PREFERRED_ATTRIBUTE_MAX_VALUES} short codes")
        break
      end
    end
  end

  def normalize_preferences
    self.country = country.to_s.strip.upcase.presence
    self.relationship_intent = relationship_intent.to_s.strip.presence
    normalize_interested_in
    normalize_preferred_country_codes
    normalize_preferred_attributes
  end

  def normalize_preferred_attributes
    return unless preferred_attributes.is_a?(Hash)

    self.preferred_attributes = preferred_attributes.each_with_object({}) do |(key, values), acc|
      next unless values.is_a?(Array)

      cleaned = values.filter_map { |v| v.is_a?(String) ? v.strip.downcase.presence : nil }.uniq
      acc[key.to_s] = cleaned if cleaned.any?
    end
  end

  def normalize_interested_in
    return unless interested_in.is_a?(Array)

    self.interested_in = interested_in.map do |value|
      value.is_a?(String) ? value.strip.presence : value
    end.compact.uniq
  end

  def normalize_preferred_country_codes
    return unless preferred_country_codes.is_a?(Array)

    self.preferred_country_codes = preferred_country_codes.map do |value|
      value.is_a?(String) ? value.strip.upcase.presence : value
    end.compact.uniq
  end
end
