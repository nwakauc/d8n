require "test_helper"

module D8n
  module Platform
    class CatalogTest < ActiveSupport::TestCase
      EXPECTED_NAMESPACES = %w[
        admin ai chat discovery id insights match media notify pay profile trust verify
      ].freeze

      test "catalogues every canonical D8N capability namespace" do
        namespaces = Catalog.definitions.map { |definition| definition.key.namespace }.uniq.sort

        assert_equal EXPECTED_NAMESPACES, namespaces
        assert Catalog.validate!(brand_slugs: BrandRegistry.slugs)
      end

      test "keeps definitions unique and dependencies resolvable" do
        keys = Catalog.definitions.map { |definition| definition.key.to_s }

        assert_equal keys.uniq, keys
        Catalog.definitions.each do |definition|
          definition.dependencies.each { |dependency| assert Catalog.key?(dependency) }
        end
      end

      test "available and partial definitions reference real implementation constants" do
        implemented = Catalog.definitions.reject(&:planned?)

        implemented.each do |definition|
          definition.implementations.each do |implementation|
            assert implementation.safe_constantize,
              "#{definition.key} references missing implementation #{implementation}"
          end
        end
      end

      test "does not present planned platform pillars as implemented" do
        %w[
          pay.plan
          pay.entitlement
          pay.subscription
          pay.payment
          ai.matchmaker
          insights.marketplace_health
          verify.identity.selfie
          chat.realtime
          chat.voice
          chat.video
        ].each do |key|
          assert_predicate Catalog.fetch(key), :planned?, key
        end
      end


      test "records stable daily selection as an available platform capability" do
        definition = Catalog.fetch("discovery.surface.daily_batch")

        assert_predicate definition, :available?
        assert_includes definition.implementations, "Matching::StableDailySelection"
      end

      test "records persistent browser sessions as an available D8N ID capability" do
        definition = Catalog.fetch("id.session.browser_persistence")

        assert_predicate definition, :available?
        assert_includes definition.dependencies, D8n::Platform::CapabilityKey.new("id.session.current")
        assert_includes definition.implementations, "Identity::BrowserSession"
      end

      test "records remaining architectural drift as partial instead of available" do
        assert_predicate Catalog.fetch("media.profile_photo.moderation"), :partial?
      end

      test "records brand-authoritative scalar fields as available" do
        assert_predicate Catalog.fetch("profile.scalar_fields"), :available?
      end

      test "records remediated configured facets and decorations as available" do
        assert_predicate Catalog.fetch("discovery.facet.option_group"), :available?
        assert_predicate Catalog.fetch("discovery.decoration"), :available?
      end

      test "rejects unknown capability keys" do
        assert_raises(KeyError) { Catalog.fetch("pay.checkout") }
        assert_not Catalog.key?("hookus.discovery")
      end
    end
  end
end
