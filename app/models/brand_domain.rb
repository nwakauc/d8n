class BrandDomain < ApplicationRecord
  belongs_to :brand

  enum :status, { active: 0, disabled: 1 }

  scope :kept, -> { where(deleted_at: nil) }

  before_validation :normalize_host

  validates :host, presence: true, uniqueness: { conditions: -> { kept } }

  private

  def normalize_host
    self.host = host.to_s.strip.downcase.delete_suffix(".")
  end
end
