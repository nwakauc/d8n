require "test_helper"
require "stringio"

module LoadTesting
  class SyntheticDatasetTest < ActiveJob::TestCase
    test "production requires the staging target and action-specific confirmation" do
      create_dataset = dataset(environment: "production", env: {})

      error = assert_raises(SyntheticDataset::SafetyError) { create_dataset.create! }
      assert_includes error.message, SyntheticDataset::CREATE_CONFIRMATION

      cleanup_dataset = dataset(
        environment: "production",
        env: {
          "D8N_LOAD_TEST_TARGET" => SyntheticDataset::STAGING_HOST,
          "D8N_LOAD_TEST_CONFIRM" => SyntheticDataset::CREATE_CONFIRMATION
        }
      )
      error = assert_raises(SyntheticDataset::SafetyError) { cleanup_dataset.cleanup! }
      assert_includes error.message, SyntheticDataset::CLEANUP_CONFIRMATION
    end

    test "creates identifiable authenticatable records and cleans only the synthetic dataset" do
      brand = create_brand
      normal_user = User.create!
      lookalike = normal_user.identity_identifiers.create!(
        kind: :email,
        normalized_value: "loadtest-user-999999@example.invalid",
        metadata: {}
      )
      generator = dataset(brand:, count: 40)

      assert_no_enqueued_jobs do
        result = generator.create!

        assert_equal 40, result.users
        assert_equal 40, result.profiles
        assert_equal 40, result.brand_memberships
        assert_operator result.locations, :>, 0
        assert_operator result.likes, :>, 0
        assert_operator result.passes, :>, 0
        assert_operator result.matches, :>, 0
      end

      credential = IdentityIdentifier.find_by!(normalized_value: "loadtest-user-000001@example.invalid")
        .credentials.password.kept.sole
      assert Identity::PasswordEngine.matches?(credential:, password: "synthetic-secret")
      assert_equal 40, SyntheticDataset.synthetic_identifiers.count

      result = generator.cleanup!

      assert_equal 0, result.users
      assert_equal 0, result.profiles
      assert_predicate normal_user.reload, :persisted?
      assert_predicate lookalike.reload, :persisted?
    end

    test "provisions the canonical HookUs configuration but cleanup leaves it in place" do
      create_env = {
        "D8N_LOAD_TEST_TARGET" => SyntheticDataset::STAGING_HOST,
        "D8N_LOAD_TEST_CONFIRM" => SyntheticDataset::CREATE_CONFIRMATION
      }
      generator = dataset(brand_slug: "hookus", count: 2, environment: "production", env: create_env)

      result = generator.create!

      assert_equal 2, result.users
      brand = Brand.kept.find_by!(slug: "hookus")
      assert_equal %w[email_password phone_password], brand.auth_methods.sort
      assert_equal %w[intents vibes], brand.profile_option_groups.kept.status_active.order(:key).pluck(:key)
      assert_equal brand, BrandDomain.kept.active.find_by!(host: SyntheticDataset::STAGING_HOST).brand

      cleanup_env = create_env.merge("D8N_LOAD_TEST_CONFIRM" => SyntheticDataset::CLEANUP_CONFIRMATION)
      dataset(brand:, count: 2, environment: "production", env: cleanup_env).cleanup!

      assert_predicate brand.reload, :persisted?
      assert_equal 0, SyntheticDataset.synthetic_identifiers.count
    end

    private

    def create_brand
      brand = Brand.create!(
        slug: "load-test-#{SecureRandom.hex(6)}",
        name: "Load Test HookUs",
        auth_methods: %w[email_password]
      )
      Profiles::HookusProfileCatalog.install!(brand:)
      brand
    end

    def dataset(brand: nil, brand_slug: nil, count: 3, environment: "test", env: {})
      SyntheticDataset.new(
        brand_slug: brand&.slug || brand_slug || "missing-test-brand",
        count:,
        password: "synthetic-secret",
        environment:,
        env:,
        output: StringIO.new
      )
    end
  end
end
