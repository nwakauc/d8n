require "net/http"
require "json"
require "uri"

module Notifications
  # Minimal, dependency-free HTTP client for outbound provider calls (Resend,
  # Twilio). Deliberately not a vendor SDK: it keeps provider HTTP in one testable
  # seam that gateways can stub, and avoids adding a networking gem to the platform.
  #
  # Network-level failures (timeouts, connection resets, TLS errors) are raised as
  # TransientError so a gateway can classify the attempt as retryable. HTTP
  # responses (any status) are returned intact so the gateway — which knows the
  # vendor's status semantics — decides success/transient/permanent.
  class HttpClient
    class TransientError < StandardError; end

    Response = Data.define(:status, :body) do
      def success? = status.between?(200, 299)

      # Data instances are frozen, so this parses on each call rather than memoizing;
      # gateways call it at most a couple of times per response.
      def json
        JSON.parse(body)
      rescue JSON::ParserError
        {}
      end
    end

    DEFAULT_TIMEOUT = 8

    def self.post_form(url, headers: {}, form: {}, timeout: DEFAULT_TIMEOUT)
      post(url, headers:, timeout:, body: URI.encode_www_form(form),
        content_type: "application/x-www-form-urlencoded")
    end

    def self.post_json(url, headers: {}, payload: {}, timeout: DEFAULT_TIMEOUT)
      post(url, headers:, timeout:, body: JSON.generate(payload), content_type: "application/json")
    end

    def self.post(url, headers:, body:, content_type:, timeout:)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = content_type
      headers.each { |key, value| request[key] = value }
      request.body = body

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: timeout, read_timeout: timeout) do |http|
        http.request(request)
      end

      Response.new(status: response.code.to_i, body: response.body.to_s)
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
           SocketError, EOFError, IOError, OpenSSL::SSL::SSLError => e
      raise TransientError, e.class.name
    end
    private_class_method :post
  end
end
