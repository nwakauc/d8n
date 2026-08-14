module Infrastructure
  class SmokeTestJob < ApplicationJob
    queue_as :default

    def perform(test_id)
      Rails.logger.info("[INFRA_SMOKE_TEST] completed test_id=#{test_id}")
    end
  end
end
