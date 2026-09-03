# frozen_string_literal: true

require "openssl"
require "json"
require "digest"
require "fileutils"

module Date9ja
  module Snapshot
    # Deterministic synthetic media corpus for the Date9ja profile-photo Pass 2
    # L2 rehearsal (MEDIA-TRANSFER.md §21 L2).
    #
    #   raw production backup
    #     -> date9ja_snapshot_sanitized                (operator, PII-stripped)
    #     -> date9ja_snapshot_sanitized_media_v2        (TEMPLATE copy of the above)
    #     -> synthetic media corpus  (THIS module: bytes + manifest, patches
    #        media_v2 blob byte_size/checksum to match)
    #     -> Date9ja::Storage::LocalCorpusReader        (rehearsal transport)
    #     -> Pass 2
    #
    # The corpus contains NO original Date9ja media bytes. Every object is a
    # freshly encoded image whose pixels are an AES-CTR keystream keyed only by
    # (generator version, seed, source_blob_id, canonical_content_type) — so the
    # generator is a total, reproducible function and the verifier can prove each
    # stored file by re-rendering it.
    #
    # Structural identity from the parent artifact is preserved exactly: source
    # photo / attachment / blob / owner ids, moderation, primary state, ordering,
    # storage key, service_name and canonical content_type are never changed.
    # Only `byte_size` and `checksum` on the 279 Photo image blobs are rewritten
    # to describe the synthetic bytes.
    module SyntheticMedia
      GENERATOR_VERSION = "date9ja-synthetic-media-v1"
      DEFAULT_SEED = "date9ja-media-v2-2026-09-03"

      PARENT_ARTIFACT = "date9ja_snapshot_sanitized"
      ARTIFACT_NAME = "date9ja_snapshot_sanitized_media_v2"

      # ext by canonical content type. libvips selects the encoder from this.
      FORMATS = { "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp" }.freeze

      MIN_DIMENSION = 96
      MAX_DIMENSION = 1_400 # a slice above Media::ImageProcessor::DISPLAY_MAX_DIMENSION (1600) is fine
      # Same ceiling the real transport enforces (Migration::MediaTransfer::BYTE_CEILING).
      BYTE_CEILING = 8 * 1024 * 1024

      PHOTO_RECORD_TYPE = "Photo"
      PHOTO_ATTACHMENT_NAME = "image"

      module_function

      # Deterministic image bytes for one source blob.
      def render(source_blob_id:, canonical_content_type:, seed: DEFAULT_SEED)
        ext = FORMATS.fetch(canonical_content_type) do
          raise ArgumentError, "unsupported canonical content type"
        end
        material = "#{GENERATOR_VERSION}|#{seed}|#{source_blob_id}|#{canonical_content_type}"
        digest = Digest::SHA256.digest(material)
        state = digest.unpack1("Q>")

        width  = MIN_DIMENSION + (state % (MAX_DIMENSION - MIN_DIMENSION))
        height = MIN_DIMENSION + ((state >> 20) % (MAX_DIMENSION - MIN_DIMENSION))

        pixels = keystream(width * height * 3, material)
        image = Vips::Image.new_from_memory(pixels, width, height, 3, :uchar)
          .copy(interpretation: :srgb)

        # A deterministic low-pass pass varies the high-frequency content (and so
        # the encoded size / processing cost) across the corpus.
        blur = 0.3 + ((state >> 8) % 25) / 10.0
        image = image.gaussblur(blur)

        opts =
          case canonical_content_type
          when "image/jpeg" then { Q: 55 + (state % 35) }
          when "image/webp" then { Q: 50 + ((state >> 4) % 40) }
          else {}
          end
        bytes = image.write_to_buffer(ext, **opts).b
        raise "synthetic object exceeds the byte ceiling" if bytes.bytesize > BYTE_CEILING

        bytes
      end

      # Fast, deterministic, high-entropy byte stream (AES-256-CTR keystream).
      def keystream(length, material)
        cipher = OpenSSL::Cipher.new("aes-256-ctr")
        cipher.encrypt
        cipher.key = Digest::SHA256.digest("key|#{material}")
        cipher.iv = Digest::SHA256.digest("iv|#{material}")[0, 16]
        (cipher.update("\x00".b * length) + cipher.final).byteslice(0, length)
      end

      def deterministic_identity(source_blob_id, canonical_content_type, seed)
        Digest::SHA256.hexdigest(
          "#{GENERATOR_VERSION}|#{seed}|#{source_blob_id}|#{canonical_content_type}"
        )
      end
    end
  end
end
