class ProfileOptionGroup < ApplicationRecord
  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
  MAX_ALLOWED_SELECTIONS = 50

  belongs_to :brand

  has_many :profile_options, dependent: :restrict_with_exception
  has_many :profile_option_selections, dependent: :restrict_with_exception

  enum :cardinality, { single: 0, multiple: 1 }, prefix: true
  # Visibility governs who may see a group's selections:
  #   owner_only      — only the member themselves (never serialized to others)
  #   public_profile  — any member who can already see the profile
  #   matches_only     — only a member with an active, still-reachable Match
  # `matches_only` lets sensitive-but-shareable capabilities (e.g. intimacy
  # preferences) exist without being locked into the public serializer (ADR 0017).
  enum :visibility, { owner_only: 0, public_profile: 1, matches_only: 2 }, prefix: true
  enum :status, { active: 0, retired: 1 }, prefix: true

  scope :kept, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  validates :key, presence: true, format: { with: KEY_FORMAT },
    uniqueness: { scope: :brand_id, conditions: -> { kept } }
  validates :label, presence: true, length: { maximum: 120 }
  validates :max_selections,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_ALLOWED_SELECTIONS }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :single_group_allows_one_selection
  validate :key_is_immutable, on: :update
  validate :required_group_remains_available, on: :update

  private

  def single_group_allows_one_selection
    return unless cardinality_single? && max_selections != 1

    errors.add(:max_selections, "must be 1 for a single-select group")
  end

  def key_is_immutable
    errors.add(:key, "cannot be changed") if will_save_change_to_key?
  end

  def required_group_remains_available
    return unless will_save_change_to_status? || will_save_change_to_deleted_at?
    return unless status_retired? || deleted_at.present?
    return unless brand.profile_completion_requirements.fetch("option_groups").include?(key)

    errors.add(:base, "required option groups cannot be retired or deleted")
  end
end
