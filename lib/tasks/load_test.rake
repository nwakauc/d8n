require "json"

namespace :load_test do
  namespace :synthetic do
    desc "Create or reconcile the guarded synthetic dating dataset"
    task create: :environment do
      result = LoadTesting::SyntheticDataset.new(
        brand_slug: ENV.fetch("D8N_LOAD_TEST_BRAND", "hookus"),
        count: ENV.fetch("D8N_LOAD_TEST_COUNT", LoadTesting::SyntheticDataset::DEFAULT_COUNT),
        password: ENV["D8N_LOAD_TEST_PASSWORD"]
      ).create!
      puts JSON.pretty_generate(result.to_h)
    end

    desc "Delete only records anchored to the guarded synthetic identifier namespace"
    task cleanup: :environment do
      result = LoadTesting::SyntheticDataset.new(
        brand_slug: ENV.fetch("D8N_LOAD_TEST_BRAND", "hookus")
      ).cleanup!
      puts JSON.pretty_generate(result.to_h)
    end

    desc "Report counts for the guarded synthetic dating dataset"
    task report: :environment do
      result = LoadTesting::SyntheticDataset.new(
        brand_slug: ENV.fetch("D8N_LOAD_TEST_BRAND", "hookus")
      ).report
      puts JSON.pretty_generate(result.to_h)
    end
  end
end
