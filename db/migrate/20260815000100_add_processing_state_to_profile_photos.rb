class AddProcessingStateToProfilePhotos < ActiveRecord::Migration[8.0]
  # Tracks the async safe-derivative pipeline. Deliberately separate from
  # `status` (moderation lifecycle) and `visibility` (whether the photo may be
  # shown): a photo can be moderation-visible yet not safe to deliver to other
  # users until processing produces the EXIF-stripped display derivative.
  # `pending` is the safe default so a newly attached raw upload is never
  # eligible for stranger delivery before processing completes.
  def change
    add_column :profile_photos, :processing_state, :integer, default: 0, null: false
    add_column :profile_photos, :processed_at, :datetime
    add_index :profile_photos, [ :brand_id, :processing_state ],
      name: "index_profile_photos_on_brand_id_and_processing_state"
  end
end
