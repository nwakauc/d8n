class ProfileOptionSelection < ApplicationRecord
  belongs_to :profile
  belongs_to :user
  belongs_to :brand
  belongs_to :profile_option_group
  belongs_to :profile_option

  scope :kept, -> { where(deleted_at: nil) }

  validates :profile_option_id,
    uniqueness: { scope: [ :profile_id, :profile_option_group_id ], conditions: -> { kept } }
  validate :profile_matches_scope
  validate :group_matches_scope
  validate :option_matches_scope
  validate :option_accepts_new_selection, on: :create
  validate :selection_limit_not_exceeded, on: :create

  private

  def profile_matches_scope
    return if profile.blank?
    return if profile.user_id == user_id && profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same user and brand")
  end

  def group_matches_scope
    return if profile_option_group.blank?
    return if profile_option_group.brand_id == brand_id

    errors.add(:profile_option_group, "must belong to the same brand")
  end

  def option_matches_scope
    return if profile_option.blank? || profile_option_group.blank?
    return if profile_option.brand_id == brand_id && profile_option.profile_option_group_id == profile_option_group_id

    errors.add(:profile_option, "must belong to the same option group and brand")
  end

  def option_accepts_new_selection
    return if profile_option.blank? || profile_option_group.blank?
    return if profile_option.status_active? && profile_option.deleted_at.nil? &&
      profile_option_group.status_active? && profile_option_group.deleted_at.nil?

    errors.add(:profile_option, "must be active")
  end

  def selection_limit_not_exceeded
    return if profile.blank? || profile_option_group.blank?

    current_count = self.class.kept.where(profile:, profile_option_group:).count
    return if current_count < profile_option_group.max_selections

    errors.add(:profile_option_group, "allows at most #{profile_option_group.max_selections} selections")
  end
end
