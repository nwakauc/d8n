require "test_helper"

module Media
  class VideoPolicyTest < ActiveSupport::TestCase
    test "Date9ja enables profile video with its legacy-compatible limits" do
      brand = Brand.new(slug: "date9ja", name: "Date9ja")

      assert VideoPolicy.enabled?(brand:)
      state = VideoPolicy.initial_state(brand:)
      assert_equal :visible, state.visibility
      assert_equal :pending_review, state.status
      assert_equal 60, VideoPolicy.max_duration_seconds(brand:)
      assert_equal 50.megabytes, VideoPolicy.max_byte_size(brand:)
      assert_not VideoPolicy.moderate_first?(brand:)
    end

    test "a brand without a video configuration has no profile video" do
      %w[hookus dateza some-future-brand].each do |slug|
        brand = Brand.new(slug:, name: slug)

        assert_not VideoPolicy.enabled?(brand:), "#{slug} must not enable profile video"
        assert_raises(VideoPolicy::NotConfigured) { VideoPolicy.initial_state(brand:) }
        assert_raises(VideoPolicy::NotConfigured) { VideoPolicy.max_duration_seconds(brand:) }
      end
    end

    test "publication_eligible? fails closed until a rendition is ready" do
      brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership,
        display_name: "Ada", birthdate: 26.years.ago.to_date, gender: "woman"
      )
      video = ProfileVideo.new(profile:, user:, brand:, status: :pending_review, visibility: :visible)
      video.video.attach(io: StringIO.new("x"), filename: "v.mp4", content_type: "video/mp4")
      video.save!

      assert_not VideoPolicy.publication_eligible?(video:)

      video.playback.attach(io: StringIO.new("y"), filename: "playback.mp4", content_type: "video/mp4")
      video.update!(processing_state: :ready)
      assert VideoPolicy.publication_eligible?(video:)
    end
  end
end
