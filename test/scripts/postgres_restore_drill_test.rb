require "test_helper"
require "open3"

class PostgresRestoreDrillTest < ActiveSupport::TestCase
  RESTORE_SCRIPT = Rails.root.join("script/operations/postgres_restore_drill").to_s

  test "requires explicit disposable restore confirmation" do
    _stdout, stderr, status = run_restore(
      "D8N_RESTORE_TARGET" => "d8n_restore_primary_test"
    )

    assert_equal 64, status.exitstatus
    assert_includes stderr, "Refusing restore"
  end

  test "refuses a target without the disposable prefix before reading the archive" do
    _stdout, stderr, status = run_restore(
      "D8N_RESTORE_CONFIRM" => "CREATE_DISPOSABLE_RESTORE_DATABASE",
      "D8N_RESTORE_TARGET" => "d8n_production"
    )

    assert_equal 64, status.exitstatus
    assert_includes stderr, "target must begin with d8n_restore_"
  end

  test "refuses an unknown database kind before reading the archive" do
    _stdout, stderr, status = run_restore(
      "D8N_RESTORE_CONFIRM" => "CREATE_DISPOSABLE_RESTORE_DATABASE",
      "D8N_RESTORE_TARGET" => "d8n_restore_test",
      "D8N_RESTORE_KIND" => "unknown"
    )

    assert_equal 64, status.exitstatus
    assert_includes stderr, "must be primary or queue"
  end

  private

  def run_restore(environment)
    defaults = {
      "D8N_RESTORE_BACKUP" => "/does/not/exist.dump",
      "D8N_RESTORE_KIND" => "primary"
    }

    Open3.capture3(defaults.merge(environment), RESTORE_SCRIPT)
  end
end
