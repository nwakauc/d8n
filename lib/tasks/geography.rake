# Seeds/refreshes the curated launch-scope place catalog (real reference
# data, not synthetic/demo test data — safe to run in any environment).
#
#   bin/rails geography:seed_south_africa
namespace :geography do
  desc "Seed the curated South African place catalog (provinces/metros/suburbs)"
  task seed_south_africa: :environment do
    Geography::SouthAfricaCatalog.install!
    puts "South Africa place catalog: #{Place.kept.where(country_code: "ZA").count} places"
  end
end
