class AdminAssignment < ApplicationRecord
  belongs_to :admin_user
  belongs_to :brand
  belongs_to :admin_role

  enum :status, { active: 0, suspended: 1, revoked: 2 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :admin_user_id, uniqueness: {
    scope: [ :brand_id, :admin_role_id ],
    conditions: -> { kept }
  }
  validates :admin_user_id, uniqueness: {
    scope: :brand_id,
    conditions: -> { kept.active },
    message: "already has an active role for this brand"
  }, if: :active?
end
