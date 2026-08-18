class ProfilePromptAnswer < ApplicationRecord
  # A member's free-text answer to a brand ProfilePrompt. The answer belongs to a
  # single Profile (the authoritative owner of the member and brand); brand_id is
  # carried only for the tenant-safe composite foreign keys. The replace-set writer
  # Profiles::PromptAnswers enforces MAX_PER_PROFILE and per-brand prompt validity.
  MAX_PER_PROFILE = 5
  MAX_ANSWER_LENGTH = 300

  belongs_to :brand
  belongs_to :profile
  belongs_to :profile_prompt

  scope :kept, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  validates :profile_prompt_id, uniqueness: { scope: :profile_id, conditions: -> { kept } }
  validates :answer, presence: true, length: { maximum: MAX_ANSWER_LENGTH }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :profile_matches_brand
  validate :prompt_matches_brand
  validate :prompt_accepts_new_answer, on: :create
  validate :answer_limit_not_exceeded, on: :create

  private

  def profile_matches_brand
    return if profile.blank?
    return if profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same brand")
  end

  def prompt_matches_brand
    return if profile_prompt.blank?
    return if profile_prompt.brand_id == brand_id

    errors.add(:profile_prompt, "must belong to the same brand")
  end

  def prompt_accepts_new_answer
    return if profile_prompt.blank?
    return if profile_prompt.status_active? && profile_prompt.deleted_at.nil?

    errors.add(:profile_prompt, "must be active")
  end

  def answer_limit_not_exceeded
    return if profile.blank?
    return if self.class.kept.where(profile:).count < MAX_PER_PROFILE

    errors.add(:base, "allows at most #{MAX_PER_PROFILE} prompt answers")
  end
end
