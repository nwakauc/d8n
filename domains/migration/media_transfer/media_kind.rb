# frozen_string_literal: true

module Migration
  module MediaTransfer
    # ADR 0029 — the small injected strategy that lets the ONE proven transfer
    # spine (locking, canonical identity, AdoptOrUpload state machine,
    # deterministic recovery, ReferenceMap semantics) serve more than one media
    # kind. A MediaKind parameterizes ONLY genuinely media-specific behaviour:
    #
    #   - accepted canonical content types
    #   - canonical extension for a type (delegated to CanonicalKey::EXTENSIONS)
    #   - byte ceiling
    #   - magic-byte / container type detection
    #   - structural / container validation (Phase A, full)
    #   - remote re-verification body (every destination reuse path)
    #
    # It NEVER touches locking, canonical identity structure, VERSION, the
    # AdoptOrUpload cases, deterministic recovery, ReferenceMap, or concurrency.
    #
    # `MediaKind::Image` reproduces the pre-0029 Profile Photo behaviour
    # byte-for-byte and is the default everywhere, so existing callers are
    # unchanged.
    module MediaKind
      # Media facts a kind can establish from the verified source bytes in
      # Phase A. `duration_seconds` is authoritative playable duration for video
      # (a structural acceptance property, ADR 0029 "Duration"); nil for image.
      Facts = Data.define(:duration_seconds, :codec, :container) do
        def self.empty = new(duration_seconds: nil, codec: nil, container: nil)
      end

      # A structural / container / duration-derivation failure. Carries the
      # exact fail-closed disposition + stable reason code the transfer must
      # surface — image malformed and video duration_unreadable are NOT the same
      # disposition.
      class StructuralError < StandardError
        attr_reader :disposition, :reason

        def initialize(disposition, reason)
          @disposition = disposition
          @reason = reason
          super("#{disposition}:#{reason}")
        end
      end

      # ---- MediaKind::Image — pre-0029 Profile Photo behaviour, unchanged ----

      module Image
        CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
        BYTE_CEILING = 8.megabytes

        module_function

        def key = :image
        def content_types = CONTENT_TYPES
        def byte_ceiling = BYTE_CEILING
        # Unchanged accepted Profile Photo reason code (ADR 0028 regression fence).
        def not_recognized_reason = "not_an_image"

        # The existing authority: JPEG / PNG / WebP magic bytes over the head.
        def detect_type(bytes)
          Profiles::PhotoUpload.detect_image_type(bytes.to_s.b[0, 16])
        end

        # Full decode-safety probe (libvips header + decode). The real safety gate.
        def structural_verify!(bytes, image_processor: Media::ImageProcessor)
          image_processor.call(bytes)
          Facts.empty
        rescue Media::ImageProcessor::Error
          raise StructuralError.new(:validation_failed, "malformed_image")
        end

        # Remote re-verification body for a destination reuse path: same image
        # decode. Returns nil on success, raises StructuralError on failure.
        def remote_reverify!(bytes, image_processor: Media::ImageProcessor)
          image_processor.call(bytes)
          nil
        rescue Media::ImageProcessor::Error
          raise StructuralError.new(:binding_conflict, "destination_collision")
        end
      end

      # ---- MediaKind::Video — Date9ja Profile Video (ADR 0029) --------------

      module Video
        CONTENT_TYPES = ProfileVideo::ALLOWED_CONTENT_TYPES # video/mp4, video/quicktime
        # ADR 0029: video byte ceiling is the brand VideoPolicy max byte size;
        # the generic default is the same DEFAULT_MAX_BYTE_SIZE the policy uses.
        BYTE_CEILING = Media::VideoPolicy::DEFAULT_MAX_BYTE_SIZE
        # ISO-BMFF brands that actually mean "this file IS an MP4" (QuickTime's
        # "qt  " is MP4-compatible but is NOT MP4 — it maps to video/quicktime).
        MP4_BRANDS = (Media::VideoContainerValidator::ACCEPTED_BRANDS - [ "qt  " ]).freeze

        module_function

        def key = :video
        def content_types = CONTENT_TYPES
        def byte_ceiling = BYTE_CEILING
        def not_recognized_reason = "not_a_video"

        # ISO-BMFF `ftyp` sniff — the structural analogue of image magic bytes.
        # Never trusts the declared type; a spoofed extension cannot pass.
        def detect_type(bytes)
          b = bytes.to_s.b
          return nil if b.bytesize < 16

          size = b[0, 4].unpack1("N").to_i
          return nil unless b[4, 4] == "ftyp"

          size = b.bytesize if size.zero?
          return nil if size < 16 || size > b.bytesize

          major = b[8, 4]
          compatible = b[16, size - 16].to_s.scan(/.{4}/m)
          brands = [ major ] + compatible
          return "video/quicktime" if brands.include?("qt  ")
          return "video/mp4" if brands.any? { |brand| MP4_BRANDS.include?(brand) }

          nil
        end

        # Phase A structural validation for video (ADR 0029 "Duration"):
        #   ISO-BMFF box-tree walk + codec gate  (Media::VideoContainerValidator)
        #   -> authoritative duration             (ffprobe: Media::VideoProcessor.probe)
        #        unreadable / <= 0  -> FAIL CLOSED quarantined / duration_unreadable
        # The brand duration LIMIT check is a separate Phase-A gate supplied by
        # the orchestrator (it needs brand knowledge, which a MediaKind must not
        # have). This method derives the duration; the gate enforces the policy.
        def structural_verify!(bytes, image_processor: nil) # rubocop:disable Lint/UnusedMethodArgument
          container = validate_container!(bytes)
          probe = probe!(bytes)

          duration = probe.duration_seconds
          if duration.nil? || duration <= 0
            raise StructuralError.new(:quarantined, "duration_unreadable")
          end

          Facts.new(duration_seconds: duration, codec: container.codec, container: probe.major_brand)
        end

        # Remote re-verification body: container re-validation only (no ffprobe
        # on every reuse — duration was authoritatively established in Phase A
        # and the deterministic key is byte-identity-bound).
        def remote_reverify!(bytes, image_processor: nil) # rubocop:disable Lint/UnusedMethodArgument
          validate_container!(bytes)
          nil
        end

        def validate_container!(bytes)
          Media::VideoContainerValidator.call(bytes)
        rescue Media::VideoContainerValidator::Error
          raise StructuralError.new(:validation_failed, "malformed_container")
        end
        private_class_method :validate_container!

        def probe!(bytes)
          Media::VideoProcessor.probe(bytes)
        rescue Media::VideoProcessor::TimedOut, Media::VideoProcessor::Error
          raise StructuralError.new(:quarantined, "duration_unreadable")
        end
        private_class_method :probe!
      end

      # Default: existing image callers are unchanged.
      DEFAULT = Image
    end
  end
end
