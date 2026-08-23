require "test_helper"
require "vips"

module Profiles
  class DatezaDemoSeedTest < ActiveSupport::TestCase
    def setup
      @root = Pathname.new(Dir.mktmpdir("dateza-demo-seed"))
      ActiveStorage::Current.url_options = { host: "http://test.local" }
    end

    def teardown
      ActiveStorage::Current.reset
      FileUtils.remove_entry(@root) if @root&.directory?
    end

    test "seeds DateZA profiles from image names and ages using the real completion gate" do
      write_person("ladies/Thandeka-36", %w[ 1.jpeg 2.jpeg ])
      write_person("guys/Tawanda--28", %w[ 1.jpeg ])

      summary = seed!

      assert_equal 2, summary.created
      assert_equal 0, summary.skipped
      assert_equal 3, summary.photos_attached

      thandeka = seeded_profile("Thandeka")
      assert_equal "dateza", thandeka.brand.slug
      assert_equal "Thandeka", thandeka.user.first_name
      assert_equal DatezaDemoSeed::SYNTHETIC_LAST_NAME, thandeka.user.last_name
      assert_equal 36, displayed_age(thandeka)
      assert thandeka.active?
      assert thandeka.visible?
      assert Completion.call(profile: thandeka).complete?
      assert thandeka.profile_photos.kept.all?(&:deliverable?)

      public_payload = PublicSerializer.call(profile: thandeka)
      assert_equal "Thandeka", public_payload.fetch(:display_name)
      assert_equal 36, public_payload.fetch(:age)
      refute_includes public_payload.keys, :first_name
      refute_includes public_payload.keys, :last_name
    end

    test "uses only DateZA option and prompt capabilities" do
      write_person("ladies/Maya-27", %w[ 1.jpeg ])
      seed!
      profile = seeded_profile("Maya")

      selected_groups = profile.profile_option_selections.kept
        .joins(:profile_option_group).pluck("profile_option_groups.key").uniq
      assert_empty selected_groups & %w[ intents vibes cannabis ]
      DatezaProfileCatalog::REQUIRED_OPTION_GROUPS.each do |key|
        assert_includes selected_groups, key
      end
      assert_includes selected_groups, "interests"

      prompt_keys = profile.prompt_answers.kept.joins(:profile_prompt).pluck("profile_prompts.key")
      assert_empty prompt_keys - DatezaProfileCatalog::ENABLED_PROMPTS
    end

    test "DateZA and HookUs demo runs remain separate and idempotent" do
      write_person("ladies/Maya-27", %w[ 1.jpeg ])
      first = seed!
      second = seed!

      assert_equal 1, first.created
      assert_equal 0, second.created
      assert_equal 1, second.updated
      assert_equal 0, second.photos_attached
      assert_equal 1, Profile.where("metadata->>'seed' = ?", "dateza_demo").count

      DemoSeed.call(root: @root, dry_run: false, io: StringIO.new)
      dateza_profile = seeded_profile("Maya")
      hookus_profile = Profile.where("metadata->>'seed' = ?", "hookus_demo").find_by!(display_name: "Maya")

      assert_not_equal dateza_profile.user_id, hookus_profile.user_id
      assert_not_equal dateza_profile.brand_id, hookus_profile.brand_id
      assert_equal "seed+lady-maya-27@dateza.test",
        dateza_profile.user.identity_identifiers.kept.find_by!(kind: :email).normalized_value
      assert_equal "seed+lady-maya-27@hookus.test",
        hookus_profile.user.identity_identifiers.kept.find_by!(kind: :email).normalized_value
    end

    test "dry run reports DateZA changes without writing" do
      Brands::DatezaInstaller.call
      write_person("ladies/Maya-27", %w[ 1.jpeg ])

      assert_no_difference [ "User.count", "Profile.count", "ProfilePhoto.count", "Brand.count" ] do
        summary = DatezaDemoSeed.call(root: @root, dry_run: true, io: StringIO.new)
        assert summary.dry_run
        assert_equal 1, summary.created
        assert_equal 1, summary.photos_attached
      end
    end

    test "seeding performs no email or SMS delivery" do
      write_person("ladies/Maya-27", %w[ 1.jpeg ])

      assert_no_difference [ "OtpChallenge.count", "NotificationDelivery.count" ] do
        seed!
      end
    end

    private

    def seed!
      DatezaDemoSeed.call(root: @root, dry_run: false, io: StringIO.new)
    end

    def seeded_profile(display_name)
      Profile.kept.where("metadata->>'seed' = ?", "dateza_demo").find_by!(display_name:)
    end

    def displayed_age(profile)
      today = Date.current
      birthday_passed = (today.month * 100 + today.day) >= (profile.birthdate.month * 100 + profile.birthdate.day)
      today.year - profile.birthdate.year - (birthday_passed ? 0 : 1)
    end

    def write_person(relative, filenames)
      directory = @root.join(relative)
      FileUtils.mkdir_p(directory)
      filenames.each_with_index do |filename, index|
        bytes = Vips::Image.black(48, 48).add([ 40 + index * 30 ]).cast("uchar").write_to_buffer(".jpg")
        File.binwrite(directory.join(filename), bytes)
      end
    end
  end
end
