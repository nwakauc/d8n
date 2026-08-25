class ProfileLocation < ApplicationRecord
  MAX_ACCURACY_METERS = 100_000
  MAX_FUTURE_SKEW = 5.minutes
  SOURCES = %w[ device manual imported place ].freeze

  belongs_to :profile
  belongs_to :user
  belongs_to :brand
  belongs_to :place, optional: true

  scope :kept, -> { where(deleted_at: nil) }

  validates :profile_id, uniqueness: { conditions: -> { kept } }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :accuracy_meters,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_ACCURACY_METERS }
  validates :source, inclusion: { in: SOURCES }
  validates :captured_at, presence: true
  validate :profile_matches_scope
  validate :captured_at_is_not_too_far_in_future

  private

  def profile_matches_scope
    return if profile.blank?
    return if profile.user_id == user_id && profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same user and brand")
  end

  def captured_at_is_not_too_far_in_future
    return if captured_at.blank? || captured_at <= MAX_FUTURE_SKEW.from_now

    errors.add(:captured_at, "cannot be more than five minutes in the future")
  end
end
