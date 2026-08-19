module Trust
  # Registry + shared contract for the per-target-type authorization/evidence
  # resolvers used by Trust::FileReport.
  #
  # A resolver's ONLY job is to answer, entirely server-side: "may THIS viewer
  # report the content identified by this opaque id, and if so, who is responsible
  # for it and what minimal evidence should survive?" It authorizes, derives the
  # responsible profile from the target (never trusting a client-supplied
  # reported_profile_id), and returns a Resolution. Every failure — unknown,
  # cross-brand, inaccessible, self-owned, deleted — raises the SAME neutral
  # AccessError(:target_unavailable) so nothing about the target is enumerable.
  module ReportTargets
    # What a resolver returns. `target_id` is the INTERNAL record id (nil only for
    # a plain profile report); `reported_profile` is the derived responsible
    # person; `evidence` is the minimal immutable snapshot persisted on the report.
    Resolution = Data.define(:target_type, :target_id, :reported_profile, :evidence)

    RESOLVERS = {
      "profile" => ProfileTarget,
      "message" => MessageTarget,
      "profile_media" => MediaTarget,
      "hook" => HookTarget
    }.freeze

    def self.resolver_for(target_type)
      RESOLVERS[target_type.to_s]
    end
  end
end
