# Local-dev-only helper. Brand resolution is strictly host-based with no dev
# bypass (see docs/adr/0006-brand-resolution-strategy.md) — a BrandDomain row
# mapping a host to the "hookus" Brand must exist before any request against
# a locally-running d8n resolves to a brand at all. Idempotent; safe to rerun.
#
# auth_methods defaults to [] for newly-provisioned brands (deny-by-default,
# see db/migrate/*_add_auth_methods_to_brands.rb) — that migration only
# backfilled phone_password/email_password onto a *pre-existing* hookus row,
# which didn't exist when this task first ran. Set explicitly here so a fresh
# dev database doesn't end up with every auth method locked.
namespace :brands do
  desc "Provision the HookUs brand + localhost BrandDomain for local development"
  task seed_hookus_dev: :environment do
    brand = Brand.kept.find_or_create_by!(slug: "hookus") { |b| b.name = "HookUs" }
    brand.update!(auth_methods: %w[phone_password email_password]) if brand.auth_methods.blank?
    BrandDomain.kept.find_or_create_by!(host: "localhost") { |d| d.brand = brand }
    Profiles::HookusProfileCatalog.install!(brand:)

    puts "hookus brand ready: #{brand.slug} -> localhost (auth: #{brand.auth_methods.join(', ')})"
  end
end
