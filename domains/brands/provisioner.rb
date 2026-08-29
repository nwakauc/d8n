module Brands
  # Dispatches brand slugs to their brand-specific installer. This is
  # deliberately a thin registry, not a replacement for the installers: each
  # brand keeps its own idempotent Brands::<Brand>Installer, and adding a new
  # brand means adding one line here plus its installer class, not editing a
  # shared conditional.
  class Provisioner
    class UnsupportedBrand < StandardError; end

    INSTALLERS = {
      "dateza" => Brands::DatezaInstaller,
      "hookus" => Brands::HookusInstaller
    }.freeze

    def self.call(slug:, hosts: [])
      installer = INSTALLERS[slug.to_s]
      unless installer
        raise UnsupportedBrand,
          "no installer registered for brand #{slug.inspect} (supported: #{slugs.join(', ')})"
      end

      installer.call(hosts:)
    end

    def self.slugs
      INSTALLERS.keys
    end
  end
end
