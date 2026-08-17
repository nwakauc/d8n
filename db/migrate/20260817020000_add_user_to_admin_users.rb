class AddUserToAdminUsers < ActiveRecord::Migration[8.0]
  # Admins authenticate through the existing brand-scoped session as a network
  # User; this link identifies which User is an AdminUser. No separate admin
  # credential/session/auth system is introduced. Nullable + unique (Postgres
  # allows many NULLs) so a placeholder AdminUser without a login is still valid.
  def change
    add_reference :admin_users, :user, null: true, foreign_key: true, index: { unique: true }
  end
end
