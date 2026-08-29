# Operator-facing bootstrap for the very first D8N admin identity. Promotes an
# EXISTING, already-registered User (found by email) to AdminUser and assigns
# it the "moderator" AdminRole on every active brand — using only the current
# brand-scoped authorization model (Admin::ModeratorContext, ADR 0013). It
# never creates a password, never prints one, and never invents a new
# identity/auth mechanism. See Admin::FounderBootstrap for the full rationale.
#
#   FOUNDER_EMAIL="ops@example.com" bin/rails d8n:bootstrap_founder
#
# Idempotent: safe to rerun (e.g. after a new brand is provisioned) — it only
# adds what's missing and never touches or removes an existing assignment.
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
end
