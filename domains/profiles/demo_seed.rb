module Profiles
  # Staging/demo seeder for a realistic HookUs population, driven entirely by the
  # founders' on-disk image folders (docs/user-images/{ladies,guys}). SEED DATA
  # ONLY: it composes existing models/services and changes no application,
  # discovery, or matching behaviour. See lib/tasks/hookus_demo.rake for the guard
  # and command.
  module DemoSeed
    DEFAULT_ROOT = Rails.root.join("docs", "user-images")
    BRAND_SLUG = "hookus".freeze
    # Demo seeding is fixture data; by default it only runs in dev/test. The D8N
    # staging host, however, runs as RAILS_ENV=production, so seeding it (or a real
    # production) requires a DELIBERATE, loud opt-in: SEED_DEMO_ALLOW_PRODUCTION=1.
    # Absent that flag the task aborts, so it can never seed a real env by accident.
    ALLOWED_ENVS = %w[ development staging test ].freeze
    PRODUCTION_OVERRIDE = "SEED_DEMO_ALLOW_PRODUCTION".freeze

    class EnvNotAllowed < StandardError; end

    def self.guard!(env: Rails.env, allow_production: override_set?)
      return if ALLOWED_ENVS.include?(env.to_s)
      return if allow_production

      raise EnvNotAllowed,
        "Refusing to seed demo profiles in '#{env}'. Set #{PRODUCTION_OVERRIDE}=1 to override deliberately."
    end

    def self.override_set?
      ActiveModel::Type::Boolean.new.cast(ENV[PRODUCTION_OVERRIDE])
    end

    Summary = Data.define(
      :created, :updated, :ladies, :guys, :photos_attached, :skipped, :dry_run
    ) do
      def total = created + updated
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
        DemoSeed.guard!
        brand = resolve_brand!
        people = Catalog.call(root: @root)
        indices = group_indices(people)
        created = updated = photos = skipped = 0
        ladies = people.count { |person| person.gender == "woman" }

        people.each do |person|
          content = Content.for(person, index: indices.fetch(person.seed_key))
          if @dry_run
            outcome = plan(person:, brand:)
          else
            outcome = Builder.call(person:, content:, brand:)
          end
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

      # Read-only classification for a dry run: what a real run WOULD create,
      # update, and attach — without writing anything.
      def plan(person:, brand:)
        identifier = IdentityIdentifier.kept.find_by(kind: :email, normalized_value: person.email)
        profile = Profile.kept.find_by(user: identifier&.user, brand:) if identifier
        seeded = profile ? profile.profile_photos.kept.filter_map { |p| p.metadata["seed_basename"] }.to_set : Set.new
        to_attach = person.image_paths.count { |path| !seeded.include?(File.basename(path)) }
        Builder::Outcome.new(created: identifier.nil?, photos_attached: to_attach)
      end

      # Resolve the HookUs brand and make sure its capability catalogue is present
      # so option/prompt selections validate. A dry run is strictly READ-ONLY: it
      # never creates the brand nor rewrites the catalogue. On an already-configured
      # env (e.g. staging, where the catalogue exists) the install is skipped, so a
      # rerun neither rewrites catalogue rows nor races a second container on them.
      def resolve_brand!
        brand = Brand.kept.find_by(slug: BRAND_SLUG)

        if brand.nil?
          raise Catalog::Error, "HookUs brand (slug=#{BRAND_SLUG}) not found" if @dry_run

          brand = Brand.create!(slug: BRAND_SLUG, name: "HookUs",
            auth_methods: %w[ phone_password email_password ])
        end

        install_catalog!(brand) unless @dry_run || catalog_ready?(brand)
        brand
      end

      def install_catalog!(brand)
        brand.update!(auth_methods: %w[ phone_password email_password ]) if brand.auth_methods.blank?
        Profiles::HookusProfileCatalog.install!(brand:)
      end

      # The catalogue is ready when every option group the seeder writes to already
      # exists for the brand (intents/vibes/interests + the lifestyle groups).
      def catalog_ready?(brand)
        required = (%w[ intents vibes interests pets cannabis ] + Content::LIFESTYLE_KEYS).uniq
        present = brand.profile_option_groups.kept.where(key: required).pluck(:key)
        (required - present).empty?
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
        @io.puts "HookUs demo seed #{summary.dry_run ? 'DRY RUN (no changes written)' : 'complete'}"
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
