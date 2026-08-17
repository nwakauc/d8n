module Media
  # Physically erases a closed account's profile media from object storage. Runs
  # after the (synchronous) closure has already removed product access, so the
  # account is never left open waiting on R2. Purges both the safe display
  # derivative and any remaining raw original for every photo of the profile,
  # including already soft-deleted ones.
  #
  # Idempotent and retry-safe: an already-purged attachment is skipped, a
  # never-completed run is re-tried, and the closure's `media_purge_state` records
  # the outcome so a persistently failing purge is operationally discoverable
  # rather than silently marked done.
  class PurgeProfileMediaJob < ApplicationJob
    queue_as :default

    class TransientError < StandardError; end

    retry_on TransientError, wait: :polynomially_longer, attempts: 5

    def perform(account_closure_id)
      closure = AccountClosure.find_by(id: account_closure_id)
      return if closure.nil? || closure.media_purge_completed?
      return complete(closure) if closure.profile_id.nil?

      purge_profile_media(closure.profile_id)
      complete(closure)
    rescue StandardError => e
      closure&.update!(media_purge_state: :failed)
      raise TransientError, "media purge failed: #{e.class}"
    end

    private

    def purge_profile_media(profile_id)
      ProfilePhoto.where(profile_id:).find_each do |photo|
        photo.image.purge if photo.image.attached?
        photo.display_image.purge if photo.display_image.attached?
      end
    end

    def complete(closure)
      closure.update!(media_purge_state: :completed, media_purged_at: Time.current)
    end
  end
end
