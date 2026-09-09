class AddSensitivePreservationDestinations < ActiveRecord::Migration[8.1]
  # Lossless D8N homes for the sensitive Date9ja `users` values that previously
  # had none (DECISIONS.md "Retain ..." rows). Sensitivity governs HOW a value
  # is stored and exposed, not WHETHER D8N represents it:
  #
  #   * interest_in_nigerian_culture — free-text self-description, owner-only.
  #   * preferred_attributes — a generic owner-only matching-preference store,
  #     keyed by attribute ("religion" / "tribe" / "ethnicity" / "genotype"),
  #     each an array of controlled codes. One reusable column instead of four
  #     bespoke ones; other brands may key it differently.
  #
  # tribe / religion / genotype / ethnicity / denomination /
  # intertribal_marriage_openness / polygamy_openness are controlled
  # vocabularies and are stored as ProfileOptionSelection rows against option
  # groups (Profiles::CapabilityCatalog) — no column needed here.
  def change
    add_column :profiles, :interest_in_nigerian_culture, :text
    add_column :profile_preferences, :preferred_attributes, :jsonb, null: false, default: {}
  end
end
