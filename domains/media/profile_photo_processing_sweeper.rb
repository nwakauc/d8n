# frozen_string_literal: true

module Media
  # Smallest recovery mechanism for stuck profile-photo processing
  # (MEDIA-TRANSFER.md §16b "Sweeper — final contract").
  #
  # Eligible:      pending | retryable failed | stale `processing`
  # NOT eligible:  ready | terminal failed | recent/active `processing`
  #
  # It just (re-)enqueues Media::ProcessProfilePhotoJob. It does NOT need to
  # prove "no job is already queued": ProcessProfilePhotoJob's claim/token
  # contract makes a duplicate enqueue harmless — only the worker holding the
  # current processing_claim_token can finalize.
  class ProfilePhotoProcessingSweeper
    DEFAULT_LIMIT = 500

    Result = Data.define(:enqueued, :scanned)

    def self.call(...) = new(...).call

    def initialize(limit: DEFAULT_LIMIT, job: Media::ProcessProfilePhotoJob)
      @limit = limit
      @job = job
    end

    def call
      ids = ProfilePhoto.processing_sweepable.order(:processing_started_at, :id).limit(@limit).pluck(:id)
      ids.each { |id| @job.perform_later(id) }
      Result.new(enqueued: ids.size, scanned: ids.size)
    end
  end
end
