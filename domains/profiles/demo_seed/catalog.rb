module Profiles
  module DemoSeed
    # Reads the on-disk demo image tree and turns it into an ordered list of
    # `Person` records — the single source of truth for a seeded profile's name
    # and age. NOTHING about a person is invented here beyond what the filesystem
    # states; realistic profile copy is layered on later by DemoSeed::Content.
    #
    # The tree lives at <root>/ladies and <root>/guys. A person is either:
    #   * a directory  "Thandeka-36/"  holding one or more images, OR
    #   * a loose file "Aarav-27.jpeg" (a single-image person)
    # so both shapes the founders actually produced are supported. The trailing
    # number is the age; everything before the final separator run is the name.
    class Catalog
      # <name><separators><age>, e.g. "Thandeka-36", "Tawanda--28", "Maya 27".
      NAME_AGE = /\A(?<name>.+?)[\s_.\-]+(?<age>\d{2,3})\z/
      IMAGE_EXTENSIONS = %w[ .jpg .jpeg .png .webp ].freeze
      # Numbered curated files (1.jpeg, 2.jpeg …) lead; the rest follow by name.
      NUMBERED = /\A(\d+)\z/
      GROUPS = { "ladies" => { group: "lady", gender: "woman" },
                 "guys" => { group: "guy", gender: "man" } }.freeze
      MAX_PHOTOS = 6

      # One seedable person. `seed_key`/`email` are the STABLE identity used for
      # idempotent reruns; `slug` is a human-readable label for logs.
      Person = Data.define(:seed_key, :slug, :display_name, :age, :group, :gender, :image_paths) do
        def email = "seed+#{slug}@hookus.test"
      end

      Error = Class.new(StandardError)

      def self.call(root:)
        new(root:).call
      end

      def initialize(root:)
        @root = Pathname.new(root)
      end

      def call
        raise Error, "image root not found: #{@root}" unless @root.directory?

        people = GROUPS.flat_map { |dir, meta| scan_group(dir:, **meta) }
        raise Error, "no seedable people found under #{@root}" if people.empty?

        people.sort_by(&:slug)
      end

      private

      def scan_group(dir:, group:, gender:)
        base = @root.join(dir)
        return [] unless base.directory?

        base.children.sort.filter_map do |entry|
          next if hidden?(entry)

          if entry.directory?
            person_from_directory(entry, group:, gender:)
          elsif image?(entry)
            person_from_file(entry, group:, gender:)
          end
        end
      end

      def person_from_directory(dir, group:, gender:)
        name, age = parse_name_age(dir.basename.to_s, source: dir)
        images = dir.children.reject { |child| hidden?(child) || child.directory? }
          .select { |child| image?(child) }
        raise Error, "no usable images in #{dir}" if images.empty?

        build_person(name:, age:, group:, gender:, images: order_images(images))
      end

      def person_from_file(file, group:, gender:)
        name, age = parse_name_age(file.basename(file.extname).to_s, source: file)
        build_person(name:, age:, group:, gender:, images: [ file ])
      end

      def build_person(name:, age:, group:, gender:, images:)
        display_name = name.tr("_", " ").strip
        slug = "#{group}-#{display_name.parameterize}-#{age}"
        Person.new(
          seed_key: slug, slug:, display_name:, age:, group:, gender:,
          image_paths: images.first(MAX_PHOTOS).map(&:to_s)
        )
      end

      def parse_name_age(raw, source:)
        match = NAME_AGE.match(raw.strip)
        raise Error, "cannot parse name/age from #{source}" if match.nil?

        age = Integer(match[:age], 10)
        raise Error, "age #{age} for #{source} is below the minimum of #{Profile::MINIMUM_AGE}" if age < Profile::MINIMUM_AGE

        [ match[:name].strip, age ]
      end

      # Numbered files first in numeric order (the curated primary shots), then any
      # remaining images alphabetically — a stable, human-sensible ordering.
      def order_images(images)
        images.sort_by do |path|
          stem = path.basename(path.extname).to_s
          number = stem[NUMBERED, 1]
          number ? [ 0, number.to_i, stem ] : [ 1, 0, stem.downcase ]
        end
      end

      def image?(path)
        IMAGE_EXTENSIONS.include?(path.extname.downcase)
      end

      def hidden?(path)
        path.basename.to_s.start_with?(".")
      end
    end
  end
end
