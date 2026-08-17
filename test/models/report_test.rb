require "test_helper"

class ReportTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @reporter = create_profile(@brand)
    @reported = create_profile(@brand)
  end

  test "allows one open report per pair and permits a fresh one after resolution" do
    first = Report.create!(brand: @brand, reporter_profile: @reporter, reported_profile: @reported, reason: :spam)
    assert_not Report.new(brand: @brand, reporter_profile: @reporter, reported_profile: @reported, reason: :harassment).valid?

    first.update!(status: :dismissed)
    replacement = Report.create!(brand: @brand, reporter_profile: @reporter, reported_profile: @reported, reason: :harassment)

    assert_not_equal first.id, replacement.id
    assert_equal 1, Report.open_reports.where(brand: @brand).count
  end

  test "rejects an over-long note" do
    report = Report.new(brand: @brand, reporter_profile: @reporter, reported_profile: @reported,
      reason: :other, note: "x" * 2_001)
    assert_not report.valid?
    assert_includes report.errors[:note].join, "too long"
  end

  test "database rejects self reports" do
    assert_raises ActiveRecord::StatementInvalid do
      Report.insert_all!([ attributes_for(@brand, @reporter, @reporter) ])
    end
  end

  test "database rejects a reported profile from another brand" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_profile = create_profile(other_brand)

    assert_raises ActiveRecord::InvalidForeignKey do
      Report.insert_all!([ attributes_for(@brand, @reporter, other_profile) ])
    end
  end

  private

  def create_profile(brand)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end

  def attributes_for(brand, reporter, reported)
    {
      brand_id: brand.id,
      reporter_profile_id: reporter.id,
      reported_profile_id: reported.id,
      reason: Report.reasons.fetch("spam"),
      status: Report.statuses.fetch("open"),
      created_at: Time.current,
      updated_at: Time.current
    }
  end
end
