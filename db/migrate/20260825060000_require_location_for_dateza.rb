class RequireLocationForDateza < ActiveRecord::Migration[8.1]
  PREVIOUS_COLLECTIONS = %w[photos].freeze
  REQUIRED_COLLECTIONS = %w[photos location].freeze

  def up
    execute <<~SQL.squish
      UPDATE brands
      SET profile_requirements = jsonb_set(
        profile_requirements, '{collections}', '#{REQUIRED_COLLECTIONS.to_json}'::jsonb, true
      ), updated_at = CURRENT_TIMESTAMP
      WHERE slug = 'dateza' AND deleted_at IS NULL
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE brands
      SET profile_requirements = jsonb_set(
        profile_requirements, '{collections}', '#{PREVIOUS_COLLECTIONS.to_json}'::jsonb, true
      ), updated_at = CURRENT_TIMESTAMP
      WHERE slug = 'dateza' AND deleted_at IS NULL
        AND profile_requirements->'collections' = '#{REQUIRED_COLLECTIONS.to_json}'::jsonb
    SQL
  end
end
