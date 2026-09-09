class AddPreferredCountryCodesToProfilePreferences < ActiveRecord::Migration[8.1]
  # Date9ja collects a MULTI-country residence preference (`users.preferred_countries`,
  # 84 non-empty rows in the 2026-09-08 snapshot). D8N only had the scalar
  # `profile_preferences.country`, so the legacy value had no lossless
  # destination. This adds one: an ordered list of ISO-3166 alpha-2 codes,
  # shaped like the sibling `interested_in` jsonb list. No brand requires it.
  def change
    add_column :profile_preferences, :preferred_country_codes, :jsonb, null: false, default: []
  end
end
