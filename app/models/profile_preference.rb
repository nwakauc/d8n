class ProfilePreference < ApplicationRecord
  MINIMUM_AGE = Profile::MINIMUM_AGE
  MAXIMUM_AGE = 120
  MAX_DISTANCE_KM = 500

  belongs_to :profile
  belongs_to :user
  belongs_to :brand

  scope :kept, -> { where(deleted_at: nil) }

  validates :profile_id, uniqueness: { conditions: -> { kept } }
  validates :user_id, uniqueness: { scope: :brand_id, conditions: -> { kept } }
  validates :min_age,
    numericality: { only_integer: true, greater_than_or_equal_to: MINIMUM_AGE, less_than_or_equal_to: MAXIMUM_AGE },
    allow_nil: true
  validates :max_age,
    numericality: { only_integer: true, greater_than_or_equal_to: MINIMUM_AGE, less_than_or_equal_to: MAXIMUM_AGE },
    allow_nil: true
  validates :max_distance_km,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_DISTANCE_KM },
    allow_nil: true
  validates :relationship_intent, length: { maximum: 80 }, allow_blank: true
  validates :country, length: { maximum: 2 }, allow_blank: true
  validate :age_range_is_ordered
  validate :profile_matches_scope
  validate :interested_in_is_array

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
    return if interested_in.is_a?(Array)

    errors.add(:interested_in, "must be an array")
  end
end
