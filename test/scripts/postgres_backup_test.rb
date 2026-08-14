require "test_helper"
require "open3"
require "tmpdir"

class PostgresBackupTest < ActiveSupport::TestCase
  BACKUP_SCRIPT = Rails.root.join("script/operations/postgres_backup").to_s

  test "rejects an unsafe backup label before invoking pg_dump" do
    Dir.mktmpdir do |output_directory|
      _stdout, stderr, status = Open3.capture3(
        backup_environment(output_directory).merge("D8N_BACKUP_LABEL" => "../../unsafe"),
        BACKUP_SCRIPT
      )

      assert_equal 64, status.exitstatus
      assert_includes stderr, "D8N_BACKUP_LABEL"
      assert_empty Dir.children(output_directory)
    end
  end

  test "removes a partial archive when pg_dump fails" do
    Dir.mktmpdir do |working_directory|
      output_directory = File.join(working_directory, "backups")
      fake_bin = File.join(working_directory, "bin")
      FileUtils.mkdir_p(fake_bin)
      fake_pg_dump = File.join(fake_bin, "pg_dump")
      File.write(fake_pg_dump, <<~SH)
        #!/bin/sh
        for argument in "$@"; do
          case "$argument" in
            --file=*) printf 'partial' > "${argument#--file=}" ;;
          esac
        done
        exit 1
      SH
      FileUtils.chmod(0o700, fake_pg_dump)

      _stdout, _stderr, status = Open3.capture3(
        backup_environment(output_directory).merge("PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}"),
        BACKUP_SCRIPT
      )

      assert_equal 1, status.exitstatus
      assert_empty Dir.children(output_directory)
    end
  end

  private

  def backup_environment(output_directory)
    {
      "D8N_BACKUP_DATABASE" => "d8n_test",
      "D8N_BACKUP_LABEL" => "d8n-test",
      "D8N_BACKUP_OUTPUT_DIR" => output_directory
    }
  end
end
