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

if (date9ja = Brand.kept.find_by(slug: "date9ja"))
  Profiles::Date9jaProfileCatalog.install!(brand: date9ja)
end

# ADR 0020 gives every role a centralized, tested capability meaning. Seeds
# create vocabulary only; capabilities remain immutable application policy.
{
  "founder" => "Bootstrap-only root operator for an explicitly assigned brand.",
  "super_admin" => "Manages non-privileged operators and all current brand operations.",
  "operations" => "Reads member/operational state and manages brand operations.",
  "trust_safety" => "Reads and moderates reports, enforcements, and profile photos.",
  "support" => "Reads Member 360 and discovery diagnostics for support workflows.",
  "engineering" => "Reads discovery diagnostics and future system-health surfaces.",
  "marketing" => "Reserved for future authorized marketing analytics.",
  "analyst" => "Reserved for future read-only analytics.",
  "moderator" => "Legacy compatibility role for current moderation and HQ operational surfaces."
}.each do |name, description|
  role = AdminRole.kept.find_or_initialize_by(name:)
  role.description = description
  role.save!
end
