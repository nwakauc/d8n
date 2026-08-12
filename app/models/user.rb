class User < ApplicationRecord
  has_many :brand_memberships, dependent: :restrict_with_exception
  has_many :brands, through: :brand_memberships

  enum :status, { active: 0, suspended: 1, closed: 2 }

  scope :kept, -> { where(deleted_at: nil) }
end
