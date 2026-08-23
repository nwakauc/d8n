class RequirePrivateIdentityNamesForDateza < ActiveRecord::Migration[8.1]
  REQUIRED_IDENTITY_FIELDS = %w[first_name last_name].freeze

  def up
    execute <<~SQL.squish
      UPDATE brands
      SET profile_requirements = jsonb_set(
        jsonb_set(profile_requirements, '{identity_fields}', '#{REQUIRED_IDENTITY_FIELDS.to_json}'::jsonb, true),
        '{enabled_identity_fields}', '#{REQUIRED_IDENTITY_FIELDS.to_json}'::jsonb, true
      ), updated_at = CURRENT_TIMESTAMP
      WHERE slug = 'dateza' AND deleted_at IS NULL
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE brands
      SET profile_requirements = profile_requirements - 'identity_fields' - 'enabled_identity_fields',
          updated_at = CURRENT_TIMESTAMP
      WHERE slug = 'dateza' AND deleted_at IS NULL
        AND profile_requirements->'identity_fields' = '#{REQUIRED_IDENTITY_FIELDS.to_json}'::jsonb
        AND profile_requirements->'enabled_identity_fields' = '#{REQUIRED_IDENTITY_FIELDS.to_json}'::jsonb
    SQL
  end
end
