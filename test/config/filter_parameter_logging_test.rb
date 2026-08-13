require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  test "filters OTP verification code parameters" do
    filtered = Rails.application.config.filter_parameters
    filter = ActiveSupport::ParameterFilter.new(filtered)

    params = filter.filter(phone: "+27 82 123 4567", code: "123456")

    assert_equal "[FILTERED]", params[:code]
    assert_equal "[FILTERED]", params[:phone]
  end

  test "filters precise location parameters" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    params = filter.filter(latitude: "-33.9248685", longitude: "18.4240553", accuracy_meters: 25)

    assert_equal "[FILTERED]", params[:latitude]
    assert_equal "[FILTERED]", params[:longitude]
    assert_equal 25, params[:accuracy_meters]
  end
end
