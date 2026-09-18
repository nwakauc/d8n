require "test_helper"

class Api::V1::NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dateza = Brand.create!(slug: "dateza", name: "DateZA")
    @hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @dateza, host: "dateza.test")
    BrandDomain.create!(brand: @hookus, host: "hookus.test")
    @user = User.create!
    @dateza_membership = BrandMembership.create!(brand: @dateza, user: @user, status: :active)
    @hookus_membership = BrandMembership.create!(brand: @hookus, user: @user, status: :active)
    event = Notifications::EventPublisher.membership_registered!(membership: @dateza_membership)
    Notifications::ProcessEventJob.perform_now(event.id)
    @notification = event.notification
    @dateza_token, = Session.issue!(user: @user, brand: @dateza)
    @hookus_token, = Session.issue!(user: @user, brand: @hookus)
  end

  test "lists only current-brand notifications and exposes no provider details" do
    host! "dateza.test"
    get "/api/v1/notifications", headers: bearer(@dateza_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.fetch("unread_count")
    assert_equal({ "dateza.welcome" => 1 }, body.fetch("unread_counts"))
    assert_equal [ @notification.public_id ], body.fetch("notifications").pluck("id")
    assert_equal "dateza.welcome", body.dig("notifications", 0, "type")
    assert_not_includes response.body, "recipient"
    assert_not_includes response.body, "provider"
    assert_not_includes response.body, "external_id"

    host! "hookus.test"
    get "/api/v1/notifications", headers: bearer(@hookus_token)
    assert_response :success
    assert_equal [], JSON.parse(response.body).fetch("notifications")
    assert_equal({}, JSON.parse(response.body).fetch("unread_counts"))
  end

  test "category counts cover the full inbox beyond its fifty record page" do
    50.times do
      event = @notification.notification_event.dup
      event.idempotency_key = SecureRandom.uuid
      event.save!
      notification = @notification.dup
      notification.public_id = SecureRandom.uuid
      notification.notification_event = event
      notification.save!
    end

    host! "dateza.test"
    get "/api/v1/notifications", headers: bearer(@dateza_token)
    body = JSON.parse(response.body)
    assert_equal 50, body.fetch("notifications").length
    assert_equal 51, body.fetch("unread_count")
    assert_equal({ "dateza.welcome" => 51 }, body.fetch("unread_counts"))

    patch "/api/v1/notifications/#{@notification.public_id}/read", headers: bearer(@dateza_token)
    assert_equal({ "dateza.welcome" => 50 }, JSON.parse(response.body).fetch("unread_counts"))
  end

  test "requires a brand-bound session" do
    host! "dateza.test"
    get "/api/v1/notifications"

    assert_response :unauthorized
  end

  test "marks one notification and all notifications read" do
    host! "dateza.test"
    patch "/api/v1/notifications/#{@notification.public_id}/read", headers: bearer(@dateza_token)
    assert_response :success
    assert @notification.reload.read_at
    assert_equal({}, JSON.parse(response.body).fetch("unread_counts"))

    @notification.update!(read_at: nil)
    post "/api/v1/notifications/read_all", headers: bearer(@dateza_token)
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("marked_read")
    assert @notification.reload.read_at
    assert_equal({}, JSON.parse(response.body).fetch("unread_counts"))
  end

  test "cross-brand notification ids fail neutrally" do
    host! "hookus.test"
    patch "/api/v1/notifications/#{@notification.public_id}/read", headers: bearer(@hookus_token)

    assert_response :not_found
    assert_equal({ "error" => "notification_not_found" }, JSON.parse(response.body))
    assert_nil @notification.reload.read_at
  end

  private

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
