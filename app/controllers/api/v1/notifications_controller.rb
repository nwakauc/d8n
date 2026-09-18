class Api::V1::NotificationsController < ApplicationController
  before_action :authenticate_user!

  def index
    render json: {
      notifications: Notifications::Inbox.list(brand: Current.brand, user: Current.user).map do |notification|
        Notifications::Presenter.call(notification)
      end,
      **unread_state
    }
  end

  def read
    notification = scoped_notifications.find_by(public_id: params[:id])
    unless notification
      render json: { error: "notification_not_found" }, status: :not_found
      return
    end

    notification.mark_read!
    render json: { notification: Notifications::Presenter.call(notification), **unread_state }
  end

  def read_all
    now = Time.current
    updated = scoped_notifications.unread.update_all(read_at: now, updated_at: now)
    Realtime::MemberEvents.publish(brand_id: Current.brand.id, user_id: Current.user.id, type: "read_state_changed")
    render json: { marked_read: updated, **unread_state }
  end

  private

  def unread_state
    counts = scoped_notifications.unread.group(:notification_type).count
    { unread_count: counts.values.sum, unread_counts: counts }
  end

  def scoped_notifications
    Notifications::Inbox.scope(brand: Current.brand, user: Current.user)
  end
end
