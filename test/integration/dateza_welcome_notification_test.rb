require "test_helper"

class DatezaWelcomeNotificationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @dateza = Brand.create!(
      slug: "dateza",
      name: "DateZA",
      auth_methods: %w[ phone_password email_password ]
    )
    BrandDomain.create!(brand: @dateza, host: "dateza.test")
    host! "dateza.test"
  end

  test "successful DateZA registration creates exactly one welcome notification after commit" do
    assert_difference -> { NotificationEvent.count }, 1 do
      assert_difference -> { Notification.count }, 1 do
        perform_enqueued_jobs(only: Notifications::ProcessEventJob) do
          post "/api/v1/auth/password/register", params: registration
        end
      end
    end

    assert_response :created
    membership = BrandMembership.find_by!(brand: @dateza, user: User.order(:id).last)
    notification = Notification.find_by!(brand_membership: membership)

    assert_equal "membership_registered", notification.notification_event.event_type
    assert_equal "dateza.welcome", notification.notification_type
    assert_equal({}, notification.payload)
    assert_equal 1, notification.notification_deliveries.in_app.sent.count
    assert_equal 1, notification.notification_deliveries.email.pending.count
    assert_equal 0, notification.notification_deliveries.push.count
    assert enqueued_jobs.any? { |job| job[:job] == Notifications::DeliverProductNotificationJob }
  end

  test "a failed registration transaction creates no welcome event or notification" do
    failure = Class.new(StandardError)
    failing_issue = ->(**) { raise failure, "forced registration failure" }

    assert_no_difference [ "User.count", "NotificationEvent.count", "Notification.count" ] do
      stub_method(Session, :issue!, failing_issue) do
        assert_raises(failure) do
          Identity::PasswordRegistration.call(
            brand: @dateza,
            identifier: "rollback@example.com",
            password: "secret"
          )
        end
      end
    end
  end

  test "processing and job retries do not duplicate the welcome or its channels" do
    user = User.create!
    membership = BrandMembership.create!(brand: @dateza, user:, status: :active)
    user.identity_identifiers.create!(kind: :email, normalized_value: "retry@example.com", last_seen_at: Time.current)
    event = Notifications::EventPublisher.membership_registered!(membership:)

    2.times { Notifications::ProcessEventJob.perform_now(event.id) }

    notification = Notification.find_by!(notification_event: event)
    assert_equal 1, Notification.where(notification_event: event).count
    assert_equal 1, notification.notification_deliveries.in_app.count
    assert_equal 1, notification.notification_deliveries.email.count
  end

  test "the same identity remains isolated between DateZA and HookUs memberships" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    user = User.create!
    dateza_membership = BrandMembership.create!(brand: @dateza, user:, status: :active)
    BrandMembership.create!(brand: hookus, user:, status: :active)
    event = Notifications::EventPublisher.membership_registered!(membership: dateza_membership)
    Notifications::ProcessEventJob.perform_now(event.id)

    assert_equal 1, Notifications::Inbox.scope(brand: @dateza, user:).count
    assert_equal 0, Notifications::Inbox.scope(brand: hookus, user:).count
    assert_equal @dateza, Notification.last.brand
    assert_equal dateza_membership, Notification.last.brand_membership
  end

  private

  def registration
    { identifier: "welcome@example.com", password: "secret", device_name: "Web" }
  end
end
