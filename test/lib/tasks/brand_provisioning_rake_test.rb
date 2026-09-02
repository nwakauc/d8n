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

  test "provisions date9ja via the generic command" do
    ENV["HOSTS"] = "date9ja.test"

    assert_difference -> { Brand.count }, 1 do
      Rake::Task["brands:provision"].invoke("date9ja")
    end

    brand = Brand.kept.find_by!(slug: "date9ja")
    assert_equal brand, BrandDomain.kept.find_by!(host: "date9ja.test").brand
  end

  test "install_date9ja maps DATE9JA_API_HOST idempotently" do
    ENV["DATE9JA_API_HOST"] = "date9ja-api.test"
    Rake::Task["brands:install_date9ja"].reenable

    assert_difference -> { Brand.count }, 1 do
      Rake::Task["brands:install_date9ja"].invoke
    end
    Rake::Task["brands:install_date9ja"].reenable

    assert_no_difference [ -> { Brand.count }, -> { BrandDomain.count } ] do
      Rake::Task["brands:install_date9ja"].invoke
    end

    assert_equal "date9ja", BrandDomain.kept.find_by!(host: "date9ja-api.test").brand.slug
  ensure
    ENV.delete("DATE9JA_API_HOST")
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
