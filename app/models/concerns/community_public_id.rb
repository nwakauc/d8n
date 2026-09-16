module CommunityPublicId
  extend ActiveSupport::Concern

  included do
    before_validation :ensure_community_public_id, on: :create
  end

  private

  def ensure_community_public_id
    self.public_id ||= SecureRandom.uuid
  end
end
