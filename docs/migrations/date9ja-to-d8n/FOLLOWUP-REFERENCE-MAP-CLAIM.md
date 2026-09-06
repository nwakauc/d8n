# Follow-up: `Migration::ReferenceMap.claim` aborts its own recovery path

**Status: CLOSED — fixed 2026-09-06.** `domains/migration/reference_map.rb`
`claim` now wraps its INSERT in `LegacyReference.transaction(requires_new: true)`,
so a unique violation rolls back to a savepoint and the enclosing transaction
survives to run the documented recovery. Deterministic regression tests:
`Migration::ReferenceMapLostRaceTest` (`test/domains/migration/reference_map_test.rb`).
No longer blocking for Pass 2. The rest of this document is retained as the
diagnosis and the record of what was changed.
**Raised:** 2026-09-05, during Pass 1 (source value census). Found by code
reading after a concurrency test failed under parallel load.
**History.** Raised during Pass 1, which is an evidence feature and deliberately
changed no production code. Fixed afterwards as its own small slice, as intended
— the fix is production code in shared migration infrastructure, kept separate
from both the Pass-1 evidence work and Pass 2.

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

## Why this had to be fixed before Pass 2

Pass 2 is a **direct `ReferenceMap` consumer**, which is why this was treated as
a blocker: it will bind the
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

## The fix, as applied (2026-09-06)

**1. Savepoint.** `claim` wraps its `create!` in
`LegacyReference.transaction(requires_new: true)`. The unique violation now rolls
back to a savepoint; the enclosing transaction stays usable and the recovery
`locate` runs. This is the same idiom Rails uses internally for
`create_or_find_by!`. One-line change; no signature, semantics or call-site change.

**2. All three outcomes reconfirmed** by test — identical → idempotent (metadata
still refreshes), source key taken → `ImmutableBinding` (the winner's binding is
never rewritten), destination taken → `DestinationConflict` (the loser gets no
row).

**3. Deterministic regression tests.** `ReferenceMapLostRaceTest` reproduces the
lost race without threads racing, sleeps, or scheduling luck.

> **Why a naive reproduction does not work, and why the old test was flaky.**
> Staging the conflicting row *before* calling `bind!` does **not** reproduce
> this defect. `LegacyReference` carries model-level uniqueness validations
> (`app/models/legacy_reference.rb:20-23`), so `create!` SELECTs first and raises
> `ActiveRecord::RecordInvalid` **without ever issuing the failing INSERT** —
> the transaction is never poisoned and the recovery works. The defect needs a
> genuine `ActiveRecord::RecordNotUnique` from the database index, which only
> happens when a competing writer commits *after* our validation passed. That is
> exactly why `ReferenceMapConcurrencyTest` only failed intermittently: it
> needed two threads to clear validation in the same instant.
>
> The new tests therefore commit the competing row **from a second connection
> inside a `before_create` hook** — after our validations have passed, before our
> INSERT. The thread is joined before the hook returns, so the ordering is fixed.
> Verified both ways: with the savepoint removed, five tests fail with
> `PG::InFailedSqlTransaction`; with it in place, 3/3 runs green.

**4. Same shape elsewhere — checked.** All 16 `rescue ActiveRecord::RecordNotUnique`
sites were reviewed. Most rescue *outside* the transaction block (the exception
has already escaped, so Rails has issued the ROLLBACK and the connection is
clean), and `Analytics::Emit` is safe because Rails' own `create_or_find_by!`
already uses `requires_new: true`. **One genuine look-alike was found and is NOT
fixed here** because it is outside migration infrastructure and off Pass 2's
path: `Notifications::EventPublisher.publish!`
(`domains/notifications/event_publisher.rb:108`) recovers with `find_by!` after
`find_or_create_by!`, and is called *inside* the transaction that
`Hooks::SendHook` opens (`domains/hooks/send_hook.rb:58`). It has the same
aborted-transaction exposure under concurrency and wants the same one-line fix in
its own slice.
