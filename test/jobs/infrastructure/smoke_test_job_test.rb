require "test_helper"

module Infrastructure
  class SmokeTestJobTest < ActiveJob::TestCase
    test "can be enqueued" do
      assert_enqueued_with(job: SmokeTestJob, args: ["test-123"]) do
        SmokeTestJob.perform_later("test-123")
      end
    end
  end
end
