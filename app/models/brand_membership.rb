class BrandMembership < ApplicationRecord
  belongs_to :user
  belongs_to :brand

  has_one :profile, dependent: :restrict_with_exception
  has_many :find_profile_exposures, dependent: :restrict_with_exception

  enum :status, { active: 0, suspended: 1, left: 2 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :user_id, uniqueness: { scope: :brand_id, conditions: -> { kept } }
end
