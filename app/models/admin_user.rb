class AdminUser < ApplicationRecord
  has_many :admin_assignments, dependent: :restrict_with_exception
  has_many :brands, through: :admin_assignments

  enum :status, { active: 0, suspended: 1, disabled: 2 }

  scope :kept, -> { where(deleted_at: nil) }
end
