# Operator-facing bootstrap for the very first D8N admin identity. Promotes an
# EXISTING, already-registered User (found by email) to AdminUser and assigns
# it the real "founder" AdminRole on every active brand — one explicit
# assignment per brand, never a platform bypass (ADR 0020). It
# never creates a password, never prints one, and never invents a new
# identity/auth mechanism. See Admin::FounderBootstrap for the full rationale.
#
#   FOUNDER_EMAIL="ops@example.com" FOUNDER_BRAND="hookus" bin/rails d8n:bootstrap_founder
#
# Idempotent: safe to rerun (e.g. after a new brand is provisioned). Existing
# assignments for the founder are retained; any legacy/non-founder assignment
# on that brand is revoked so the upgrade is unambiguous and fail-closed.
#
# FOUNDER_BRAND names which brand's already-registered account is "the"
# admin-rooted identity -- identity is brand-scoped (app/models/
# identity_identifier.rb), so the same email may independently exist on
# several brands as unrelated accounts; this must be explicit, not guessed.
namespace :d8n do
  desc "Promote an existing D8N identity (by email, on one named brand) to admin on every active brand. Usage: FOUNDER_EMAIL=... FOUNDER_BRAND=... bin/rails d8n:bootstrap_founder"
  task bootstrap_founder: :environment do
    brand_slug = ENV["FOUNDER_BRAND"].to_s.strip
    abort "FOUNDER_BRAND is required (the brand of the already-registered account to promote)" if brand_slug.blank?

    brand = Brand.kept.active.find_by(slug: brand_slug)
    abort "No active brand #{brand_slug.inspect}" if brand.blank?

    result =
      begin
        Admin::FounderBootstrap.call(email: ENV["FOUNDER_EMAIL"], brand:)
      rescue Admin::FounderBootstrap::MissingEmail,
             Admin::FounderBootstrap::InvalidEmail,
             Admin::FounderBootstrap::IdentityNotFound,
             Admin::FounderBootstrap::RoleMissing,
             Admin::FounderBootstrap::NoActiveBrands => e
        abort e.message
      end

    brand_slugs = result.assignments.map { |assignment| assignment.brand.slug }
    puts "admin ready: user ##{result.user.id} -> role #{result.admin_role.name.inspect} on brands: #{brand_slugs.join(', ')}"
  end

  desc "Break-glass reset of an admin's MFA. Requires FOUNDER_EMAIL, FOUNDER_BRAND, and CONFIRM_RESET_ADMIN_MFA matching FOUNDER_EMAIL exactly"
  task reset_admin_mfa: :environment do
    email = ENV["FOUNDER_EMAIL"].to_s.strip.downcase
    confirmation = ENV["CONFIRM_RESET_ADMIN_MFA"].to_s.strip.downcase
    brand_slug = ENV["FOUNDER_BRAND"].to_s.strip
    abort "FOUNDER_EMAIL is required" if email.blank?
    abort "FOUNDER_BRAND is required (the brand of the admin-rooted account)" if brand_slug.blank?
    abort "CONFIRM_RESET_ADMIN_MFA must exactly match FOUNDER_EMAIL" unless confirmation == email

    brand = Brand.kept.active.find_by(slug: brand_slug)
    abort "No active brand #{brand_slug.inspect}" if brand.blank?

    begin
      result = Admin::Mfa::OfflineReset.call(email:, brand:)
    rescue Admin::Mfa::OfflineReset::Unavailable => e
      abort e.message
    end

    puts "admin MFA reset: admin_user ##{result.admin_user.id}; all HQ/admin sessions require enrollment again"
  end
end
