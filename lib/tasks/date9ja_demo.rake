# Seeds real, active, visible, photo-complete Date9ja demo profiles from
# docs/user-images/{ladies,guys} so there is a genuine pool to browse/like/
# match against while testing Introductions/Explore. Each profile goes
# through the real Profiles::Publication gate and the real photo-processing
# pipeline — nothing is faked at the discovery layer. The first deterministic
# catalog profile also receives a generated, processed intro video so card
# surfaces exercise the real `has_video_intro` contract.
#
#   bin/rails date9ja:seed_demo_profiles
#   DRY_RUN=1 bin/rails date9ja:seed_demo_profiles
#   IMAGE_ROOT=/path bin/rails date9ja:seed_demo_profiles
namespace :date9ja do
  desc "Seed realistic Date9ja demo profiles from docs/user-images (dev/staging only)"
  task seed_demo_profiles: :environment do
    begin
      Profiles::Date9jaDemoSeed.guard!
    rescue Profiles::DemoSeed::EnvNotAllowed => e
      abort e.message
    end

    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
    root = ENV["IMAGE_ROOT"].presence || Profiles::Date9jaDemoSeed::DEFAULT_ROOT

    Profiles::Date9jaDemoSeed.call(root:, dry_run:)
  end
end
