require "test_helper"

# "Today's introductions" — Date9ja's curated_daily discovery surface
# (discovery.curated_daily), enabled via Matching::StableDailySelection /
# StableDailyAllocationPolicy, the same proven engine DateZA's Discover uses.
# discovery.find (plain browse) stays Date9ja's default surface for Explore;
# this surface is reached with ?mode=curated_daily.
class Api::V1::Date9jaDiscoveryCuratedDailyControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    Profiles::Date9jaProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "date9ja.test")
    @viewer = create_profile(gender: "woman", interested_in: [ "man" ])
    @token, = Session.issue!(
      brand: @brand, user: @viewer.user, credential: verified_credential(@viewer.user, "viewer@example.test")
    )
    host! "date9ja.test"
  end

  test "creates one finalized batch of at most ten and keeps candidates and order stable" do
    candidates = 11.times.map do |index|
      create_candidate(created_at: Time.utc(2026, 9, 11, 10, 0, index))
    end

    travel_to Time.utc(2026, 9, 11, 12, 0, 0) do
      get "/api/v1/discovery", params: { mode: "curated_daily" }, headers: bearer_headers
      first = JSON.parse(response.body)

      assert_response :success
      assert_equal candidates.last(10).reverse.map(&:public_id), first.fetch("profiles").pluck("id")
      assert_nil first.fetch("next_cursor")
      assert_equal({
        "allocation_date" => "2026-09-11",
        "daily_limit" => 10,
        "count" => 10,
        "finalized" => true,
        "refreshes_at" => "2026-09-12T00:00:00+01:00"
      }, first.fetch("selection"))
      # Missing genotype and sparse answers do not block an introduction and do
      # not fabricate a 0% compatibility score.
      assert first.fetch("profiles").all? { |p| p.fetch("compatibility").fetch("score").nil? }
      assert first.fetch("profiles").all? do |profile|
        profile.dig("compatibility", "critical_checks", "hemoglobin_genotype", "status") == "not_assessed"
      end

      late_candidate = create_candidate(created_at: Time.utc(2026, 9, 11, 12, 30, 0))
      get "/api/v1/discovery", params: { mode: "curated_daily" }, headers: bearer_headers
      repeated = JSON.parse(response.body)

      assert_equal first.fetch("profiles").pluck("id"), repeated.fetch("profiles").pluck("id")
      assert_not_includes repeated.fetch("profiles").pluck("id"), late_candidate.public_id
    end

    allocation = DiscoveryAllocation.where(brand: @brand, brand_membership: @viewer.brand_membership).sole
    assert_equal "discovery.curated_daily", allocation.surface_key
    assert_equal "date9ja_v1", allocation.strategy_key
    assert_equal 10, allocation.allocation_candidates.count
  end

  test "tops up liked/passed candidates instead of shrinking the batch toward zero" do
    initial = 10.times.map { |index| create_candidate(created_at: Time.utc(2026, 9, 11, 9, 0, index)) }

    travel_to Time.utc(2026, 9, 11, 10, 0, 0) do
      get "/api/v1/discovery", params: { mode: "curated_daily" }, headers: bearer_headers
      first_ids = JSON.parse(response.body).fetch("profiles").pluck("id")
      assert_equal 10, first_ids.length

      post "/api/v1/profiles/#{initial.first.public_id}/pass", headers: bearer_headers
      assert_response :success

      backfill = create_candidate(created_at: Time.utc(2026, 9, 11, 9, 30, 0))

      get "/api/v1/discovery", params: { mode: "curated_daily" }, headers: bearer_headers
      second = JSON.parse(response.body)

      # The passed profile drops out of view, but the visible batch is topped
      # back up to 10 rather than left at 9 — this is the "never shrinks
      # toward zero as you decide" guarantee.
      visible_ids = second.fetch("profiles").pluck("id")
      assert_equal 10, visible_ids.length
      assert_not_includes visible_ids, initial.first.public_id
      assert_includes visible_ids, backfill.public_id
    end
  end

  test "a genotype answered after allocation is enforced on the next delivery" do
    candidate = create_candidate(created_at: Time.utc(2026, 9, 11, 9, 0, 0))
    replacement = create_candidate(created_at: Time.utc(2026, 9, 11, 8, 0, 0))

    travel_to Time.utc(2026, 9, 11, 10, 0, 0) do
      get "/api/v1/discovery", params: { mode: "curated_daily" }, headers: bearer_headers
      assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), candidate.public_id

      set_genotype(@viewer, "as")
      set_genotype(candidate, "as")

      get "/api/v1/discovery", params: { mode: "curated_daily" }, headers: bearer_headers
      delivered = JSON.parse(response.body).fetch("profiles")

      assert_not_includes delivered.pluck("id"), candidate.public_id
      assert_includes delivered.pluck("id"), replacement.public_id
    end
  end

  private

  def create_candidate(**attributes)
    create_profile(gender: "man", interested_in: [ "woman" ], **attributes)
  end

  def create_profile(gender:, interested_in:, created_at: nil)
    user = User.create!(status: :active)
    membership = BrandMembership.create!(brand: @brand, user:, status: :active)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: membership, gender:,
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible
    )
    profile.update_columns(created_at:, updated_at: created_at) if created_at
    ProfilePreference.create!(brand: @brand, user:, profile:, interested_in:)
    profile
  end

  def bearer_headers(token = @token)
    { "Authorization" => "Bearer #{token}" }
  end

  def set_genotype(profile, code)
    Profiles::OptionSelections.replace!(profile:, selections: { genotype: [ code ] })
    profile.update!(status: :active, visibility: :visible)
  end

  # A verified email is incidental here: Date9ja discovery itself has no
  # contact-confirmation or RealMe gate.
  def verified_credential(user, email)
    identifier = IdentityIdentifier.create!(
      user:, kind: :email, normalized_value: email, verified_at: Time.current
    )
    Credential.create!(user:, identity_identifier: identifier, kind: :password, status: :active)
  end
end
