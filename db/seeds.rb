# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

if (hookus = Brand.kept.find_by(slug: "hookus"))
  Profiles::HookusProfileCatalog.install!(brand: hookus)
end

if (dateza = Brand.kept.find_by(slug: "dateza"))
  Profiles::DatezaProfileCatalog.install!(brand: dateza)
end

# Admin::ModeratorContext (see ADR 0013) does not check role name today — any
# active AdminAssignment for a brand grants moderation. "moderator" is the
# only role name the current authorization model actually understands or
# exercises anywhere in the codebase, so it is the only truthful baseline
# role to seed. Do not add roles like "founder" or "admin" here until
# differentiated RBAC exists to give them real meaning.
AdminRole.kept.find_or_create_by!(name: "moderator") do |role|
  role.description = "Grants report moderation and enforcement for an assigned brand (ADR 0013)."
end
