require "test_helper"
require "vips"

module Profiles
  # End-to-end coverage for the HookUs demo seeder. Exercises folder discovery,
  # name/age parsing, idempotency, the real media pipeline, and — via the REAL
  # discovery service — the reciprocal-discoverability requirement, all against a
  # small on-disk fixture tree built per test.
  class DemoSeedTest < ActiveSupport::TestCase
    def setup
      @root = Pathname.new(Dir.mktmpdir("demo-seed"))
    end

    def teardown
      FileUtils.remove_entry(@root) if @root&.directory?
    end

    # --- Folder discovery + parsing -----------------------------------------

    test "discovers directory people, loose-file people, and orders photos" do
      write_dir("ladies/Thandeka-36", %w[ 2.jpeg 1.jpeg extra.jpeg ])
      write_file("ladies/thando-26.jpeg")
      write_file("guys/Aarav-27.jpeg")
      write_dir("guys/Tawanda--28", %w[ 1.jpeg 2.jpeg ])

      people = DemoSeed::Catalog.call(root: @root).index_by(&:display_name)

      assert_equal %w[ Aarav Tawanda Thandeka thando ].sort, people.keys.sort
      thandeka = people.fetch("Thandeka")
      assert_equal 36, thandeka.age
      assert_equal "woman", thandeka.gender
      # Numbered files lead in numeric order; non-numbered follow.
      assert_equal %w[ 1.jpeg 2.jpeg extra.jpeg ], thandeka.image_paths.map { |p| File.basename(p) }
      assert_equal 28, people.fetch("Tawanda").age, "double-hyphen separator parses"
      assert_equal "man", people.fetch("Aarav").gender
      assert_equal 1, people.fetch("thando").image_paths.size
    end

    test "caps photos per person at the model max" do
      write_dir("ladies/Amara-28", (1..20).map { |n| "#{n}.jpeg" })
      person = DemoSeed::Catalog.call(root: @root).first
      assert_equal DemoSeed::Catalog::MAX_PHOTOS, person.image_paths.size
    end

    test "raises clearly on unparseable folder names" do
      write_dir("ladies/NoAgeHere", %w[ 1.jpeg ])
      assert_raises(DemoSeed::Catalog::Error) { DemoSeed::Catalog.call(root: @root) }
    end

    test "raises on ages below the minimum" do
      write_dir("ladies/Kiddo-15", %w[ 1.jpeg ])
      error = assert_raises(DemoSeed::Catalog::Error) { DemoSeed::Catalog.call(root: @root) }
      assert_match(/minimum/, error.message)
    end

    test "raises when a person directory has no usable images" do
      write_dir("ladies/Empty-30", %w[ notes.txt ])
      assert_raises(DemoSeed::Catalog::Error) { DemoSeed::Catalog.call(root: @root) }
    end

    test "raises when no people are found at all" do
      assert_raises(DemoSeed::Catalog::Error) { DemoSeed::Catalog.call(root: @root) }
    end

    # --- Seeding: profiles, photos, taxonomy --------------------------------

    test "seeds valid, active, discoverable profiles with deliverable photos" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg 2.jpeg ])
      write_file("guys/Jason-34.jpeg")

      summary = seed!
      assert_equal 0, summary.skipped
      assert_equal 2, summary.created
      assert_equal 1, summary.ladies
      assert_equal 1, summary.guys
      assert_equal 3, summary.photos_attached

      maya = seeded_profile("Maya")
      assert maya.active?
      assert maya.visible?
      assert maya.valid?
      assert_equal "hookus_demo", maya.metadata["seed"]
      assert_equal 27, displayed_age(maya), "displayed age matches the folder age"

      photos = maya.profile_photos.kept.ordered
      assert_equal 2, photos.size
      assert photos.all?(&:deliverable?), "seeded photos are deliverable via the real pipeline"
      # Folder order is preserved and the first folder image sorts first (primary).
      assert_equal %w[ 1.jpeg 2.jpeg ], photos.map { |photo| photo.metadata["seed_basename"] }
      assert_operator photos.first.position, :<, photos.second.position
    end

    test "every generated option and prompt code exists in the brand catalog" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg ])
      write_file("guys/Jason-34.jpeg")
      seed!

      brand = Brand.kept.find_by!(slug: "hookus")
      valid_codes = ProfileOption.kept.where(brand:).pluck(:code).to_set
      valid_prompts = brand.profile_prompts.kept.pluck(:key).to_set

      Profile.where(brand:).where("metadata->>'seed' = ?", "hookus_demo").find_each do |profile|
        profile.profile_option_selections.kept.includes(:profile_option).each do |selection|
          assert_includes valid_codes, selection.profile_option.code
        end
        profile.prompt_answers.kept.includes(:profile_prompt).each do |answer|
          assert_includes valid_prompts, answer.profile_prompt.key
          assert answer.answer.present?
        end
      end
    end

    # --- Idempotency ---------------------------------------------------------

    test "rerunning creates no duplicate users, profiles, photos, or selections" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg 2.jpeg ])
      seed!

      counts = -> {
        [ User.count, Profile.count, ProfilePhoto.count,
          ProfileOptionSelection.count, ProfilePromptAnswer.count, IdentityIdentifier.count ]
      }
      before = counts.call
      second = seed!

      assert_equal before, counts.call, "a rerun must not create duplicate rows"
      assert_equal 0, second.created
      assert_equal 1, second.updated
      assert_equal 0, second.photos_attached
    end

    test "a rerun attaches only newly added images" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg ])
      seed!
      assert_equal 1, seeded_profile("Maya").profile_photos.kept.count

      write_file("ladies/Maya-27/2.jpeg")
      summary = seed!
      assert_equal 1, summary.photos_attached
      assert_equal 2, seeded_profile("Maya").profile_photos.kept.count
    end

    # --- Discovery compatibility (real service, no code changes) -------------

    test "seeded lady is discoverable by compatible male AND female viewers" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg ])
      write_file("guys/Jason-34.jpeg")
      seed!
      lady = seeded_profile("Maya")

      assert_discoverable lady, by: viewer(gender: "man", interested_in: [ "woman" ])
      assert_discoverable lady, by: viewer(gender: "woman", interested_in: [ "woman" ])
    end

    test "seeded guy is discoverable by compatible female AND male viewers" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg ])
      write_file("guys/Jason-34.jpeg")
      seed!
      guy = seeded_profile("Jason")

      assert_discoverable guy, by: viewer(gender: "woman", interested_in: [ "man" ])
      assert_discoverable guy, by: viewer(gender: "man", interested_in: [ "man" ])
    end

    test "seeds still obey normal reciprocal rules (no discovery bypass)" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg ])
      write_file("guys/Jason-34.jpeg")
      seed!

      # A straight woman is interested in men, so she must NOT see the seeded lady:
      # discoverability comes only from valid preference data, not a special case.
      straight_woman = viewer(gender: "woman", interested_in: [ "man" ])
      refute_discoverable seeded_profile("Maya"), by: straight_woman
      assert_discoverable seeded_profile("Jason"), by: straight_woman
    end

    # --- No external delivery + env guard -----------------------------------

    test "seeding triggers no email/SMS delivery" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg ])
      write_file("guys/Jason-34.jpeg")

      assert_no_difference [ "OtpChallenge.count", "NotificationDelivery.count" ] do
        seed!
      end
      # Identifiers are created directly (never via the verification flow).
      assert IdentityIdentifier.kept.exists?(normalized_value: "seed+lady-maya-27@hookus.test")
    end

    test "guard refuses production unless the deliberate override is set" do
      assert_raises(DemoSeed::EnvNotAllowed) { DemoSeed.guard!(env: "production") }
      assert_nil DemoSeed.guard!(env: "development")
      # The D8N staging host runs as RAILS_ENV=production, so the explicit opt-in
      # is what makes a deliberate staging/production seed possible.
      assert_nil DemoSeed.guard!(env: "production", allow_production: true)
    end

    test "dry run reports intentions without writing anything" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg ])
      seed! # establishes the brand, catalogue, and Maya
      write_file("guys/Jason-34.jpeg") # a not-yet-seeded person

      assert_no_difference [ "User.count", "Profile.count", "ProfilePhoto.count",
                             "ProfileOptionGroup.count", "Brand.count" ] do
        summary = DemoSeed.call(root: @root, dry_run: true, io: StringIO.new)
        assert summary.dry_run
        assert_equal 1, summary.created, "Jason would be created"
        assert_equal 1, summary.updated, "Maya already exists"
        assert_equal 1, summary.photos_attached, "only Jason's image would attach"
      end
    end

    test "dry run against an unconfigured brand fails read-only rather than creating it" do
      write_dir("ladies/Maya-27", %w[ 1.jpeg ])
      assert_no_difference "Brand.count" do
        assert_raises(DemoSeed::Catalog::Error) do
          DemoSeed.call(root: @root, dry_run: true, io: StringIO.new)
        end
      end
    end

    private

    def seed!
      DemoSeed.call(root: @root, dry_run: false, io: StringIO.new)
    end

    def seeded_profile(display_name)
      Profile.kept.where("metadata->>'seed' = ?", "hookus_demo").find_by!(display_name:)
    end

    def displayed_age(profile)
      today = Date.current
      passed = (today.month * 100 + today.day) >= (profile.birthdate.month * 100 + profile.birthdate.day)
      today.year - profile.birthdate.year - (passed ? 0 : 1)
    end

    def assert_discoverable(candidate, by:)
      assert_includes discovered_ids(by), candidate.id,
        "#{candidate.display_name} should be discoverable by the viewer"
    end

    def refute_discoverable(candidate, by:)
      refute_includes discovered_ids(by), candidate.id,
        "#{candidate.display_name} should NOT be discoverable by the viewer"
    end

    def discovered_ids(viewer)
      Matching::Discovery.call(user: viewer.user, brand: viewer.brand, limit: "50").profiles.map(&:id)
    end

    # A throwaway (non-seed) viewer profile, wide-open on age with no distance cap.
    def viewer(gender:, interested_in:)
      brand = Brand.kept.find_or_create_by!(slug: "hookus") { |b| b.name = "HookUs" }
      user = User.create!(status: :active)
      membership = BrandMembership.create!(brand:, user:, status: :active)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, gender:, birthdate: 30.years.ago.to_date,
        status: :active, visibility: :visible, display_name: "Viewer", bio: "hi", country_code: "ZA"
      )
      ProfilePreference.create!(brand:, user:, profile:, interested_in:, min_age: 18, max_age: 99)
      profile
    end

    def write_dir(relative, filenames)
      dir = @root.join(relative)
      FileUtils.mkdir_p(dir)
      filenames.each_with_index do |name, index|
        path = dir.join(name)
        if File.extname(name).downcase == ".txt"
          File.write(path, "not an image")
        else
          File.binwrite(path, jpeg_bytes(index))
        end
      end
    end

    def write_file(relative)
      path = @root.join(relative)
      FileUtils.mkdir_p(path.dirname)
      File.binwrite(path, jpeg_bytes)
    end

    def jpeg_bytes(seed = 0)
      Vips::Image.black(48, 48).add([ 40 + (seed * 30) % 200 ]).cast("uchar").write_to_buffer(".jpg")
    end
  end
end
