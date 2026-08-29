require "test_helper"
require "rake"

class BrandProvisioningRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("brands:provision")
    Rake::Task["brands:provision"].reenable
  end

  teardown do
    ENV.delete("HOSTS")
  end

  test "provisions hookus via the generic command" do
    ENV["HOSTS"] = "hookus.test"

    assert_difference -> { Brand.count }, 1 do
      Rake::Task["brands:provision"].invoke("hookus")
    end

    brand = Brand.kept.find_by!(slug: "hookus")
    assert_equal brand, BrandDomain.kept.find_by!(host: "hookus.test").brand
  end

  test "provisions dateza via the generic command" do
    ENV["HOSTS"] = "dateza.test"

    assert_difference -> { Brand.count }, 1 do
      Rake::Task["brands:provision"].invoke("dateza")
    end

    brand = Brand.kept.find_by!(slug: "dateza")
    assert_equal brand, BrandDomain.kept.find_by!(host: "dateza.test").brand
  end

  test "rerunning the generic command is safe" do
    ENV["HOSTS"] = "hookus.test"
    Rake::Task["brands:provision"].invoke("hookus")
    Rake::Task["brands:provision"].reenable

    assert_no_difference [ -> { Brand.count }, -> { BrandDomain.count } ] do
      Rake::Task["brands:provision"].invoke("hookus")
    end
  end
end
