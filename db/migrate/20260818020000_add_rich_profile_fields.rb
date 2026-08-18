class AddRichProfileFields < ActiveRecord::Migration[8.1]
  # Additive profile enrichment (see ADR 0017). Every column is optional and
  # default-safe so existing profiles keep validating and serializing untouched —
  # no backfill, no invented data. Controlled-vocabulary capabilities (orientation,
  # education, religion, diet, lifestyle, intent, meeting pace, personality, etc.)
  # deliberately live in the brand-configurable profile_options taxonomy, NOT here;
  # only genuinely free-text/scalar identity fields and structured languages are
  # columns.
  def change
    change_table :profiles, bulk: true do |t|
      # Short self-declared pronouns, e.g. "she/her". Free text (brands vary too
      # much for a fixed enum); length-capped and stripped like other free text.
      t.string :pronouns, limit: 40
      # Work identity kept separate from the existing free-text `occupation` so a
      # brand can expose one without the other.
      t.string :job_title, limit: 120
      t.string :company_name, limit: 120
      # Education free text; the education *level* is a controlled option group.
      t.string :school_or_institution, limit: 160
      # "What are you looking for?" personality free text — kept separate from the
      # structured relationship_intent option group (filtering vs. voice).
      t.text :looking_for_text
      # Optional, owner-only (never serialized to other members): how many children
      # someone has. No other child detail is ever stored (ADR/ticket §11).
      t.integer :children_count
      # Structured languages: array of { code, proficiency, primary }. Distinct from
      # the retained legacy free-text `languages_spoken` array so no existing payload
      # breaks; codes are validated against a config-driven taxonomy, not hardcoded.
      t.jsonb :languages, null: false, default: []
    end

    add_check_constraint :profiles,
      "children_count IS NULL OR (children_count >= 0 AND children_count <= 30)",
      name: "chk_profiles_children_count"
  end
end
