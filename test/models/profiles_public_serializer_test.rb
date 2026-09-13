require "test_helper"

module Profiles
  class PublicSerializerTest < ActiveSupport::TestCase
    test "exposes derived age and public options without private source fields" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand:)
      private_group = ProfileOptionGroup.create!(
        brand:, key: "private_note", label: "Private", visibility: :owner_only
      )
      private_option = ProfileOption.create!(
        brand:, profile_option_group: private_group, code: "hidden", label: "Hidden"
      )
      user = User.create!(first_name: "Ada", last_name: "Lovelace")
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, display_name: "Ada", birthdate: 25.years.ago.to_date
      )
      OptionSelections.replace!(profile:, selections: { intents: [ "hookups" ], private_note: [ "hidden" ] })

      payload = PublicSerializer.call(profile:)

      assert_equal profile.public_id, payload.fetch(:id)
      assert_equal 25, payload.fetch(:age)
      assert_equal [ "hookups" ], payload.fetch(:options).fetch("intents")
      assert_not payload.fetch(:options).key?("private_note")
      assert_not payload.key?(:birthdate)
      assert_not payload.key?(:first_name)
      assert_not payload.key?(:last_name)
      assert_not payload.key?(:user_id)
      assert_not payload.key?(:latitude)
      assert_not payload.key?(:longitude)
    end

    test "Date9ja cards advertise only a deliverable intro-video signal" do
      brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      Date9jaProfileCatalog.install!(brand:)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, display_name: "Ada", birthdate: 25.years.ago.to_date
      )
      video = ProfileVideo.new(
        profile:, user:, brand:, status: :approved, visibility: :visible,
        processing_state: :ready, duration_seconds: 22, processed_at: Time.current
      )
      video.video.attach(io: StringIO.new("raw"), filename: "intro.mp4", content_type: "video/mp4")
      video.playback.attach(io: StringIO.new("play"), filename: "playback.mp4", content_type: "video/mp4")
      video.poster.attach(io: StringIO.new("poster"), filename: "poster.jpg", content_type: "image/jpeg")
      video.save!

      payload = PublicSerializer.call(profile: profile.reload)

      assert_equal true, payload.fetch(:has_video_intro)
      assert_equal 22, payload.fetch(:video_intro_duration_seconds)
      assert_not payload.key?(:playback_url)
      assert_not payload.key?(:poster_url)
    end

    test "Date9ja cards fail closed for an incomplete intro video" do
      brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      Date9jaProfileCatalog.install!(brand:)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, display_name: "Ada", birthdate: 25.years.ago.to_date
      )
      video = ProfileVideo.new(
        profile:, user:, brand:, status: :approved, visibility: :visible,
        processing_state: :pending, duration_seconds: 22
      )
      video.video.attach(io: StringIO.new("raw"), filename: "intro.mp4", content_type: "video/mp4")
      video.save!

      payload = PublicSerializer.call(profile: profile.reload)

      assert_equal false, payload.fetch(:has_video_intro)
      assert_nil payload.fetch(:video_intro_duration_seconds)
    end
  end
end
