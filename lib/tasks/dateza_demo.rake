# Seeds DateZA demo profiles from docs/user-images/{ladies,guys}. The filenames
# remain the source of public first name and displayed age. A private, explicitly
# synthetic surname is added only so these synthetic profiles satisfy DateZA's
# real completion contract.
#
#   bin/rails dateza:seed_demo_profiles
#   DRY_RUN=1 bin/rails dateza:seed_demo_profiles
#   IMAGE_ROOT=/path bin/rails dateza:seed_demo_profiles
namespace :dateza do
  desc "Seed realistic DateZA demo profiles from docs/user-images (dev/staging only)"
  task seed_demo_profiles: :environment do
    begin
      Profiles::DatezaDemoSeed.guard!
    rescue Profiles::DemoSeed::EnvNotAllowed => e
      abort e.message
    end

    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
    root = ENV["IMAGE_ROOT"].presence || Profiles::DatezaDemoSeed::DEFAULT_ROOT

    Profiles::DatezaDemoSeed.call(root:, dry_run:)
  end
end
