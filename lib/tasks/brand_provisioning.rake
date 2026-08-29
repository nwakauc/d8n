# Generic operator-facing entry point for provisioning any supported brand's
# persisted foundation (Brand, BrandDomain, auth_methods, profile catalog).
# Dispatches to the brand-specific installer registered in
# Brands::Provisioner — it does not replace brand.install_dateza or the dev
# seed tasks, which remain valid for their existing callers (e.g. the docker
# entrypoint).
#
#   bin/rails 'brands:provision[hookus]' HOSTS=hookus.test
#   bin/rails 'brands:provision[dateza]' HOSTS=dateza.test,dateza.example.com
namespace :brands do
  desc "Provision a brand's persisted foundation. Usage: bin/rails 'brands:provision[slug]' HOSTS=host1,host2"
  task :provision, [ :slug ] => :environment do |_, args|
    slug = args[:slug]

    if slug.blank?
      abort "Usage: bin/rails 'brands:provision[slug]' HOSTS=host1,host2 (supported: #{Brands::Provisioner.slugs.join(', ')})"
    end

    hosts = ENV.fetch("HOSTS", "").split(",").map(&:strip).reject(&:blank?)

    brand =
      begin
        Brands::Provisioner.call(slug:, hosts:)
      rescue Brands::Provisioner::UnsupportedBrand => e
        abort e.message
      end

    puts "#{brand.slug} brand ready (auth: #{brand.auth_methods.join(', ')}; hosts: #{hosts.join(', ')})"
  end
end
