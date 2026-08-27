require "test_helper"

class Api::V1::NotificationPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dateza = Brand.create!(slug: "dateza", name: "DateZA")
    @hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @dateza, host: "dateza.test")
    BrandDomain.create!(brand: @hookus, host: "hookus.test")
    @user = User.create!
    @dateza_membership = BrandMembership.create!(brand: @dateza, user: @user, status: :active)
    @hookus_membership = BrandMembership.create!(brand: @hookus, user: @user, status: :active)
    @dateza_token, = Session.issue!(brand: @dateza, user: @user)
    @hookus_token, = Session.issue!(brand: @hookus, user: @user)
  end

  # -- GET --------------------------------------------------------------------

  test "GET requires authentication" do
    host! "dateza.test"
    get "/api/v1/notifications/preferences"

    assert_response :unauthorized
  end

  test "GET returns effective defaults when no row exists, without creating one" do
    host! "dateza.test"

    assert_no_difference -> { NotificationPreference.count } do
      get "/api/v1/notifications/preferences", headers: auth(@dateza_token)
    end

    assert_response :success
    assert_equal({ "preferences" => { "product_email_enabled" => true, "push_enabled" => true } },
      JSON.parse(response.body))
  end

  test "GET response has exactly the expected keys and no internal identifiers" do
    host! "dateza.test"
    get "/api/v1/notifications/preferences", headers: auth(@dateza_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal %w[preferences], body.keys
    assert_equal %w[product_email_enabled push_enabled], body.fetch("preferences").keys.sort
  end

  test "GET reflects persisted values after an update" do
    host! "dateza.test"
    patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: { product_email_enabled: false }, as: :json

    get "/api/v1/notifications/preferences", headers: auth(@dateza_token)

    assert_response :success
    preferences = JSON.parse(response.body).fetch("preferences")
    assert_equal false, preferences.fetch("product_email_enabled")
    assert_equal true, preferences.fetch("push_enabled")
  end

  test "a suspended brand membership cannot authenticate at all, so preferences are unreachable" do
    host! "dateza.test"
    @dateza_membership.update!(status: :suspended)

    get "/api/v1/notifications/preferences", headers: auth(@dateza_token)

    # authenticate_user! itself rejects a suspended membership's session — this
    # is existing auth-layer behaviour, not T5-specific logic. Because of that,
    # Notifications::Preferences' own defensive non-active-membership handling
    # (mirroring Notifications::Inbox.scope) can never actually be exercised
    # through this HTTP endpoint; it is still correct to keep for symmetry with
    # the rest of the notify.* domain and for any future non-HTTP caller.
    assert_response :unauthorized
  end

  # -- PATCH ------------------------------------------------------------------

  test "PATCH requires authentication" do
    host! "dateza.test"
    patch "/api/v1/notifications/preferences", params: { product_email_enabled: false }

    assert_response :unauthorized
  end

  test "a partial update changes only the given field and creates exactly one row" do
    host! "dateza.test"

    assert_difference -> { NotificationPreference.count }, 1 do
      patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: { push_enabled: false }, as: :json
    end

    assert_response :success
    body = JSON.parse(response.body).fetch("preferences")
    assert_equal true, body.fetch("product_email_enabled")
    assert_equal false, body.fetch("push_enabled")

    preference = NotificationPreference.kept.find_by!(brand_membership: @dateza_membership)
    assert_equal @dateza, preference.brand
    assert_equal @user, preference.user
  end

  test "a second partial update preserves the field set by an earlier update" do
    host! "dateza.test"
    patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: { product_email_enabled: false }, as: :json

    assert_no_difference -> { NotificationPreference.count } do
      patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: { push_enabled: false }, as: :json
    end

    body = JSON.parse(response.body).fetch("preferences")
    assert_equal false, body.fetch("product_email_enabled")
    assert_equal false, body.fetch("push_enabled")
  end

  test "repeating an identical PATCH is safe and idempotent" do
    host! "dateza.test"
    patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: { product_email_enabled: false }, as: :json

    assert_no_difference -> { NotificationPreference.count } do
      patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: { product_email_enabled: false }, as: :json
    end

    assert_response :success
    assert_equal false, JSON.parse(response.body).dig("preferences", "product_email_enabled")
  end

  test "unknown preference keys are rejected, not silently persisted" do
    host! "dateza.test"

    assert_no_difference -> { NotificationPreference.count } do
      patch "/api/v1/notifications/preferences", headers: auth(@dateza_token),
        params: { whatsapp_enabled: true, whatsapp_number: "+27821234567" }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_preferences", JSON.parse(response.body).fetch("error")
  end

  test "a non-boolean value is rejected rather than coerced" do
    host! "dateza.test"

    assert_no_difference -> { NotificationPreference.count } do
      patch "/api/v1/notifications/preferences", headers: auth(@dateza_token),
        params: { product_email_enabled: "true" }, as: :json
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "invalid_preferences", body.fetch("error")
    assert body.dig("details", "product_email_enabled").present?
  end

  test "an empty PATCH body is not treated as unknown keys and leaves preferences unchanged" do
    host! "dateza.test"
    patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: { product_email_enabled: false }, as: :json

    patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: {}, as: :json

    assert_response :success
    assert_equal false, JSON.parse(response.body).dig("preferences", "product_email_enabled")
  end

  # -- multi-brand scope --------------------------------------------------------

  test "the same D8N identity has independent preferences per brand membership" do
    host! "dateza.test"
    patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: { product_email_enabled: false }, as: :json

    host! "hookus.test"
    get "/api/v1/notifications/preferences", headers: auth(@hookus_token)

    assert_response :success
    assert_equal({ "product_email_enabled" => true, "push_enabled" => true },
      JSON.parse(response.body).fetch("preferences"))
    assert_equal 1, NotificationPreference.count
  end

  test "updating HookUs preferences never touches the DateZA row for the same identity" do
    host! "dateza.test"
    patch "/api/v1/notifications/preferences", headers: auth(@dateza_token), params: { product_email_enabled: false }, as: :json

    host! "hookus.test"
    patch "/api/v1/notifications/preferences", headers: auth(@hookus_token), params: { push_enabled: false }, as: :json

    dateza_preference = NotificationPreference.kept.find_by!(brand_membership: @dateza_membership)
    hookus_preference = NotificationPreference.kept.find_by!(brand_membership: @hookus_membership)
    assert_equal false, dateza_preference.product_email_enabled
    assert_equal true, dateza_preference.push_enabled
    assert_equal true, hookus_preference.product_email_enabled
    assert_equal false, hookus_preference.push_enabled
  end

  private

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
