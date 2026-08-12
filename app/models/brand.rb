class Brand < ApplicationRecord
  has_many :brand_memberships, dependent: :restrict_with_exception
  has_many :users, through: :brand_memberships
  has_many :admin_assignments, dependent: :restrict_with_exception
  has_many :admin_users, through: :admin_assignments

  enum :status, { active: 0, disabled: 1, archived: 2 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :slug, presence: true, uniqueness: { conditions: -> { kept } }
  validates :name, presence: true
  validates :owner_type, presence: true
end
