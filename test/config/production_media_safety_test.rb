require "test_helper"
require "open3"

class ProductionMediaSafetyTest < ActiveSupport::TestCase
  test "production boots without generic Active Storage routes or profile photo access" do
    script = <<~'RUBY'
      active_storage_paths = Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s
        path if path.start_with?("/rails/active_storage")
      end

      abort "generic Active Storage routes are mounted" if active_storage_paths.any?
      abort "development profile photos are enabled" if Rails.configuration.x.profile_photos_enabled
    RUBY

    env = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE_DUMMY" => "1"
    }
    command = [ RbConfig.ruby, Rails.root.join("bin/rails").to_s, "runner", script ]
    stdout, stderr, status = Open3.capture3(env, *command)

    assert status.success?, <<~MESSAGE
      Production media safety check failed.
      stdout: #{stdout}
      stderr: #{stderr}
    MESSAGE
  end
end
