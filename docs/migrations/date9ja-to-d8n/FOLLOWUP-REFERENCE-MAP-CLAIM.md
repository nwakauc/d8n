# Follow-up: `Migration::ReferenceMap.claim` aborts its own recovery path

**Status:** OPEN — **blocking for Pass 2** of the profile & preference migration.
**Raised:** 2026-09-05, during Pass 1 (source value census). Found by code
reading after a concurrency test failed under parallel load.
**Not fixed here.** Pass 1 is an evidence feature and changed no production code
(this document was re-worded, but not the code, in the 2026-09-06 review-fix
pass);
this is a production defect in shared migration infrastructure and needs its own
slice, its own review, and its own commit.

---

## The defect

`domains/migration/reference_map.rb`:

```ruby
def bind!(...)
  LegacyReference.transaction do                     # line 42 — outer transaction
    reference = locate(key:, target:) || claim(...)  # line 43
    ...
  end
end

def claim(key:, target:, importer_version:, fingerprint:)
  LegacyReference.create!(...)                       # line 113 — may violate the unique index
rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
  # "A concurrent writer won the race between our locate check and this
  #  insert. Re-resolve and let assert_same_binding! classify the outcome"
  locate(key:, target:) || raise                     # line 123 — CANNOT RUN
end
```

In PostgreSQL, a statement that raises inside a transaction **aborts that
transaction**; every subsequent statement fails with `PG::InFailedSqlTransaction`
until rollback. The `create!` at line 113 runs inside the `LegacyReference.transaction`
opened at line 42, so by the time the `rescue` at line 118 executes, the
transaction is already poisoned and the `locate` at line 123 cannot execute.

**The documented recovery path is therefore unreachable.** When a concurrent
claimer actually wins the race, `bind!` raises `PG::InFailedSqlTransaction`
instead of resolving the binding idempotently.

To be precise about the trigger: the defect needs a **second writer** to insert
the same key between this caller's `locate` and its `create!`. An ordinary
sequential retry does **not** race itself — a re-run of `bind!` in a
single-threaded importer finds the row at `locate` and never reaches `claim`. The
reachable scenarios are concurrent claimers: parallel importer workers, an
overlapping cutover-delta worker, a retried job running beside the original, or
any future concurrent slice.

The recovery is only sound if the insert runs in its own savepoint — i.e.
`LegacyReference.transaction(requires_new: true) { create!(...) }` — so that
rolling back to the savepoint leaves the outer transaction usable.

## Evidence

`test/domains/migration/reference_map_test.rb:187`
(`ReferenceMapConcurrencyTest#test_concurrent_binds_of_the_same_key_produce_exactly_one_row`)
races four threads on one key and asserts none of them sees an error. Observed
failure output:

```
#<LegacyReference id: 549, ... source_id: "555" ...>
#<ActiveRecord::StatementInvalid:
    "PG::InFailedSqlTransaction: ERROR:  current transaction is aborted,
     commands ignored until end of transaction block">
#<LegacyReference id: 549, ... source_id: "555" ...>
```

Two threads resolved to the same row (correct); one hit the aborted-transaction
path.

- Reproducible under the full parallel suite (2/2 runs).
- Passes in isolation (6/6 runs) — the race has to actually be lost.
- Pre-existing: unchanged by Pass 1, which modified no file under `domains/`.
- A clean-tree control run of the same suite produced a *different*
  parallel-only failure, confirming the suite has several order/timing-sensitive
  tests and that the trigger here is scheduling, not the census work.

## Why this blocks Pass 2

Pass 2 is a **direct `ReferenceMap` consumer**: it will bind the
`ProfilePreference` it creates for each migrated member, plus whatever further
bindings Pass 2 explicitly introduces. *(It is not claimed here that every
`ProfileOptionSelection` is registered as its own binding — Pass 2 has not been
designed, and which destination types it registers is one of the things that
design will decide.)* `ReferenceMap` is the deterministic idempotency spine for
**every** importer slice (ADR 0022), and idempotent re-run is a stated acceptance
requirement for each of them.

The exposure is narrower than "any retry", and worth stating exactly:

- it needs **concurrent claimers** — parallel importer workers, a cutover-delta
  worker overlapping a backfill, or a retried job running beside the original.
  A sequential retry on its own resolves at `locate` and never reaches `claim`;
- when it does occur the failure mode is a hard exception rather than the
  documented `already_imported` outcome, so the run fails in a way the
  reconciliation contract does not anticipate;
- the same path is on the critical route for the cutover delta, which is where
  concurrency is most likely to be introduced.

## Scope of the fix (for whoever picks this up)

1. Wrap the `create!` in `claim` in `requires_new: true` so the unique-violation
   rolls back to a savepoint and the outer transaction survives.
2. Confirm `assert_same_binding!` still classifies all three outcomes correctly
   (identical → idempotent, source key taken → `ImmutableBinding`, destination
   taken → `DestinationConflict`).
3. Make `ReferenceMapConcurrencyTest` deterministic rather than
   scheduling-dependent, so the regression cannot hide again.
4. Check whether any other importer rescues a constraint violation inside an
   enclosing transaction — the same shape may exist elsewhere.

Do not bundle this with a Pass-2 feature: it is shared infrastructure with its
own blast radius and deserves an independent review.
