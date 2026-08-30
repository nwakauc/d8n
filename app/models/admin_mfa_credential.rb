class AdminMfaCredential < ApplicationRecord
  belongs_to :admin_user

  enum :status, { pending: 0, active: 1, disabled: 2 }

  encrypts :secret

  scope :kept, -> { where(deleted_at: nil) }

  validates :secret, presence: true
  validates :admin_user_id, uniqueness: { conditions: -> { kept } }

  def confirmed?
    active? && confirmed_at.present?
  end
end
