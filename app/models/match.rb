class Match < ApplicationRecord
  belongs_to :brand
  belongs_to :profile_a, class_name: "Profile"
  belongs_to :profile_b, class_name: "Profile"

  enum :status, { active: 0, ended: 1 }, prefix: true

  scope :kept, -> { where(deleted_at: nil) }

  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :profile_a_id,
    uniqueness: { scope: [ :brand_id, :profile_b_id ], conditions: -> { kept.status_active } }
  validate :profiles_match_brand
  validate :participants_are_canonical

  before_validation :ensure_public_id, on: :create

  def self.canonical_pair(first_profile_id, second_profile_id)
    [ first_profile_id, second_profile_id ].sort
  end

  def other_profile(profile)
    profile.id == profile_a_id ? profile_b : profile_a
  end

  private

  def ensure_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def profiles_match_brand
    return if profile_a.blank? || profile_b.blank?
    return if profile_a.brand_id == brand_id && profile_b.brand_id == brand_id

    errors.add(:base, "profiles must belong to the same brand")
  end

  def participants_are_canonical
    return if profile_a_id.blank? || profile_b_id.blank? || profile_a_id < profile_b_id

    errors.add(:base, "profile_a_id must be less than profile_b_id")
  end
end
