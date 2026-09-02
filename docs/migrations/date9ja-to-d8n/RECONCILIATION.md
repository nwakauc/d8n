# Reconciliation Plan

No production counts were collected in Phase 1 because production access remains out of scope. Run against the approved snapshot and staging/import output, recording snapshot/run IDs and timestamps.

| Measure | Source | Target | Acceptance |
|---|---:|---:|---|
| users/accounts | pending | pending | equal after documented exclusions |
| published profiles | pending | pending | equal after state mapping |
| photos | pending | pending | equal; exceptions listed |
| verified users | pending | pending | equal under approved definition |
| likes | pending | pending | equal after valid mapping |
| passes | pending | pending | equal or approved exclusion |
| matches | pending | pending | equal canonical unique pairs |
| conversations | pending | pending | one per retained match |
| messages | pending | pending | equal per retention policy |
| blocks | pending | pending | equal same-brand rows |
| reports | pending | pending | equal retained reports |

Also reconcile profile videos, message reactions, profile views, verification records/status/history, trust records/status, notification preferences/deliveries, Community, Dating Hub, Aunty Phobie, subscription/entitlement state, and any other active capability in [CAPABILITY-PARITY.md](CAPABILITY-PARITY.md). For retained features, an “approved exclusion” is not a cutover pass: the feature must have a supported target or an explicitly approved transition that preserves user access.

Validate that every mapped user has exactly one D8N user and at most one Date9ja membership/profile; every relationship is same-brand, non-self, directional where applicable; every match is canonical and unique; every conversation has exactly two match participants; every message has a valid participant sender and same-conversation reply; and read state maps to the correct participant.

For media, verify every source blob/object exists, matches checksum/size/type, maps to a destination public ID, and is deliverable under D8N privacy rules. Missing or unsupported objects are exceptions, not skips.

Run the importer twice against the same snapshot: the second run must create zero users, profiles, relationships, conversations, or messages, and destination IDs/fingerprints must remain unchanged. Test interruption/resume as well.

```text
Snapshot <id> / run <id>
Users <source> → <target> ✓
Profiles <source> → <target> ✓
Photos <source> → <target> ✓
Likes <source> → <target> ✓
Matches <source> → <target> ✓
Conversations <source> → <target> ✓
Messages <source> → <target> ✓
Blocks <source> → <target> ✓
Reports <source> → <target> ✓
Orphans 0 ✓ / Duplicate identities 0 ✓ / Broken media 0 ✓
Unmapped records 0 or approved exception list
```
