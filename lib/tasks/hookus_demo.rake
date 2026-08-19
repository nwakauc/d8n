# Seeds a realistic HookUs demo population from the founders' image folders
# (docs/user-images/{ladies,guys}). SEED DATA ONLY — no application, discovery,
# or matching behaviour is changed. See Profiles::DemoSeed.
#
#   bin/rails hookus:seed_demo_profiles              # seed (dev/staging only)
#   DRY_RUN=1 bin/rails hookus:seed_demo_profiles    # report, write nothing
#   IMAGE_ROOT=/path bin/rails hookus:seed_demo_profiles
#
# Never runs in production: the task aborts loudly there and offers no override.
namespace :hookus do
  desc "Seed realistic HookUs demo profiles from docs/user-images (dev/staging only)"
  task seed_demo_profiles: :environment do
    begin
      Profiles::DemoSeed.guard!
    rescue Profiles::DemoSeed::EnvNotAllowed => e
      abort e.message
    end

    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
    root = ENV["IMAGE_ROOT"].presence || Profiles::DemoSeed::DEFAULT_ROOT

    Profiles::DemoSeed.call(root:, dry_run:)
  end
end
