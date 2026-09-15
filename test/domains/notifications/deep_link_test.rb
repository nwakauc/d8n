require "test_helper"

module Notifications
  class DeepLinkTest < ActiveSupport::TestCase
    test "Date9ja links use its explicit application URL" do
      brand = Brand.new(slug: "date9ja", name: "Date9ja")
      previous = ENV["D8N_DATE9JA_APP_URL"]
      ENV["D8N_DATE9JA_APP_URL"] = "https://www.date9ja.love"

      assert_equal "https://www.date9ja.love/matches/42", DeepLink.for(brand:, path: "/matches/42")
    ensure
      previous.nil? ? ENV.delete("D8N_DATE9JA_APP_URL") : ENV["D8N_DATE9JA_APP_URL"] = previous
    end
  end
end
