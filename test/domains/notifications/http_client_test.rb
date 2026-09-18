require "test_helper"

class NotificationsHttpClientTest < ActiveSupport::TestCase
  test "unreachable network is classified transient without leaking payload" do
    stub_method(Net::HTTP, :start, ->(*) { raise Errno::ENETUNREACH, "private provider payload" }) do
      error = assert_raises(Notifications::HttpClient::TransientError) do
        Notifications::HttpClient.post_json("https://provider.example", payload: { code: "private" })
      end
      assert_equal "Errno::ENETUNREACH", error.message
      assert_not_includes error.message, "private"
    end
  end
end
