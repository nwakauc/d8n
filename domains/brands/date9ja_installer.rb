module Brands
  # Idempotently provisions Date9ja's first-class D8N tenant foundation. Mirrors
  # Brands::DatezaInstaller / Brands::HookusInstaller: the caller supplies
  # environment-appropriate hosts; this class deliberately knows no production
  # domain and never reassigns a host owned by another brand.
  class Date9jaInstaller
    BRAND_NAME = "Date9ja".freeze
    BRAND_SLUG = "date9ja".freeze

    class HostConflict < StandardError; end

    def self.call(hosts: [])
      new(hosts:).call
    end

    def initialize(hosts:)
      @hosts = Array(hosts).filter_map { |host| normalize_host(host) }.uniq
    end

    def call
      Brand.transaction do
        brand = Brand.kept.find_or_initialize_by(slug: BRAND_SLUG)
        brand.assign_attributes(name: BRAND_NAME, status: :active)
        brand.save!
        Profiles::Date9jaProfileCatalog.install!(brand:)
        hosts.each { |host| install_host!(brand:, host:) }
        brand
      end
    end

    private

    attr_reader :hosts

    def normalize_host(host)
      normalized = host.to_s.strip.downcase.delete_suffix(".")
      normalized.presence
    end

    def install_host!(brand:, host:)
      domain = BrandDomain.kept.find_by(host:)
      if domain.present? && domain.brand_id != brand.id
        raise HostConflict, "host is already assigned to another brand"
      end

      domain ||= BrandDomain.new(host:)
      domain.update!(brand:, status: :active)
    end
  end
end
