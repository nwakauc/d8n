class Api::V1::NotificationsController < ApplicationController
  before_action :authenticate_user!

  def index
    scope = Notifications::Inbox.scope(brand: Current.brand, user: Current.user)
    render json: {
      notifications: Notifications::Inbox.list(brand: Current.brand, user: Current.user).map do |notification|
        Notifications::Presenter.call(notification)
      end,
      unread_count: scope.unread.count
    }
  end

  def read
    notification = scoped_notifications.find_by(public_id: params[:id])
    unless notification
      render json: { error: "notification_not_found" }, status: :not_found
      return
    end

    notification.mark_read!
    render json: { notification: Notifications::Presenter.call(notification) }
  end

  def read_all
    now = Time.current
    updated = scoped_notifications.unread.update_all(read_at: now, updated_at: now)
    render json: { marked_read: updated, unread_count: 0 }
  end

  private

  def scoped_notifications
    Notifications::Inbox.scope(brand: Current.brand, user: Current.user)
  end
end
