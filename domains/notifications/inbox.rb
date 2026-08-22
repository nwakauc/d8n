module Notifications
  class Inbox
    LIMIT = 50

    def self.scope(brand:, user:)
      membership = BrandMembership.kept.active.find_by(brand:, user:)
      return Notification.none unless membership

      Notification.kept.where(brand:, user:, brand_membership: membership)
    end

    def self.list(brand:, user:)
      scope(brand:, user:).order(created_at: :desc, id: :desc).limit(LIMIT)
    end
  end
end
