# D8N Migration Architecture

## Core Rule

Schema changes and data migrations should be separate when production data is involved.

Do not run large unsafe data updates inside deployment migrations.

## Production Migration Pattern

Preferred sequence:

1. Add nullable column/table/index safely.
2. Deploy code compatible with old and new schema.
3. Backfill in batches.
4. Verify reconciliation counts.
5. Add constraints after data is valid.
6. Deploy final code.

## Date9ja Migration

Date9ja is a live migration target with existing users and data. This was confirmed by the founder on 2026-08-13.

Before migration:

- Inventory legacy schema.
- Inventory password/hash/auth behavior.
- Inventory media storage.
- Map legacy records to D8N domains.
- Dry-run migration.
- Reconcile counts.
- Prepare rollback/fallback plan.

Do not treat Date9ja as a clean new brand configuration. Preserve existing users and reconcile all migrated production data.
