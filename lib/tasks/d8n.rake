# Operator-facing bootstrap for the very first D8N admin identity. Promotes an
# EXISTING, already-registered User (found by email) to AdminUser and assigns
# it the real "founder" AdminRole on every active brand — one explicit
# assignment per brand, never a platform bypass (ADR 0020). It
# never creates a password, never prints one, and never invents a new
# identity/auth mechanism. See Admin::FounderBootstrap for the full rationale.
#
#   FOUNDER_EMAIL="ops@example.com" bin/rails d8n:bootstrap_founder
#
# Idempotent: safe to rerun (e.g. after a new brand is provisioned). Existing
# assignments for the founder are retained; any legacy/non-founder assignment
# on that brand is revoked so the upgrade is unambiguous and fail-closed.
namespace :d8n do
  desc "Promote an existing D8N identity (by email) to admin on every active brand. Usage: FOUNDER_EMAIL=... bin/rails d8n:bootstrap_founder"
  task bootstrap_founder: :environment do
    result =
      begin
        Admin::FounderBootstrap.call(email: ENV["FOUNDER_EMAIL"])
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

  desc "Break-glass reset of an admin's MFA. Requires FOUNDER_EMAIL and CONFIRM_RESET_ADMIN_MFA matching it exactly"
  task reset_admin_mfa: :environment do
    email = ENV["FOUNDER_EMAIL"].to_s.strip.downcase
    confirmation = ENV["CONFIRM_RESET_ADMIN_MFA"].to_s.strip.downcase
    abort "FOUNDER_EMAIL is required" if email.blank?
    abort "CONFIRM_RESET_ADMIN_MFA must exactly match FOUNDER_EMAIL" unless confirmation == email

    begin
      result = Admin::Mfa::OfflineReset.call(email:)
    rescue Admin::Mfa::OfflineReset::Unavailable => e
      abort e.message
    end

    puts "admin MFA reset: admin_user ##{result.admin_user.id}; all HQ/admin sessions require enrollment again"
  end
end
