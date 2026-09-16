require "test_helper"
require "rake"

class D8nBootstrapFounderRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("d8n:bootstrap_founder")
    Rake::Task["d8n:bootstrap_founder"].reenable

    AdminRole.kept.find_or_create_by!(name: "founder")
    @brand = Brand.create!(slug: "hookus", name: "HookUs", status: :active)
    @user = User.create!
    @user.identity_identifiers.create!(
      brand: @brand, kind: :email, normalized_value: "founder@example.test", verified_at: Time.current
    )
  end

  teardown do
    ENV.delete("FOUNDER_EMAIL")
    ENV.delete("FOUNDER_BRAND")
  end

  test "bootstraps the founder admin and never prints a password" do
    ENV["FOUNDER_EMAIL"] = "founder@example.test"
    ENV["FOUNDER_BRAND"] = "hookus"

    output = capture_io { Rake::Task["d8n:bootstrap_founder"].invoke }.join

    assert AdminUser.kept.joins(:user).exists?(user: @user)
    assert_no_match(/password/i, output)
  end

  test "aborts clearly when FOUNDER_EMAIL is missing" do
    ENV.delete("FOUNDER_EMAIL")
    ENV["FOUNDER_BRAND"] = "hookus"

    assert_raises(SystemExit) do
      capture_io { Rake::Task["d8n:bootstrap_founder"].invoke }
    end
  end

  test "aborts clearly when FOUNDER_BRAND is missing" do
    ENV["FOUNDER_EMAIL"] = "founder@example.test"
    ENV.delete("FOUNDER_BRAND")

    assert_raises(SystemExit) do
      capture_io { Rake::Task["d8n:bootstrap_founder"].invoke }
    end
  end

  test "aborts clearly when FOUNDER_BRAND does not match an active brand" do
    ENV["FOUNDER_EMAIL"] = "founder@example.test"
    ENV["FOUNDER_BRAND"] = "nonexistent-brand"

    assert_raises(SystemExit) do
      capture_io { Rake::Task["d8n:bootstrap_founder"].invoke }
    end
  end
end
