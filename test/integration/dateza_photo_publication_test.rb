require "test_helper"

# DateZA and HookUs share the immediate-visibility photo policy: a freshly
# attached photo is publicly deliverable right away and moderated
# asynchronously afterwards (see domains/media/photo_policy.rb and
# domains/d8n/platform/brands/dateza.rb). These tests exercise the full
# lifecycle end to end for DateZA: default visible state, public/Discover-style
# visibility via the shared Profiles::PublicSerializer, moderation transitions
# (approve confirms, reject withdraws), and primary-photo semantics under
# owner reordering. HookUs is included as an explicit regression check that
# its existing immediate-visibility policy is untouched.
class DatezaPhotoPublicationTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "dateza", name: "DateZA",
      profile_requirements: { profile_fields: [], preference_fields: [], collections: %w[ photos ] }
    )
    BrandDomain.create!(brand: @brand, host: "dateza.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand, user: @user, brand_membership: @membership,
      display_name: "Lindiwe", birthdate: 27.years.ago.to_date, gender: "woman"
    )
    @token, = Session.issue!(brand: @brand, user: @user)
    @admin, @admin_token = create_admin(brand: @brand)
  end

  test "a newly attached DateZA photo is visible immediately, pending moderation" do
    photo = attach_photo(@profile)

    assert photo.pending_review?
    assert photo.visible?
    assert photo.deliverable?

    host! "dateza.test"
    get "/api/v1/profile/photos", headers: bearer_headers(@token)
    assert_response :success
    owner_entry = JSON.parse(response.body).fetch("photos").sole
    assert_equal "pending_review", owner_entry.fetch("status")
    assert_equal "visible", owner_entry.fetch("visibility")

    assert_equal [ photo.public_id ], public_photos(@profile).map { |entry| entry.fetch(:id) },
      "a freshly attached photo is publicly deliverable right away"
  end

  test "approval confirms an already-visible photo without disturbing public delivery" do
    photo = attach_photo(@profile)
    assert_equal [ photo.public_id ], public_photos(@profile).map { |entry| entry.fetch(:id) }

    moderate!(photo, "approved")
    assert_equal [ photo.public_id ], public_photos(@profile).map { |entry| entry.fetch(:id) }
  end

  test "rejection withdraws a visible pending photo from public delivery" do
    photo = attach_photo(@profile)
    assert_equal [ photo.public_id ], public_photos(@profile).map { |entry| entry.fetch(:id) }

    moderate!(photo, "rejected")
    assert_empty public_photos(@profile)

    # A moderation decision is terminal — it cannot be reversed by re-deciding.
    assert_raises(Trust::ModerateProfilePhoto::Error) { moderate!(photo, "approved") }
    assert_empty public_photos(@profile)
  end

  test "public serializer never exposes moderation internals" do
    photo = attach_photo(@profile)

    entry = public_photos(@profile).sole
    assert_equal %i[ id position primary url url_expires_in ], entry.keys.sort
  end

  test "owner reordering immediately changes the public primary" do
    first = attach_photo(@profile, position: 0)
    second = attach_photo(@profile, position: 1)

    public_entries = public_photos(@profile)
    assert_equal [ first.public_id, second.public_id ], public_entries.map { |entry| entry.fetch(:id) }
    assert public_entries.first.fetch(:primary)

    Profiles::PhotoOrder.reorder!(user: @user, brand: @brand, ids: [ second.id, first.id ])

    public_entries = public_photos(@profile)
    assert_equal [ second.public_id, first.public_id ], public_entries.map { |entry| entry.fetch(:id) }
    assert public_entries.first.fetch(:primary)
  end

  test "rejecting the primary photo promotes the next visible photo" do
    first = attach_photo(@profile, position: 0)
    second = attach_photo(@profile, position: 1)

    moderate!(first, "rejected")

    public_entries = public_photos(@profile)
    assert_equal [ second.public_id ], public_entries.map { |entry| entry.fetch(:id) }
    assert public_entries.sole.fetch(:primary)
  end

  test "a profile with only rejected photos has no public photos" do
    photo = attach_photo(@profile)
    moderate!(photo, "rejected")
    assert_empty public_photos(@profile)
  end

  test "HookUs keeps its existing immediate-visibility policy unchanged" do
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: hookus, host: "hookus.test")
    hookus_profile = create_profile(brand: hookus)

    photo = attach_photo(hookus_profile)

    assert photo.pending_review?
    assert photo.visible?
    assert photo.deliverable?
    assert_equal [ photo.public_id ], public_photos(hookus_profile).map { |entry| entry.fetch(:id) }
  end

  private

  def public_photos(profile)
    ActiveStorage::Current.url_options = { host: "http://test.local" }
    Profiles::PublicSerializer.call(profile: profile.reload).fetch(:photos)
  ensure
    ActiveStorage::Current.reset
  end

  def moderate!(photo, decision)
    host! "dateza.test" if photo.brand.slug == "dateza"
    Trust::ModerateProfilePhoto.call(admin_user: @admin, brand: photo.brand, photo_id: photo.public_id, decision:)
  end

  def create_profile(brand:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end

  def create_admin(brand:)
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: "moderator")
    AdminAssignment.create!(admin_user:, brand:, admin_role: role, status: :active)
    token = issue_mfa_verified_admin_session!(user:, brand:, admin_user:)
    [ admin_user, token ]
  end

  def attach_photo(profile, position: nil)
    position ||= profile.profile_photos.kept.maximum(:position).to_i + (profile.profile_photos.kept.exists? ? 1 : 0)
    initial = Media::PhotoPolicy.initial_state(brand: profile.brand)
    photo = ProfilePhoto.new(
      brand: profile.brand, user: profile.user, profile:,
      status: initial.status, visibility: initial.visibility, position:
    )
    fixture = Rails.root.join("test/fixtures/files/profile_photo.png")
    photo.image.attach(io: fixture.open, filename: "original.png", content_type: "image/png")
    photo.save!
    photo.display_image.attach(io: fixture.open, filename: "display.jpg", content_type: "image/jpeg")
    photo.update!(processing_state: :ready)
    photo
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
