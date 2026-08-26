class ProfileOpener < ApplicationRecord
  # A brand-configurable curated opener *definition* ("What's your go-to karaoke
  # song?"). Copy lives in `text` so it can change without a data migration;
  # `key` is the stable machine identifier a sender selects. Generic and
  # reusable, mirroring ProfilePrompt's shape — a brand whose opener policy
  # requires curation (see BrandContract::OpenerConfiguration#catalog_required)
  # seeds and enables its own set.
  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  belongs_to :brand

  has_many :hooks, dependent: :restrict_with_exception

  enum :status, { active: 0, retired: 1 }, prefix: true

  scope :kept, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  validates :key, presence: true, format: { with: KEY_FORMAT },
    uniqueness: { scope: :brand_id, conditions: -> { kept } }
  validates :text, presence: true, length: { maximum: 200 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :key_is_immutable, on: :update

  private

  def key_is_immutable
    errors.add(:key, "cannot be changed") if will_save_change_to_key?
  end
end
