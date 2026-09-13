class CommunityEventRsvp < ApplicationRecord
  belongs_to :community_event
  belongs_to :brand
  belongs_to :profile
  enum :status, { attending: 0, cancelled: 1 }, prefix: true
  scope :kept, -> { where(deleted_at: nil) }
  validate :tenant_ownership

  private

  def tenant_ownership
    errors.add(:profile, "must belong to the RSVP brand") if profile && profile.brand_id != brand_id
    errors.add(:community_event, "must belong to the RSVP brand") if community_event && community_event.brand_id != brand_id
  end
end
