module Notifications
  class ProcessEventJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 5

    def perform(event_id)
      event = NotificationEvent.find_by(id: event_id)
      return unless event

      MaterializeEvent.call(event:)
    end
  end
end
