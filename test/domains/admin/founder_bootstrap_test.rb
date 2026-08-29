require "test_helper"

module Admin
  class FounderBootstrapTest < ActiveSupport::TestCase
    def setup
      @role = AdminRole.kept.find_or_create_by!(name: "moderator")
      @hookus = Brand.create!(slug: "hookus", name: "HookUs", status: :active)
      @dateza = Brand.create!(slug: "dateza", name: "DateZA", status: :active)
      @user = User.create!
      @user.identity_identifiers.create!(
        kind: :email, normalized_value: "founder@example.test", verified_at: Time.current
      )
    end

    test "promotes an existing user to AdminUser and assigns moderator on every active brand" do
      result = FounderBootstrap.call(email: " Founder@Example.TEST ")

      assert_equal @user, result.user
      admin_user = AdminUser.kept.find_by!(user: @user)
      assert admin_user.active?
      assert_equal [ @dateza.id, @hookus.id ].sort,
        AdminAssignment.kept.where(admin_user:).pluck(:brand_id).sort
      assert_equal 2, AdminAssignment.kept.where(admin_user:, admin_role: @role, status: :active).count
      assert BrandMembership.kept.active.exists?(user: @user, brand: @hookus)
      assert BrandMembership.kept.active.exists?(user: @user, brand: @dateza)
    end

    test "fails safely when no existing identity matches the email" do
      assert_no_difference [ -> { User.count }, -> { AdminUser.count }, -> { IdentityIdentifier.count } ] do
        assert_raises(FounderBootstrap::IdentityNotFound) do
          FounderBootstrap.call(email: "nobody@example.test")
        end
      end
    end

    test "is idempotent on repeated execution" do
      FounderBootstrap.call(email: "founder@example.test")

      assert_no_difference [ -> { AdminUser.count }, -> { AdminAssignment.count }, -> { BrandMembership.count } ] do
        FounderBootstrap.call(email: "founder@example.test")
      end
    end

    test "rerun after a new brand exists adds only the missing assignment" do
      FounderBootstrap.call(email: "founder@example.test")
      admin_user = AdminUser.kept.find_by!(user: @user)
      existing_assignment = AdminAssignment.kept.find_by!(admin_user:, brand: @hookus)

      date9ja = Brand.create!(slug: "date9ja", name: "Date9ja", status: :active)

      assert_difference -> { AdminAssignment.count }, 1 do
        FounderBootstrap.call(email: "founder@example.test")
      end

      assert AdminAssignment.kept.exists?(admin_user:, brand: date9ja, admin_role: @role)
      assert existing_assignment.reload.active?
    end

    test "preserves an existing assignment untouched" do
      FounderBootstrap.call(email: "founder@example.test")
      admin_user = AdminUser.kept.find_by!(user: @user)
      assignment = AdminAssignment.kept.find_by!(admin_user:, brand: @hookus)
      original_created_at = assignment.created_at

      FounderBootstrap.call(email: "founder@example.test")

      assert_equal original_created_at, assignment.reload.created_at
    end

    test "missing FOUNDER_EMAIL fails clearly" do
      assert_raises(FounderBootstrap::MissingEmail) { FounderBootstrap.call(email: nil) }
      assert_raises(FounderBootstrap::MissingEmail) { FounderBootstrap.call(email: "") }
    end

    test "invalid email fails clearly" do
      assert_raises(FounderBootstrap::InvalidEmail) { FounderBootstrap.call(email: "not-an-email") }
    end

    test "does not create a duplicate identity or AdminUser" do
      FounderBootstrap.call(email: "founder@example.test")

      assert_equal 1, User.where(id: @user.id).count
      assert_equal 1, IdentityIdentifier.kept.where(kind: :email, normalized_value: "founder@example.test").count
      assert_equal 1, AdminUser.kept.where(user: @user).count
    end

    test "raises when the moderator role is missing" do
      @role.update!(deleted_at: Time.current)

      assert_raises(FounderBootstrap::RoleMissing) do
        FounderBootstrap.call(email: "founder@example.test")
      end
    end

    test "raises when no active brands exist" do
      Brand.update_all(deleted_at: Time.current)

      assert_raises(FounderBootstrap::NoActiveBrands) do
        FounderBootstrap.call(email: "founder@example.test")
      end
    end

    test "never creates a Credential or a platform-level role" do
      FounderBootstrap.call(email: "founder@example.test")

      assert_equal 0, Credential.count
      assert_not AdminRole.kept.exists?(name: "founder")
      assert_equal %w[ moderator ], AdminRole.kept.pluck(:name)
    end
  end
end
