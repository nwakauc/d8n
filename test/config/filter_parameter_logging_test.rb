require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  test "filters OTP verification code parameters" do
    filtered = Rails.application.config.filter_parameters
    filter = ActiveSupport::ParameterFilter.new(filtered)

    params = filter.filter(phone: "+27 82 123 4567", code: "123456")

    assert_equal "[FILTERED]", params[:code]
    assert_equal "+27 82 123 4567", params[:phone]
  end
end
