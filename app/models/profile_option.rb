class ProfileOption < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9][a-z0-9_]*\z/

  belongs_to :brand
  belongs_to :profile_option_group

  has_many :profile_option_selections, dependent: :restrict_with_exception

  enum :status, { active: 0, retired: 1 }, prefix: true

  scope :kept, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  validates :code, presence: true, format: { with: CODE_FORMAT },
    uniqueness: { scope: :profile_option_group_id, conditions: -> { kept } }
  validates :label, presence: true, length: { maximum: 120 }
  # Optional taxonomy grouping (e.g. interest categories food/music/travel). Only
  # meaningful for groups that opt into categorized options; null otherwise.
  validates :category, length: { maximum: 40 }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :group_matches_brand
  validate :code_is_immutable, on: :update

  private

  def group_matches_brand
    return if profile_option_group.blank?
    return if profile_option_group.brand_id == brand_id

    errors.add(:profile_option_group, "must belong to the same brand")
  end

  def code_is_immutable
    errors.add(:code, "cannot be changed") if will_save_change_to_code?
  end
end
