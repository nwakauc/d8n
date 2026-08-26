class AddProfileOpenerToHooks < ActiveRecord::Migration[8.1]
  # Nullable: HookUs hooks stay freeform (no catalog) and never set this. A brand
  # whose opener policy requires a curated catalog (see
  # BrandContract::OpenerConfiguration#catalog_required) sets it at send time; the
  # Hook model then asserts `message == profile_opener.text` (see Hook#opener_matches_catalog),
  # so the stored message can never drift from what was actually offered.
  def change
    add_reference :hooks, :profile_opener, null: true, foreign_key: false

    add_foreign_key :hooks, :profile_openers,
      column: [ :profile_opener_id, :brand_id ], primary_key: [ :id, :brand_id ],
      name: "fk_hooks_profile_opener_tenant"
  end
end
