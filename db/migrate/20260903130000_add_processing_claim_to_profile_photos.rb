class AddProcessingClaimToProfilePhotos < ActiveRecord::Migration[8.1]
  # Reusable D8N profile-photo processing-lifecycle hardening (ADR 0028 §6 /
  # MEDIA-TRANSFER.md §16b). NOT migration transfer identity and NOT a migration
  # table: a worker that crashes after claiming `processing` must become
  # recoverable, and a stale worker that wakes after a reclaim must not finalize
  # someone else's claim (the ABA guard is the per-claim token).
  def change
    add_column :profile_photos, :processing_started_at, :datetime, null: true
    add_column :profile_photos, :processing_claim_token, :uuid, null: true

    # Sweeper query shape: eligible rows are `pending` / `failed`, plus
    # `processing` whose claim has gone stale (`processing_started_at` old).
    add_index :profile_photos, [ :processing_state, :processing_started_at ],
      name: "index_profile_photos_on_processing_state_and_started_at"
  end
end
