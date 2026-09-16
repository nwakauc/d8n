# frozen_string_literal: true

module Media
  # Smallest recovery mechanism for stuck profile-video processing — the video
  # analogue of Media::ProfilePhotoProcessingSweeper (ADR 0029 Pass 2B).
  #
  # Eligible:      pending | retryable failed | stale `processing`
  # NOT eligible:  ready | terminal failed | recent/active `processing`
  #
  # It just (re-)enqueues Media::ProcessProfileVideoJob. It does NOT need to
  # prove "no job is already queued": the job's claim/token contract makes a
  # duplicate enqueue harmless — only the worker holding the current
  # processing_claim_token can finalize.
  class ProfileVideoProcessingSweeper
    DEFAULT_LIMIT = 500

    Result = Data.define(:enqueued, :scanned)

    def self.call(...) = new(...).call

    def initialize(limit: DEFAULT_LIMIT, job: Media::ProcessProfileVideoJob)
      @limit = limit
      @job = job
    end

    def call
      ids = ProfileVideo.processing_sweepable.order(:processing_started_at, :id).limit(@limit).pluck(:id)
      ids.each { |id| @job.perform_later(id) }
      Result.new(enqueued: ids.size, scanned: ids.size)
    end
  end
end
