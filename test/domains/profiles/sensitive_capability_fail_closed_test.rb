require "test_helper"

module Profiles
  # Slice 5 — proves the central promise using the REAL newly-defined sensitive
  # capabilities (tribe, ethnicity), not synthetic fields:
  #
  #   D8N KNOWS the capability  ≠  a brand USES it  ≠  it is WRITABLE  ≠
  #   it is PUBLIC  ≠  it is completion-requirable  ≠  it participates in
  #   discovery/matching.
  #
  # tribe/ethnicity are `storage: :pending` + `sensitivity: :sensitive_identity`
  # and enabled by NO brand.
  class SensitiveCapabilityFailClosedTest < ActiveSupport::TestCase
    SENSITIVE = %w[tribe ethnicity].freeze

    BRAND_REQUIREMENTS = {
      "hookus" => HookusProfileCatalog::REQUIREMENTS,
      "dateza" => DatezaProfileCatalog::REQUIREMENTS,
      "date9ja" => Date9jaProfileCatalog::REQUIREMENTS
    }.freeze

    # 1 — the canonical capability is known.
    test "FieldCatalog knows tribe and ethnicity as canonical capabilities" do
      SENSITIVE.each do |key|
        assert FieldCatalog.defined?(key)
        assert FieldCatalog.fetch(key).sensitive_identity?
      end
    end

    # religion is NOT duplicated as a scalar — it stays a CapabilityCatalog group.
    test "religion is not redefined as a scalar FieldCatalog field" do
      refute FieldCatalog.defined?("religion")
      assert CapabilityCatalog::OPTION_CAPABILITIES.key?("religion")
    end

    # 2 — no real brand auto-enables it.
    test "no production brand config enables a sensitive capability" do
      BRAND_REQUIREMENTS.each do |slug, requirements|
        brand = Brand.new(slug:, name: slug, profile_requirements: requirements)
        policy = FieldPolicy.new(brand:)
        SENSITIVE.each do |key|
          refute_includes policy.enabled_profile_fields, key, "#{slug} enabled #{key}"
          refute policy.profile_enabled?(key), "#{slug} profile_enabled? #{key}"
          refute policy.public_profile_enabled?(key), "#{slug} public #{key}"
        end
      end
    end

    # 3/4/5 — Date9ja, DateZA and HookUs (broad default contract) all reject a
    # write of a sensitive capability, and a brand cannot even declare it enabled.
    test "every brand rejects a sensitive-capability write and cannot enable it" do
      BRAND_REQUIREMENTS.each do |slug, requirements|
        brand = Brand.new(slug:, name: slug, profile_requirements: requirements)
        policy = FieldPolicy.new(brand:)

        SENSITIVE.each do |key|
          error = assert_raises(FieldPolicy::UnsupportedFields, "#{slug} allowed #{key}") do
            policy.validate_profile_write!([ "display_name", key ])
          end
          assert_includes error.fields, key
        end

        hostile = brand.dup
        hostile.profile_requirements = requirements.merge(
          "enabled_profile_fields" => Array(requirements["enabled_profile_fields"]) + SENSITIVE
        )
        refute hostile.valid?, "#{slug} accepted a sensitive enabled field"
        assert_includes hostile.errors[:profile_requirements], "contains unsupported enabled profile fields"
      end
    end

    VALID_REQUIREMENTS = {
      "profile_fields" => %w[display_name], "enabled_profile_fields" => %w[display_name bio],
      "identity_fields" => %w[first_name], "enabled_identity_fields" => %w[first_name],
      "preference_fields" => [], "collections" => %w[photos], "option_groups" => []
    }.freeze

    # 6/7/8 — never serialized, even under a hostile (in-memory) config.
    test "sensitive capabilities never appear in any serializer" do
      brand = Brand.create!(slug: "sensfc", name: "SensFC", profile_requirements: VALID_REQUIREMENTS)
      # A config that would be rejected on save, forced in memory.
      brand.profile_requirements = VALID_REQUIREMENTS.merge(
        "enabled_profile_fields" => %w[display_name bio] + SENSITIVE
      )
      user = User.create!(first_name: "Ada")
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: membership,
        display_name: "Ada", bio: "hi", birthdate: 25.years.ago.to_date, gender: "woman",
        status: :active, visibility: :visible)
      viewer_user = User.create!
      viewer = Profile.create!(brand:, user: viewer_user,
        brand_membership: BrandMembership.create!(brand:, user: viewer_user),
        display_name: "Ben", birthdate: 30.years.ago.to_date, gender: "man",
        status: :active, visibility: :visible)

      owner = OwnerSerializer.call(profile:)
      public_payload = PublicSerializer.call(profile:)
      detail = DetailSerializer.call(profile:, viewer:)

      SENSITIVE.each do |key|
        refute owner.key?(key.to_sym), "owner leaked #{key}"
        refute public_payload.key?(key.to_sym), "public leaked #{key}"
        refute detail.key?(key.to_sym), "detail leaked #{key}"
      end
      assert_equal "Ada", owner[:display_name]
    end

    # 9 — cannot be completion_requirable while sensitive/pending.
    test "sensitive capabilities are never completion_requirable" do
      SENSITIVE.each { |key| refute FieldCatalog.fetch(key).completion_requirable? }
      refute_includes FieldCatalog.completion_requirable_keys(:profile), "tribe"
      refute_includes FieldCatalog.completion_requirable_keys(:profile), "ethnicity"

      brand = Brand.new(slug: "x", name: "X",
        profile_requirements: { "profile_fields" => %w[display_name tribe] })
      refute brand.valid?
      assert_includes brand.errors[:profile_requirements], "contains unsupported profile fields"
    end

    # 10 — storage:pending stays non-enable-able.
    test "storage:pending capability is not enable-able" do
      SENSITIVE.each do |key|
        assert FieldCatalog.fetch(key).pending_storage?
        refute FieldCatalog.enableable?(key)
        refute_includes FieldCatalog.enableable_keys_for_group(:profile), key
      end
    end

    # 11 — the configuration API never advertises it.
    test "GET /profile configuration never advertises a sensitive capability" do
      brand = Brand.create!(slug: "senscfg", name: "SensCfg", profile_requirements: VALID_REQUIREMENTS)
      brand.profile_requirements = VALID_REQUIREMENTS.merge(
        "enabled_profile_fields" => %w[display_name bio] + SENSITIVE
      )
      payload = Configuration.call(brand:)
      advertised = payload.fetch(:profile_fields).map { |f| f[:key] }
      SENSITIVE.each { |key| refute_includes advertised, key }
    end

    # importer sensitive firewall unaffected.
    test "Date9ja import sensitive denylist still covers the new capabilities" do
      denylist = Date9ja::Import::FieldMapping::SENSITIVE_DENYLIST
      assert_includes denylist, "tribe"
      assert_includes denylist, "ethnicity"
      assert_empty denylist & Date9ja::Import::FieldMapping::PROFILE_SOURCE_COLUMNS
      # Nothing newly defined became an importable canonical field.
      assert_empty FieldCatalog.enableable_keys_for_group(:profile) & SENSITIVE
    end
  end
end
