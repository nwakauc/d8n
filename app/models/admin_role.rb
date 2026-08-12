class AdminRole < ApplicationRecord
  has_many :admin_assignments, dependent: :restrict_with_exception

  scope :kept, -> { where(deleted_at: nil) }

  validates :name, presence: true, uniqueness: { conditions: -> { kept } }
end
