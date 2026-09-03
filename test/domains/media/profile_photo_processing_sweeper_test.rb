# frozen_string_literal: true

require "test_helper"
require "vips"

module Media
  class ProfilePhotoProcessingSweeperTest < ActiveJob::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @user = User.create!
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership,
        display_name: "Ada", birthdate: 25.years.ago.to_date, gender: "woman")
    end

    def photo(state:, started_at: nil, terminal: false, position: 0)
      bytes = Vips::Image.black(20, 20).write_to_buffer(".jpg")
      key = "k/#{SecureRandom.uuid}/original.jpg"
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), key:, filename: "original.jpg",
        content_type: "image/jpeg", service_name: ActiveStorage::Blob.service.name)
      p = ProfilePhoto.new(brand: @brand, user: @user, profile: @profile, position:)
      p.image.attach(blob)
      p.save!
      p.update_columns(processing_state: ProfilePhoto.processing_states[state], processing_started_at: started_at,
        metadata: terminal ? { "processing_failure_kind" => "terminal" } : {})
      p
    end

    test "enqueues pending, retryable-failed, and stale processing; skips the rest" do
      pending = photo(state: :pending, position: 0)
      retryable = photo(state: :failed, position: 1)
      stale = photo(state: :processing, started_at: 30.minutes.ago, position: 2)
      _ready = photo(state: :ready, position: 3)
      _terminal = photo(state: :failed, terminal: true, position: 4)
      _recent = photo(state: :processing, started_at: 5.seconds.ago, position: 5)

      result = nil
      assert_enqueued_jobs 3, only: ProcessProfilePhotoJob do
        result = ProfilePhotoProcessingSweeper.call
      end
      assert_equal 3, result.enqueued

      enqueued_ids = enqueued_jobs.select { |j| j["job_class"] == "Media::ProcessProfilePhotoJob" }
        .map { |j| j["arguments"].first }
      assert_equal [ pending.id, retryable.id, stale.id ].sort, enqueued_ids.sort
    end

    test "a soft-deleted photo is never swept" do
      p = photo(state: :pending)
      p.update!(deleted_at: Time.current)
      assert_no_enqueued_jobs { ProfilePhotoProcessingSweeper.call }
    end

    test "processing with a NULL processing_started_at is not treated as stale" do
      p = photo(state: :processing, started_at: nil)
      assert_no_enqueued_jobs { ProfilePhotoProcessingSweeper.call }
      refute ProfilePhoto.processing_sweepable.exists?(id: p.id)
    end

    test "exhausted (terminal) failure is never re-enqueued" do
      p = photo(state: :failed, terminal: true)
      assert_no_enqueued_jobs { ProfilePhotoProcessingSweeper.call }
      refute ProfilePhoto.processing_sweepable.exists?(id: p.id)
    end
  end
end
