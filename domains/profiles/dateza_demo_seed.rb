module Profiles
  # Staging/demo seeder for DateZA. It reuses the founders' existing image/name/
  # age catalogue while creating wholly separate DateZA identities, memberships,
  # profiles, taxonomy selections, media keys and activity.
  module DatezaDemoSeed
    DEFAULT_ROOT = DemoSeed::DEFAULT_ROOT
    BRAND_SLUG = "dateza".freeze
    SEED_TAG = "dateza_demo".freeze
    SEED_DEVICE = "dateza-seed-demo".freeze
    SYNTHETIC_LAST_NAME = "Demo".freeze

    Summary = DemoSeed::Summary

    def self.guard!(...)
      DemoSeed.guard!(...)
    end

    def self.call(root: DEFAULT_ROOT, dry_run: false, io: $stdout)
      Runner.new(root:, dry_run:, io:).call
    end

    class Runner
      def initialize(root:, dry_run:, io:)
        @root = root
        @dry_run = dry_run
        @io = io
      end

      def call
        DatezaDemoSeed.guard!
        brand = resolve_brand!
        people = DemoSeed::Catalog.call(root: @root)
        indices = group_indices(people)
        created = updated = photos = skipped = 0
        ladies = people.count { |person| person.gender == "woman" }

        people.each do |person|
          content = Content.for(person, index: indices.fetch(person.seed_key))
          outcome = @dry_run ? plan(person:, brand:) : build(person:, content:, brand:)
          outcome.created ? created += 1 : updated += 1
          photos += outcome.photos_attached
        rescue StandardError => e
          skipped += 1
          @io.puts "  ! skipped #{person.slug}: #{e.class}: #{e.message}"
        end

        Summary.new(
          created:, updated:, ladies:, guys: people.size - ladies,
          photos_attached: photos, skipped:, dry_run: @dry_run
        ).tap { |summary| report(summary) }
      end

      private

      def email_for(person)
        "seed+#{person.slug}@dateza.test"
      end

      def identity_attributes(person)
        # The source catalogue contains first names only. Demo profiles need a
        # private surname to satisfy DateZA completion, so use an overtly synthetic
        # seed marker rather than pretending to possess a real identity claim.
        { first_name: person.display_name, last_name: SYNTHETIC_LAST_NAME }
      end

      def build(person:, content:, brand:)
        DemoSeed::Builder.call(
          person:, content:, brand:, email: email_for(person), seed_tag: SEED_TAG,
          identity_attributes: identity_attributes(person), seed_device: SEED_DEVICE,
          # Demo people are fabricated showcase data, never real members (see
          # DemoSeed.guard!, non-production only) — they exist to populate a
          # working Discover feed immediately. Explicit here (rather than
          # relying on DateZA's brand-level policy) so seed data stays correct
          # even if that policy changes.
          photo_initial_state: Media::PhotoPolicy::IMMEDIATE
        )
      end

      def plan(person:, brand:)
        identifier = IdentityIdentifier.kept.find_by(kind: :email, normalized_value: email_for(person))
        profile = Profile.kept.find_by(user: identifier&.user, brand:) if identifier
        seeded = profile ? profile.profile_photos.kept.filter_map { |photo| photo.metadata["seed_basename"] }.to_set : Set.new
        to_attach = person.image_paths.count { |path| !seeded.include?(File.basename(path)) }
        DemoSeed::Builder::Outcome.new(created: identifier.nil?, photos_attached: to_attach)
      end

      def resolve_brand!
        brand = Brand.kept.find_by(slug: BRAND_SLUG)

        if brand.nil?
          raise DemoSeed::Catalog::Error, "DateZA brand (slug=#{BRAND_SLUG}) not found" if @dry_run

          brand = Brands::DatezaInstaller.call
        end

        DatezaProfileCatalog.install!(brand:) unless @dry_run || catalog_ready?(brand)
        brand
      end

      def catalog_ready?(brand)
        required = DatezaProfileCatalog::REQUIRED_OPTION_GROUPS + [ "interests" ]
        present = brand.profile_option_groups.kept.where(key: required).pluck(:key)
        (required - present).empty? &&
          brand.profile_completion_requirements.fetch("identity_fields") == DatezaProfileCatalog::REQUIRED_IDENTITY_FIELDS
      end

      def group_indices(people)
        counters = Hash.new(0)
        people.each_with_object({}) do |person, acc|
          acc[person.seed_key] = counters[person.gender]
          counters[person.gender] += 1
        end
      end

      def report(summary)
        @io.puts ""
        @io.puts "DateZA demo seed #{summary.dry_run ? 'DRY RUN (no changes written)' : 'complete'}"
        @io.puts ""
        @io.puts "Profiles #{summary.dry_run ? 'to create' : 'created'}: #{summary.created}"
        @io.puts "Profiles #{summary.dry_run ? 'to update' : 'updated'}:  #{summary.updated}"
        @io.puts "Ladies: #{summary.ladies}"
        @io.puts "Guys:   #{summary.guys}"
        @io.puts "Photos #{summary.dry_run ? 'to attach' : 'attached'}: #{summary.photos_attached}"
        @io.puts "Skipped: #{summary.skipped}"
      end
    end
  end
end
