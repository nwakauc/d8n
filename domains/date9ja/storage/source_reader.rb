# frozen_string_literal: true

require "uri"
require "net/http"

module Date9ja
  module Storage
    # Read-only, host-allowlisted, fail-closed reader over the Date9ja source
    # Cloudflare R2 bucket (ADR 0028 §2 / MEDIA-TRANSFER.md §5, §5b).
    #
    # This turn does NOT configure or call real R2. The HTTP transport is
    # injected; production wiring supplies a signed-request transport, tests
    # supply an in-memory / local-file transport.
    #
    # Security contract (all enforced here):
    #   - the endpoint is CONSTRUCTED from the trusted account id only; a
    #     caller/DB/argument-supplied endpoint or host is rejected;
    #   - HTTPS only;
    #   - redirects are refused (a 3xx is an error, Location is never followed);
    #   - only HEAD and streamed GET exist — there is NO put/delete/copy method;
    #   - streamed downloads abort the moment the running byte count exceeds the
    #     caller's ceiling;
    #   - object keys are opaque S3 keys, never filesystem paths (absolute / ".."
    #     rejected);
    #   - transport exceptions are redacted — no bucket, key, signed URL, or
    #     checksum ever reaches a caller or a log.
    class SourceReader
      ALLOWED_HOST_SUFFIXES = %w[.r2.cloudflarestorage.com].freeze
      MAX_RETRIES = 3
      RETRY_BACKOFF = 0.5

      # Conservative grammar for the known Date9ja Active Storage keys: a flat
      # random token (`ActiveStorage::Blob.generate_unique_secure_token`, base36)
      # optionally with `/`-joined derivative segments. Deliberately narrow — no
      # attempt to sanitise arbitrary strings. Rejects control chars, `?`, `#`,
      # `\`, `%` (encoded traversal), whitespace, leading `/`, and `.`/`..`
      # segments.
      KEY_SEGMENT = /\A[A-Za-z0-9][A-Za-z0-9_=-]*\z/
      MAX_KEY_LENGTH = 512

      class Error < StandardError; end
      class EndpointRejected < Error; end
      class RedirectRefused < Error; end
      class ObjectUnavailable < Error; end
      class ByteCeilingExceeded < Error; end
      class InvalidKey < Error; end

      # @param account_id [String] trusted operator config (DATE9JA_SOURCE_R2_ACCOUNT_ID)
      # @param bucket [String] trusted operator config
      # @param transport [#head, #get_stream] injected; must not be built from a caller URL
      # @param rehearsal_host [String, nil] one explicit extra allowlisted host for L1/L2 doubles
      def initialize(account_id:, bucket:, transport:, rehearsal_host: nil)
        @bucket = bucket.to_s
        @transport = transport
        @rehearsal_host = rehearsal_host.to_s.presence

        raise EndpointRejected, "source account id is required" if account_id.to_s.strip.empty?
        raise EndpointRejected, "source bucket is required" if @bucket.empty?

        @endpoint = "https://#{account_id}.r2.cloudflarestorage.com"
        assert_endpoint_safe!(@endpoint)
      end

      # Explicitly reject a caller-supplied endpoint/URL/host: there is no
      # constructor parameter for one, and this guards against a future edit.
      def self.from_config(config)
        forbidden = config.keys.map(&:to_s) & %w[endpoint url host uri origin]
        raise EndpointRejected, "caller-supplied endpoint is not allowed" if forbidden.any?

        new(**config)
      end

      # @return [Hash] { byte_size: Integer } or nil when the object is absent.
      def head(key)
        object_key = validate_key!(key)
        with_retries do
          status, headers = @transport.head(object_url(object_key))
          refuse_redirect!(status)
          return nil if status == 404
          raise ObjectUnavailable, "source object unavailable" unless status == 200

          { byte_size: Integer(headers["content-length"] || headers["Content-Length"] || 0) }
        end
      end

      # Streams the object into `io`, aborting mid-stream past `byte_ceiling`.
      # @return [Integer] bytes written.
      def download(key, io:, byte_ceiling:, chunk_size: 5.megabytes)
        object_key = validate_key!(key)
        written = 0
        with_retries do
          io.truncate(0) if io.respond_to?(:truncate)
          io.rewind if io.respond_to?(:rewind)
          written = 0
          status = @transport.get_stream(object_url(object_key), chunk_size:) do |chunk|
            written += chunk.bytesize
            raise ByteCeilingExceeded, "source object exceeds the transfer ceiling" if written > byte_ceiling

            io.write(chunk)
          end
          refuse_redirect!(status)
          raise ObjectUnavailable, "source object unavailable" unless status == 200
        end
        io.flush if io.respond_to?(:flush)
        written
      end

      private

      def object_url(object_key)
        "#{@endpoint}/#{@bucket}/#{object_key}"
      end

      def validate_key!(key)
        value = key.to_s
        raise InvalidKey, "invalid source object key" if value.empty? || value.bytesize > MAX_KEY_LENGTH
        raise InvalidKey, "invalid source object key" if value.start_with?("/", ".")
        raise InvalidKey, "invalid source object key" if value.match?(/[\x00-\x1f\x7f]|[?#\\%\s]/)

        segments = value.split("/", -1)
        raise InvalidKey, "invalid source object key" if segments.any? { |s| s.empty? || s == ".." || s == "." }
        raise InvalidKey, "invalid source object key" unless segments.all? { |s| s.match?(KEY_SEGMENT) }

        value
      end

      def assert_endpoint_safe!(endpoint)
        uri = URI.parse(endpoint)
        raise EndpointRejected, "source endpoint must be https" unless uri.scheme == "https"
        raise EndpointRejected, "source endpoint host is not allowlisted" unless host_allowlisted?(uri.host)
      rescue URI::InvalidURIError
        raise EndpointRejected, "source endpoint is invalid"
      end

      def host_allowlisted?(host)
        host = host.to_s
        return true if @rehearsal_host && host == @rehearsal_host

        ALLOWED_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }
      end

      def refuse_redirect!(status)
        raise RedirectRefused, "source responded with a redirect" if status.to_i.between?(300, 399)
      end

      def with_retries
        attempts = 0
        begin
          yield
        rescue ObjectUnavailable
          attempts += 1
          raise if attempts >= MAX_RETRIES

          sleep(RETRY_BACKOFF * attempts) unless Rails.env.test?
          retry
        rescue RedirectRefused, ByteCeilingExceeded, EndpointRejected, InvalidKey
          raise
        rescue StandardError
          # Redact any provider/transport exception detail.
          attempts += 1
          raise ObjectUnavailable, "source object unavailable" if attempts >= MAX_RETRIES

          sleep(RETRY_BACKOFF * attempts) unless Rails.env.test?
          retry
        end
      end
    end
  end
end
