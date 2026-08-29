require "test_helper"
require "rake"

class D8nBootstrapFounderRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("d8n:bootstrap_founder")
    Rake::Task["d8n:bootstrap_founder"].reenable

    AdminRole.kept.find_or_create_by!(name: "moderator")
    @brand = Brand.create!(slug: "hookus", name: "HookUs", status: :active)
    @user = User.create!
    @user.identity_identifiers.create!(
      kind: :email, normalized_value: "founder@example.test", verified_at: Time.current
    )
  end

  teardown do
    ENV.delete("FOUNDER_EMAIL")
  end

  test "bootstraps the founder admin and never prints a password" do
    ENV["FOUNDER_EMAIL"] = "founder@example.test"

    output = capture_io { Rake::Task["d8n:bootstrap_founder"].invoke }.join

    assert AdminUser.kept.joins(:user).exists?(user: @user)
    assert_no_match(/password/i, output)
  end

  test "aborts clearly when FOUNDER_EMAIL is missing" do
    ENV.delete("FOUNDER_EMAIL")

    assert_raises(SystemExit) do
      capture_io { Rake::Task["d8n:bootstrap_founder"].invoke }
    end
  end
end
