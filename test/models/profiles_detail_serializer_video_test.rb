require "test_helper"

module Profiles
  # Wiring of the shared profile-video capability (ADR 0023) into the public
  # profile detail view. Delivery eligibility is re-checked at read time
  # (ADR 0011): a video that is deleted, unprocessed, failed, hidden, or no
  # longer publication-eligible must never reach another member, and brands
  # without the capability must see no `video` key at all.
  class DetailSerializerVideoTest < ActiveSupport::TestCase
    setup do
      ActiveStorage::Current.url_options = { host: "http://test.local" }
      @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      Profiles::Date9jaProfileCatalog.install!(brand: @brand)
      @viewer = build_profile
      @target = build_profile
    end

    teardown { ActiveStorage::Current.reset }

    test "a deliverable video is exposed as a safe signed payload, no raw key" do
      video = ready_video(@target)

      payload = DetailSerializer.call(profile: @target.reload, viewer: @viewer)

      assert payload.key?(:video)
      assert_equal video.public_id, payload[:video].fetch(:id)
      assert_equal 4, payload[:video].fetch(:duration_seconds)
      assert_match %r{\Ahttp://test\.local/}, payload[:video].fetch(:playback_url)
      assert payload[:video].fetch(:poster_url).present?
      refute_includes payload[:video].to_s, video.playback.blob.key
      refute_includes payload[:video].to_s, video.video.blob&.key.to_s if video.video.attached?
    end

    test "no video -> video key present but null" do
      payload = DetailSerializer.call(profile: @target.reload, viewer: @viewer)

      assert payload.key?(:video)
      assert_nil payload[:video]
    end

    test "an unprocessed video is not exposed" do
      video = ready_video(@target)
      video.update!(processing_state: :pending)
      video.playback.purge

      assert_nil DetailSerializer.call(profile: @target.reload, viewer: @viewer)[:video]
    end

    test "a failed video is not exposed" do
      ready_video(@target).update!(processing_state: :failed)

      assert_nil DetailSerializer.call(profile: @target.reload, viewer: @viewer)[:video]
    end

    test "a hidden video is not exposed" do
      ready_video(@target).update!(visibility: :hidden)

      assert_nil DetailSerializer.call(profile: @target.reload, viewer: @viewer)[:video]
    end

    test "a rejected video is not exposed" do
      ready_video(@target).update!(status: :rejected)

      assert_nil DetailSerializer.call(profile: @target.reload, viewer: @viewer)[:video]
    end

    test "a soft-deleted video is not exposed" do
      ready_video(@target).update!(deleted_at: Time.current)

      assert_nil DetailSerializer.call(profile: @target.reload, viewer: @viewer)[:video]
    end

    test "a video on another profile never bleeds through" do
      other = build_profile
      ready_video(other)

      assert_nil DetailSerializer.call(profile: @target.reload, viewer: @viewer)[:video]
    end

    test "a video with a mismatched brand is never delivered" do
      video = ready_video(@target)
      other_brand = Brand.create!(slug: "dateza", name: "DateZA")
      video.update_column(:brand_id, other_brand.id)

      assert_nil DetailSerializer.call(profile: @target.reload, viewer: @viewer)[:video]
    end

    test "a brand without the profile-video capability has no video key" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand:)
      viewer = build_profile_for(brand:)
      target = build_profile_for(brand:)

      payload = DetailSerializer.call(profile: target, viewer:)
      assert_not payload.key?(:video)
    end

    private

    def build_profile(**attrs)
      build_profile_for(brand: @brand, **attrs)
    end

    def build_profile_for(brand:, **attrs)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      Profile.create!(
        brand:, user:, brand_membership: membership,
        display_name: "M#{user.id}", birthdate: 27.years.ago.to_date,
        status: :active, visibility: :visible, **attrs
      )
    end

    # A processed, deliverable video: safe derivatives attached, ready, visible.
    def ready_video(profile)
      video = ProfileVideo.new(
        profile:, user: profile.user, brand: profile.brand,
        status: :pending_review, visibility: :visible,
        processing_state: :ready, duration_seconds: 4, processed_at: Time.current
      )
      video.video.attach(io: StringIO.new("raw".b), filename: "v.mp4", content_type: "video/mp4")
      video.playback.attach(io: StringIO.new("play".b), filename: "playback.mp4", content_type: "video/mp4")
      video.poster.attach(io: StringIO.new("post".b), filename: "poster.jpg", content_type: "image/jpeg")
      video.save!
      video
    end
  end
end
