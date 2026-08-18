class HookTonightState < ApplicationRecord
  belongs_to :brand
  belongs_to :profile

  # The only state that counts as "available tonight": not manually deactivated
  # AND not past its expiry. Expiry is evaluated against the clock here rather than
  # trusting any status flag, so a stale row can never make someone discoverable
  # and no background sweep is required for correctness (mirrors Hook#live).
  scope :live, -> { where(deactivated_at: nil).where(expires_at: Time.current..) }

  validates :intent, presence: true, inclusion: { in: ->(_) { HookTonight::Policy::INTENTS } }
  validates :activated_at, presence: true
  validates :expires_at, presence: true
  validate :profile_matches_brand

  def live?
    deactivated_at.nil? && expires_at.present? && expires_at > Time.current
  end

  private

  def profile_matches_brand
    return if profile.blank?
    return if profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same brand")
  end
end
