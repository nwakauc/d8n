class AdminUser < ApplicationRecord
  # Links to the network User the admin signs in as. There is no separate admin
  # credential/session: authentication reuses the ordinary brand-scoped session.
  belongs_to :user, optional: true

  has_many :admin_assignments, dependent: :restrict_with_exception
  has_many :brands, through: :admin_assignments

  enum :status, { active: 0, suspended: 1, disabled: 2 }

  scope :kept, -> { where(deleted_at: nil) }
end
