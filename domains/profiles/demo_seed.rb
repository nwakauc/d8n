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

      # Ensure the HookUs brand and its capability catalogue exist so option/prompt
      # selections validate. Idempotent; mirrors brands:seed_hookus_dev.
      def resolve_brand!
        brand = Brand.kept.find_or_create_by!(slug: BRAND_SLUG) { |b| b.name = "HookUs" }
        brand.update!(auth_methods: %w[ phone_password email_password ]) if brand.auth_methods.blank?
        Profiles::HookusProfileCatalog.install!(brand:)
        brand
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
