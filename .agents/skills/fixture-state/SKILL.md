---
name: fixture-state
description: Guard Adriatic fixture schema evolution and fixture-backed Editor state. Use this skill whenever a change touches Fixture, the Editor/Fixture boundary, any struct, enum, container, imported type, or shape constant reachable from Fixture, fixture tags, schema versions, manifests, history packages, migration scripts or registry, committed .fixture files, or a rebase/schema mismatch—even when the requested code change looks small. Do not use it for code proven unreachable from Fixture, such as unrelated renderer caches, build-only plumbing, or narrative text with no serialized state change.
---

# Evolve Fixture State Safely

Treat fixtures as versioned light game saves. A source change is incomplete until old
fixtures migrate, current fixtures round-trip, and the live Editor rebuilds derived state.

## Establish the boundary

1. Run `rtk make fixture-schema-check` before editing. If it already fails, separate
   rebase drift from the requested change; never bless drift by regenerating blindly.
2. Read `Fixture`, its promoted `using fixture: Fixture` placement in `Editor`, and every
   reachable type recursively. Include imported structs and enums, `using` fields, fixed
   and dynamic container element types, scalar and enum backing widths, enum order, and
   constants used as fixed-array lengths.
3. After a rebase, repeat the boundary audit from the new tree. Compare the live reachable
   graph with the current manifest before carrying migration assumptions forward.
4. Keep process, session, and resource handles on root `Editor`. Mark fixture-reachable
   derived, pointer-bound, allocator-owned, GPU, physics, audio, cache, and transient
   fields `fixture:"-"` when they must not serialize. Do not move durable playground state
   out of `Fixture` merely to avoid migration work.
5. Prove unrelated code is unreachable before declaring the skill quiet. Renderer or
   build code and narrative prose alone should cause no schema or generated-file churn.

## Create schema version N

Set `N` to the new version and `PREV` to `N-1`. Keep versions contiguous.

```sh
N=6
PREV=5
rtk make fixture-schema-check
```

1. Make the source schema change and bump `FIXTURE_SCHEMA_VERSION` exactly once.
2. Generate a new immutable manifest and history package. Never edit, regenerate, or
   rewrite a frozen `fixtures/schema/vNNNN.fixture-schema` or
   `packages/fixture_history/vNNNN/` from an older version.

```sh
rtk make fixture-schema-generate
rtk make FIXTURE_HISTORY_VERSION="$N" fixture-history-generate
rtk make FIXTURE_HISTORY_VERSION="$N" fixture-history-check
```

3. Inspect the semantic diff, then generate and check the adjacent scaffold.

```sh
rtk odin run tools/fixture_schema -collection:zelda_engine=zelda-engine/packages -- \
  migration-diff "$PREV" "$N" "$PWD" "$PWD/zelda-engine/packages"
rtk make FIXTURE_MIGRATION_FROM_VERSION="$PREV" \
  FIXTURE_MIGRATION_TO_VERSION="$N" fixture-migration-scaffold
rtk make FIXTURE_MIGRATION_FROM_VERSION="$PREV" \
  FIXTURE_MIGRATION_TO_VERSION="$N" fixture-migration-scaffold-check
```

4. Resolve every scaffold obligation with explicit Odin in
   `src/fixture_migration_vNNNN_to_vNNNN.odin`. The scaffold is a review list, not
   permission to guess semantics:

   - rename: copy the old field to its new name; never model it as blind remove and add;
   - remove: explicitly discard or project the old value and document why;
   - split: derive every new field from the old value with validated defaults;
   - merge: define precedence and conflict behavior for every old input;
   - new field: assign an intentional default, using zero only when zero is correct;
   - changed enum, container, or width: validate old bounds before conversion.

5. Register only the adjacent `PREV -> N` step. Keep the registry contiguous, reject gaps
   and duplicates, and prove direct `PREV -> N` plus every supported chained path to `N`.

## Prove compatibility

Add or update frozen golden containers and test:

- exact semantic values, deterministic bytes, and immutable migration input;
- malformed containers, invalid enums, counts, indices, identities, and hostile nested
  state;
- allocation failure at every fallible boundary, atomic failure, idempotent disposal, and
  zero leaks;
- current codec round-trip, lifecycle detach, prepare and bind, migration chains, Editor
  load and store, and batch-upgrader behavior.

Run the focused and global gates:

```sh
rtk make fixture-codec-test
rtk make fixture-lifecycle-test
rtk make fixture-migration-test
rtk make fixture-editor-load-test
rtk make fixture-editor-store-test
rtk make fixture-upgrade-test
rtk make fixture-schema-check
rtk make check
rtk make test
```

Upgrade committed `*.fixture` files only after tests pass. Build the real CLI, inspect the
file list, dry-run each owning directory, then repeat without `--dry-run`. Do not hand-edit
binary fixture files.

```sh
rtk rg --files -g '*.fixture'
rtk make build
rtk ./build/dev/adriatic fixture-upgrade --dry-run fixtures
rtk ./build/dev/adriatic fixture-upgrade fixtures
```

## Review and handoff

Use only Jujutsu. Inspect `rtk jj status` and `rtk jj diff --git`; commit only intended
source, new-version artifacts, migrations, tests, and upgraded fixtures.

Report:

- old and new schema versions and the post-rebase boundary audit;
- every reachable schema change and migration obligation, including unresolved IDs;
- new manifest, history, scaffold, and migration paths and hashes;
- each scripted rename, remove, split, merge, and default decision;
- registry continuity and direct and chained paths proven;
- golden, hostile, OOM, codec, lifecycle, migration, Editor load/store, and upgrader gates;
- dry-run and real batch-upgrade file counts;
- `fixture-schema-check`, `check`, and `test` results;
- exact `rtk jj diff --git` scope, with frozen history confirmed untouched.

Run `rtk make fixture-schema-check` again immediately before handoff.
