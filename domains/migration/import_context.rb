module Migration
  # Explicit, testable signal that code is running inside a historical-data
  # migration/import, not live member activity.
  #
  # CANONICAL POLICY: migration PRESERVES trust, migration itself does NOT
  # EARN trust. Shared runtime code (Profiles::Publication, RealMe/photo
  # moderation, membership-milestone awarding, etc.) legitimately calls
  # Trust::AwardEvent when a real member does these things live -- but an
  # import task reconstructing historical state by driving that same shared
  # code must not mint fresh trust points for it. The member's real
  # historical trust is separately and fully preserved verbatim by
  # Date9ja::Import::TrustLedgerImport, which writes TrustEvent/TrustAdjustment
  # rows directly and is untouched by this flag.
  #
  # One central check (Trust::AwardEvent.call itself) rather than scattering
  # `unless importing?` conditionals across every award call site. Thread-local
  # (safe for the single-threaded rake tasks that are the only callers today),
  # never persisted, off by default -- code outside an explicit
  # `as_migration` block is never affected, so native Date9ja/DateZA/HookUs
  # runtime activity keeps awarding trust exactly as before.
  module ImportContext
    THREAD_KEY = :d8n_migration_import_context

    def self.migrating? = Thread.current[THREAD_KEY] == true

    def self.as_migration
      previous = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = true
      yield
    ensure
      Thread.current[THREAD_KEY] = previous
    end
  end
end
