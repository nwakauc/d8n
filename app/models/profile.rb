class Profile < ApplicationRecord
  MINIMUM_AGE = 18

  belongs_to :user
  belongs_to :brand
  belongs_to :brand_membership

  has_one :profile_preference, dependent: :restrict_with_exception
  has_many :profile_photos, dependent: :restrict_with_exception

  enum :status, { draft: 0, active: 1, suspended: 2 }
  enum :visibility, { hidden: 0, visible: 1 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :user_id, uniqueness: { scope: :brand_id, conditions: -> { kept } }
  validates :display_name, length: { maximum: 80 }, allow_blank: true
  validates :bio, length: { maximum: 1_000 }, allow_blank: true
  validate :birthdate_meets_minimum_age
  validate :brand_membership_matches_profile_scope

  private

  def birthdate_meets_minimum_age
    return if birthdate.blank?
    return if birthdate <= MINIMUM_AGE.years.ago.to_date

    errors.add(:birthdate, "must be at least #{MINIMUM_AGE} years ago")
  end

  def brand_membership_matches_profile_scope
    return if brand_membership.blank?
    return if brand_membership.user_id == user_id && brand_membership.brand_id == brand_id

    errors.add(:brand_membership, "must belong to the same user and brand")
  end
end
