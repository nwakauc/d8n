#!/usr/bin/env bash
# Retired: copying destination primary keys is unsafe in a shared populated DB.
# Stable ReferenceMap bindings preserve platform ownership and remap every FK.
# Phase 1 permits isolated rehearsal only; production application stays fenced.
set -euo pipefail
printf '%s\n' 'Unsafe PK-copy promotion disabled. Use final_sync.rb on an isolated rehearsal database; see PHASE1-CLOSURE.md.' >&2
exit 64
