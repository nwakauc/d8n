module Trust
  module ReportTargets
    # A specific profile photo. Unlike a message (which you retain access to via
    # the conversation even after a block), a photo is only reportable while the
    # viewer can legitimately SEE it: the owner must be visible under the same
    # fundamental rule discovery/profile-view use (Matching::VisibilityScope —
    # brand isolation, active/visible lifecycle, min-age, blocks either way), and
    # the photo must be a deliverable (shown-to-others) photo. The responsible
    # profile is the photo's owner, derived server-side; a viewer cannot report
    # their own photo.
    #
    # Evidence identifies the exact media object (opaque public id, position,
    # lifecycle state) so moderation can locate it. It never contains the R2
    # object key, a storage path, or a URL. If the underlying object is later
    # purged (e.g. account closure), the pixels may be gone but the report still
    # identifies what was flagged — the documented beta retention limitation
    # (ADR 0018), pending a ModerationHold seam.
    class MediaTarget
      def self.resolve(brand:, viewer:, target_public_id:)
        photo = ProfilePhoto.kept.where(brand:).find_by(public_id: target_public_id)
        raise AccessError, :target_unavailable if photo.blank? || !photo.deliverable?

        owner = photo.profile
        visible = owner && owner.id != viewer.id &&
          Matching::VisibilityScope.call(brand:, viewer:).exists?(id: owner.id)
        raise AccessError, :target_unavailable unless visible

        Resolution.new(
          target_type: "profile_media",
          target_id: photo.id,
          reported_profile: owner,
          evidence: {
            "photo_public_id" => photo.public_id,
            "owner_profile_id" => owner.id,
            "position" => photo.position,
            "visibility" => photo.visibility,
            "processing_state" => photo.processing_state,
            "content_created_at" => photo.created_at.iso8601
          }
        )
      end
    end
  end
end
