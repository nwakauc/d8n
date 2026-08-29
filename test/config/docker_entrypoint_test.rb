require "test_helper"
require "open3"
require "fileutils"
require "tmpdir"

class DockerEntrypointTest < ActiveSupport::TestCase
  test "boots the rails server with DATEZA_API_HOST invokes brands:install_dateza before serving" do
    invocations = run_entrypoint(["./bin/rails", "server"], "DATEZA_API_HOST" => "dateza-api.d8n.tech")

    assert_equal ["db:prepare", "brands:install_dateza", "server"], invocations
  end

  test "boots the rails server without DATEZA_API_HOST does not touch brand provisioning" do
    invocations = run_entrypoint(["./bin/rails", "server"], "DATEZA_API_HOST" => nil)

    assert_equal ["db:prepare", "server"], invocations
  end

  test "boots the Solid Queue worker never invokes brands:install_dateza" do
    invocations = run_entrypoint(["bin/jobs"], "DATEZA_API_HOST" => "dateza-api.d8n.tech")

    assert_equal ["db:prepare"], invocations
  end

  private

  # Runs the real bin/docker-entrypoint script against a stub `./bin/rails`
  # that records each subcommand it's invoked with, so we assert on behavior
  # (what actually runs, and in what order) rather than parsing the script text.
  def run_entrypoint(command, env)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "bin"))
      log_path = File.join(dir, "invocations.log")

      File.write(File.join(dir, "bin", "rails"), <<~SCRIPT)
        #!/bin/bash
        echo "$1" >> #{log_path}
        exit 0
      SCRIPT
      FileUtils.chmod("+x", File.join(dir, "bin", "rails"))

      File.write(File.join(dir, "bin", "jobs"), "#!/bin/bash\nexit 0\n")
      FileUtils.chmod("+x", File.join(dir, "bin", "jobs"))

      _stdout, stderr, status = Open3.capture3(
        env,
        Rails.root.join("bin/docker-entrypoint").to_s, *command,
        chdir: dir
      )

      assert status.success?, "entrypoint failed: #{stderr}"
      File.exist?(log_path) ? File.readlines(log_path, chomp: true) : []
    end
  end
end
