module Media
  # Direct-to-R2 uploads allocate a blob before the client completes the upload
  # and attaches it. A client that abandons the flow leaves an unattached blob
  # (and possibly an orphaned R2 object). This reclaims those after a safe grace
  # window using Active Storage's own unattached scope and durable purge.
  #
  # The window must comfortably exceed the presigned-upload lifetime plus a
  # client's realistic time to complete, so an in-flight upload is never purged.
  class PurgeUnattachedUploadsJob < ApplicationJob
    queue_as :default

    GRACE_PERIOD = 24.hours

    def perform(older_than: GRACE_PERIOD)
      cutoff = Time.current - older_than

      ActiveStorage::Blob.unattached.where(created_at: ..cutoff).find_each do |blob|
        blob.purge_later
      end
    end
  end
end
