require "test_helper"

module Media
  class ObjectKeyTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @user = User.create!
      membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(
        brand: @brand,
        user: @user,
        brand_membership: membership,
        display_name: "Ada",
        birthdate: 25.years.ago.to_date,
        gender: "woman"
      )
    end

    test "allocates a brand/user/profile-scoped key with a per-object uuid" do
      key = ObjectKey.profile_photo_original(
        brand: @brand, user: @user, profile: @profile, content_type: "image/png"
      )

      assert_match %r{\Abrands/hookus/users/#{@user.id}/profiles/#{@profile.public_id}/photos/[0-9a-f-]{36}/original\.png\z}, key
    end

    test "maps each supported content type to a stable extension" do
      { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.each do |type, ext|
        key = ObjectKey.profile_photo_original(brand: @brand, user: @user, profile: @profile, content_type: type)
        assert key.end_with?("/original.#{ext}"), "#{type} -> original.#{ext}"
      end
    end

    test "keys are unique across allocations for the same profile" do
      keys = Array.new(5) do
        ObjectKey.profile_photo_original(brand: @brand, user: @user, profile: @profile, content_type: "image/png")
      end

      assert_equal keys.size, keys.uniq.size
    end

    test "keys contain no PII — only brand slug, ids, and uuids" do
      @user.identity_identifiers.create!(kind: :email, normalized_value: "ada@example.com")
      key = ObjectKey.profile_photo_original(
        brand: @brand, user: @user, profile: @profile, content_type: "image/png"
      )

      # Display name and any identifier are never woven into the key.
      assert_not_includes key.downcase, "ada"
      assert_not_includes key, "@"
      # Every non-literal segment is a numeric id or a uuid.
      segments = key.split("/")
      assert_equal %w[brands hookus users], segments[0..2]
      assert_match(/\A\d+\z/, segments[3])
      assert_match(/\A[0-9a-f-]{36}\z/, segments[5])
    end

    test "the profile prefix is shared by every photo of one profile" do
      prefix = "brands/hookus/users/#{@user.id}/profiles/#{@profile.public_id}"
      key = ObjectKey.profile_photo_original(
        brand: @brand, user: @user, profile: @profile, content_type: "image/png"
      )

      assert key.start_with?("#{prefix}/photos/")
    end
  end
end
