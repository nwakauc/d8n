class AddProcessingClaimToProfileVideos < ActiveRecord::Migration[8.1]
  # Profile-video processing-lifecycle hardening — the video analogue of
  # AddProcessingClaimToProfilePhotos (ADR 0028 §6 / ADR 0029 Pass 2B). A worker
  # that crashes after claiming `processing` must become recoverable, and a
  # stale worker that wakes after a reclaim must not finalize someone else's
  # claim (the ABA guard is the per-claim token). `metadata` persists the
  # deterministic derivative keys so playback/poster can be re-validated after
  # the raw original is purged. NOT a migration table and NOT migration transfer
  # identity — reusable D8N runtime hardening.
  def change
    add_column :profile_videos, :processing_started_at, :datetime, null: true
    add_column :profile_videos, :processing_claim_token, :uuid, null: true
    add_column :profile_videos, :metadata, :jsonb, null: false, default: {}

    add_index :profile_videos, [ :processing_state, :processing_started_at ],
      name: "index_profile_videos_on_processing_state_and_started_at"
  end
end
