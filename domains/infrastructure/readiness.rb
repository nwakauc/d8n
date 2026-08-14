module Infrastructure
  class Readiness
    Result = Data.define(:ready?, :checks, :failed_dependencies)

    def self.call
      checks = {
        primary_database: check_connection(ApplicationRecord.connection_pool),
        queue_database: check_connection(SolidQueue::Job.connection_pool)
      }
      failed_dependencies = checks.filter_map { |name, status| name unless status == "ok" }

      Result.new(
        ready?: failed_dependencies.empty?,
        checks:,
        failed_dependencies:
      )
    end

    def self.check_connection(pool)
      pool.with_connection { |connection| connection.select_value("SELECT 1") }
      "ok"
    rescue ActiveRecord::ActiveRecordError
      "unavailable"
    end
    private_class_method :check_connection
  end
end
