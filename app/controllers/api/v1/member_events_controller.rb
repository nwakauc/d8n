class Api::V1::MemberEventsController < ApplicationController
  include ActionController::Live
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:member_events_connection, installation_id: native_installation_id) }, only: :index
  before_action :authorize_stream_origin!, only: :index

  def index
    ids = { session_id: Current.session.id, brand_id: Current.brand.id, user_id: Current.user.id }
    channel = Realtime::MemberEvents.stream_name(brand_id: ids[:brand_id], user_id: ids[:user_id])
    queue = SizedQueue.new(100)
    callback = ->(payload) { queue.push(payload, true) rescue ThreadError }
    adapter = ActionCable.server.pubsub
    ready = Queue.new
    adapter.subscribe(channel, callback, -> { ready.push(true) })
    Rails.logger.info("member_realtime_connected")
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Accel-Buffering"] = "no"
    # Subscribe before telling the browser to fetch its snapshot, closing the
    # snapshot/subscription race. Missing/replayed events never drive counters.
    raise IOError unless ready.pop(timeout: 5)
    response.stream.write("retry: 3000\nevent: ready\ndata: {}\n\n")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 240
    loop do
      break unless Realtime::MemberEvents.session_active?(**ids)
      ActiveRecord::Base.connection_handler.clear_active_connections!
      payload = queue.pop(timeout: 15)
      break unless Realtime::MemberEvents.session_active?(**ids)
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      if payload
        next unless Realtime::MemberEvents.authorized_payload?(payload:, **ids)

        response.stream.write("event: member\ndata: #{payload}\n\n")
      else
        # Also reconciles other-device reads and ephemeral delivery outages.
        response.stream.write("event: reconcile\ndata: {}\n\n")
      end
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # Browser closed the stream; no state is changed.
  ensure
    Rails.logger.info("member_realtime_disconnected") if callback
    adapter&.unsubscribe(channel, callback) if callback
    response.stream.close
  end

  private

  def authorize_stream_origin!
    return if Current.authentication_source == :cookie && Identity::BrowserSession.origin_allowed?(request:)
    return if Current.authentication_source == :bearer && native_client_request?

    Rails.logger.warn("member_realtime_origin_rejected")
    error = Current.authentication_source == :bearer ? "native_client_headers_required" : "browser_session_origin_not_allowed"
    render json: { error: }, status: :forbidden
  end

  def native_client_request?
    request.headers["X-D8N-Client"].to_s.casecmp("native").zero? &&
      native_installation_id.present? && native_installation_id.bytesize <= 128 &&
      request.headers["Origin"].blank? &&
      request.headers["Sec-Fetch-Site"].to_s != "cross-site"
  end

  def native_installation_id
    request.headers["X-D8N-Installation-ID"].to_s.presence
  end
end
