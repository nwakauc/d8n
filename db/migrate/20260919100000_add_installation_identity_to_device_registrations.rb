class AddInstallationIdentityToDeviceRegistrations < ActiveRecord::Migration[8.0]
  def change
    add_column :device_registrations, :installation_id, :string
    add_column :device_registrations, :device_name, :string
    add_column :device_registrations, :last_error, :string

    add_index :device_registrations, [ :brand_id, :installation_id ],
      unique: true,
      where: "installation_id IS NOT NULL AND deleted_at IS NULL",
      name: "idx_device_registrations_active_installation"
  end
end
