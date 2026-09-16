# frozen_string_literal: true

module Migration
  module MediaTransfer
    # Active Storage idempotency / adoption rules (ADR 0028 §4 / MEDIA-TRANSFER.md
    # §7b). Rails 8.1 persists the Blob row before the object and has NO supported
    # "adopt an existing remote object" API.
    #
    # NO network / storage / libvips operation is performed while a DB row lock or
    # transaction is held (review Finding 2). Every case follows:
    #
    #   A. short DB snapshot / coordination (DB-only)
    #   B. external storage operation OUTSIDE any lock/transaction
    #   C. short DB authoritative re-check / finalization, fail closed on drift
    #
    # For key K and expected identity
    #   E = { md5, byte_size, content_type (EXACT canonical type), dest_service }:
    #
    #   1 no row, no object      -> DB create row (short) ; upload (outside) ; re-verify (outside)
    #   2 row + object           -> bounded remote re-read + re-hash + re-decode (outside) ;
    #                               short lock to re-prove row identity unchanged
    #   3 row, no object         -> short lock: prove + capture identity ; release ;
    #                               upload (outside) ; re-verify (outside) ;
    #                               short lock: re-prove identity ; else fail closed
    #   4 no row, object exists  -> remote_orphan: never adopt/overwrite/delete
    #   5 identity/content != E  -> destination_collision, fail closed
    module AdoptOrUpload
      module_function

      # @return [ActiveStorage::Blob] on success, or a Migration::MediaTransfer::Result on a fail-closed case.
      def call(key:, io:, expected:, media_kind: Migration::MediaTransfer::MediaKind::DEFAULT,
        image_processor: Media::ImageProcessor)
        service = ActiveStorage::Blob.services.fetch(expected[:dest_service].to_sym)
        row = ActiveStorage::Blob.find_by(key:)                       # A: DB snapshot
        object = Migration::MediaTransfer.service_exist?(service, key) # B: external, no lock

        if row.nil? && !object
          case_1_create_and_upload(key:, io:, expected:, service:, media_kind:, image_processor:)
        elsif row.nil? && object
          remote_orphan
        elsif object
          case_2_verify_and_reuse(row:, expected:, service:, media_kind:, image_processor:)
        else
          case_3_recover(row:, io:, expected:, service:, media_kind:, image_processor:)
        end
      end

      # --- case 1 -----------------------------------------------------------

      def case_1_create_and_upload(key:, io:, expected:, service:, media_kind:, image_processor:)
        blob = ActiveStorage::Blob.create!(                           # A: DB-only, one INSERT, no lock
          key:,
          filename: "original.#{Migration::MediaTransfer::CanonicalKey.extension_for(expected[:content_type])}",
          byte_size: expected[:byte_size],
          checksum: expected[:md5],
          content_type: expected[:content_type],
          service_name: expected[:dest_service]
        )
        io.rewind
        blob.upload_without_unfurling(io)                             # B: outside any lock/transaction
        remote = verify_remote!(blob, expected, service, media_kind, image_processor) # B
        remote.is_a?(Migration::MediaTransfer::Result) ? remote : blob
      rescue ActiveRecord::RecordNotUnique
        call(key:, io:, expected:, media_kind:, image_processor:) # concurrent creator won — re-dispatch
      end

      # --- case 2 -----------------------------------------------------------

      def case_2_verify_and_reuse(row:, expected:, service:, media_kind:, image_processor:)
        return collision unless row_identity_matches?(row, expected)

        remote = verify_remote!(row, expected, service, media_kind, image_processor) # B: bounded, NO lock
        return remote if remote.is_a?(Migration::MediaTransfer::Result)

        recheck_identity(row.id, expected)                              # C: short lock
      end

      # --- case 3 -----------------------------------------------------------

      def case_3_recover(row:, io:, expected:, service:, media_kind:, image_processor:)
        proven = short_lock(row.id) do |fresh|                          # A: prove + capture
          if fresh.nil? then :gone
          elsif !row_identity_matches?(fresh, expected) then :mismatch
          else identity_snapshot(fresh)
          end
        end
        return remote_orphan if proven == :gone
        return collision if proven == :mismatch

        blob = ActiveStorage::Blob.find(row.id)
        io.rewind
        blob.upload_without_unfurling(io)                               # B: outside lock
        remote = verify_remote!(blob, expected, service, media_kind, image_processor) # B
        return remote if remote.is_a?(Migration::MediaTransfer::Result)

        recheck_snapshot(row.id, proven)                                # C: nothing swapped the row
      end

      # --- short DB rechecks (C) -----------------------------------------

      def recheck_identity(id, expected)
        short_lock(id) do |fresh|
          if fresh.nil? then remote_orphan
          elsif !row_identity_matches?(fresh, expected) then collision
          else fresh
          end
        end
      end

      def recheck_snapshot(id, snapshot)
        short_lock(id) do |fresh|
          if fresh.nil? then remote_orphan
          elsif identity_snapshot(fresh) != snapshot then collision
          else fresh
          end
        end
      end

      # A short SELECT ... FOR UPDATE; the block's value is returned. No network
      # or libvips work runs inside — LockGuard enforces that for every caller.
      def short_lock(id)
        Migration::MediaTransfer::LockGuard.hold do
          ActiveStorage::Blob.transaction do
            yield ActiveStorage::Blob.lock.find_by(id:)
          end
        end
      end

      # --- shared -------------------------------------------------------

      def identity_snapshot(blob)
        { key: blob.key, checksum: blob.checksum, byte_size: blob.byte_size,
          content_type: blob.content_type, service_name: blob.service_name }
      end

      def row_identity_matches?(blob, expected)
        blob.key.present? &&
          blob.service_name.to_s == expected[:dest_service] &&
          blob.checksum.to_s == expected[:md5] &&
          blob.byte_size.to_i == expected[:byte_size] &&
          blob.content_type.to_s == expected[:content_type] # EXACT canonical type, not "allowed"
      end

      # Bounded remote re-read; returns nil on success or a fail-closed Result.
      # The type-detection + structural re-verification body is media-kind aware
      # (image decode vs. ISO-BMFF container re-validation); the bounded read,
      # size/checksum re-check, exact-canonical-type match, LockGuard fences and
      # fail-closed semantics are unchanged across kinds.
      def verify_remote!(blob, expected, service, media_kind, image_processor)
        bytes = Migration::MediaTransfer.bounded_download(service, blob.key, expected[:byte_size])
        return collision unless bytes.bytesize == expected[:byte_size]
        return collision unless Digest::MD5.base64digest(bytes) == expected[:md5]

        detected = media_kind.detect_type(bytes)
        return collision unless detected == expected[:content_type] # EXACT canonical type

        begin
          Migration::MediaTransfer::LockGuard.assert_free!("media_kind.remote_reverify!")
          media_kind.remote_reverify!(bytes, image_processor:)
        rescue Migration::MediaTransfer::MediaKind::StructuralError
          return collision
        end

        nil
      rescue Migration::MediaTransfer::DestinationTooLarge
        collision
      rescue ActiveStorage::FileNotFoundError, Errno::ENOENT
        remote_orphan
      end

      def remote_orphan
        Migration::MediaTransfer::Result.failed(:binding_conflict, "remote_orphan")
      end

      def collision
        Migration::MediaTransfer::Result.failed(:binding_conflict, "destination_collision")
      end
    end
  end
end
