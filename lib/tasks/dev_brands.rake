# Local-dev-only helper. Brand resolution is strictly host-based with no dev
# bypass (see docs/adr/0006-brand-resolution-strategy.md) — a BrandDomain row
# mapping a host to the "hookus" Brand must exist before any request against
# a locally-running d8n resolves to a brand at all. Idempotent; safe to rerun.
namespace :brands do
  desc "Provision the HookUs brand + localhost BrandDomain for local development"
  task seed_hookus_dev: :environment do
    brand = Brand.kept.find_or_create_by!(slug: "hookus") { |b| b.name = "HookUs" }
    BrandDomain.kept.find_or_create_by!(host: "localhost") { |d| d.brand = brand }
    Profiles::HookusProfileCatalog.install!(brand:)

    puts "hookus brand ready: #{brand.slug} -> localhost"
  end
end
