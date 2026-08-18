class ProfilePrompt < ApplicationRecord
  # A brand-configurable prompt *definition* ("A perfect night for me is…"). Copy
  # lives in `text` so it can change without a data migration; `key` is the stable
  # machine identifier. Generic and reusable — each D8N brand seeds its own set via
  # the capability catalogue (ADR 0017). Mirrors ProfileOptionGroup's shape.
  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  belongs_to :brand

  has_many :prompt_answers, class_name: "ProfilePromptAnswer", dependent: :restrict_with_exception

  enum :status, { active: 0, retired: 1 }, prefix: true

  scope :kept, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  validates :key, presence: true, format: { with: KEY_FORMAT },
    uniqueness: { scope: :brand_id, conditions: -> { kept } }
  validates :text, presence: true, length: { maximum: 160 }
  validates :category, length: { maximum: 40 }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :key_is_immutable, on: :update

  private

  def key_is_immutable
    errors.add(:key, "cannot be changed") if will_save_change_to_key?
  end
end
