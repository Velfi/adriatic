# Fixture and SDF Barrier Rework Plan

## Feature

Rework gameplay fixtures into versioned, lightweight editor saves, then rebuild
SDF barriers on top of the fixture system.

## Problem

Level designers need reproducible testing playgrounds without rebuilding scene
setup by hand. Fixtures must preserve nearly all relevant `Editor` state, remain
loadable as game-state schemas evolve, and support explicit scripted migrations
when a structural change cannot be migrated safely by convention.

## Scope and decisions

- `Editor` remains the hot-reload serialization root.
- Fixture-relevant state lives in a promoted `using fixture: Fixture` field.
- Fields that belong to `Fixture` structurally but must not be persisted use
  `fixture:"-"`.
- Fixture files use a versioned binary container with an `hs` payload.
- Every persisted schema change requires a schema-version bump and one migration.
- Unambiguous migrations may be generated automatically.
- Ambiguous migrations require an Odin script before the schema change passes
  validation.
- Editor in-memory migration and offline batch upgrades are separate milestones.
- SDF barriers begin only after current-version fixture save/load and migration
  behavior are demonstrable.

## Complexity

Large. The work crosses editor ownership, serialization, runtime rehydration,
schema tooling, migration execution, agent workflow, and SDF authoring.

## Current phase

Phase 3 — Verify milestone 1.

## Milestone 1 — Split `Editor` state

### Goal

Create the fixture schema boundary without changing existing behavior or adding
fixture file I/O.

### First slave implementation plan

1. Read `AGENTS.md`, the RTK instructions, and the current `Editor` definition.
2. Confirm the working copy state with `jj status`.
3. Add `Fixture :: struct` immediately before `Editor`.
4. Add exactly one promoted field to `Editor`:

   ```odin
   using fixture: Fixture,
   ```

5. Preserve existing `editor.field` call sites through Odin field promotion.
   Do not mechanically rewrite them as `editor.fixture.field`.
6. Keep `hs.serialize(editor)` and `hs.deserialize(editor)` unchanged. Hot
   reload continues to serialize the full `Editor`, including its nested
   `Fixture`.
7. Move the following durable state into `Fixture`:

   - authored terrain and project state;
   - stable level-authoring tool selection and parameters;
   - formation, architecture, foliage, Greek placement, curve, and road data;
   - player, camera, vehicle, aircraft, and trailer state;
   - vehicle visibility and showcase state;
   - durable vehicle-paint content and tool configuration;
   - attendant position and camera target state;
   - atmosphere, particle effects, and tweak state;
   - mouse appearance and scarf state.

8. Keep conceptually fixture-owned transient state inside `Fixture`, but mark it
   `fixture:"-"`:

   - active structure placement, movement, anchors, previews, and grab offsets;
   - active formation, architecture, climbing-leaf, curve, and road gestures;
   - architecture preview caches and dirty bounds;
   - player paw-plant and cursor caches;
   - vehicle-paint dirty flags, save timers, cursors, strokes, drags, hover
     state, scratch buffers, derived preview buffers, undo/redo data, texel
     lookup data, and generated paint mesh;
   - live dialogue state and dialogue UI state;
   - current flight input;
   - tweak UI, pause UI, dither tracking, and customization focus.

9. Keep runtime-only or session-only state on root `Editor`:

   - flame instrumentation;
   - capture configuration;
   - structure and terrain undo/redo histories;
   - file-status feedback and saved-revision bookkeeping;
   - frame timing and interpolation caches;
   - loaded Greek GLB asset catalog;
   - physics world, vehicle, body IDs, accumulator, and wheel cache;
   - audio device and audio-only transient state;
   - generated Libellula and Postale meshes and projected faces;
   - gameplay preferences and runtime input device state;
   - loaded control-hint and paint-tool textures;
   - controller, pause, and options UI session state;
   - quit state.

10. Keep pointer-linked gameplay values such as `pilot`, `car`, `postale`,
    `libellula`, and `aircraft` in `Fixture`. Do not solve pointer rebinding in
    this milestone; that belongs to the rehydration milestone.
11. Do not add fixture file I/O, migration behavior, schema parsing, SDF
    barriers, or new UI.
12. Format only changed Odin files.
13. Inspect the complete diff with `jj diff --git`.
14. Run `make check` and `make test`.
15. Do not commit until all acceptance criteria pass.

### Acceptance criteria

- `Fixture` is an explicit schema root.
- `Editor` contains exactly one `using fixture: Fixture` field.
- Existing `editor.field` call sites remain unchanged and compile.
- Hot save/load still serializes and deserializes `Editor`.
- Fixture-excluded fields carry `fixture:"-"`.
- Only the structural split is present.
- Formatting, `make check`, and `make test` pass.

### Status

- Implementation exists in `src/main.odin`.
- Static diff review and formatting passed.
- `make check` and `make test` are blocked before Odin compilation because
  `/Users/wolfie/bin/odin` invokes missing
  `/Users/wolfie/install/odin/odin`.
- Milestone remains unverified and uncommitted until the toolchain is restored.

## Milestone 2 — Establish schema version 1

Build an Odin tool using `core:odin/parser` and `core:odin/ast`. It must find
`Fixture`, walk reachable persisted types, ignore `fixture:"-"`, and write a
deterministic versioned schema manifest.

Acceptance criteria:

- Re-running the tool without source changes produces identical output.
- A persisted field change without a version bump fails validation.
- A root-only or `fixture:"-"` change does not alter the fixture schema.

## Milestone 3 — Add the binary fixture codec

Add fixture-aware `hs` serialization and a product-local fixture container with
magic, container version, fixture schema version, payload length, and payload
hash.

Acceptance criteria:

- Current `Fixture` state round-trips through memory.
- `fixture:"-"` fields and their dynamic contents are absent from the payload.
- Truncated, corrupt, unsupported, and oversized payloads fail safely.
- Representative binary fixtures are materially smaller than equivalent TOML.

## Milestone 4 — Rehydrate safely into a live `Editor`

Decode into temporary state, validate it, preserve root runtime state, replace
`editor.fixture`, and rebuild runtime relationships and derived resources.

Required fixups include:

- pilot, car, Postale, Libellula, and aircraft pointer relationships;
- physics world, terrain bodies, and vehicle state;
- generated meshes and projected faces;
- paint scratch state and texture invalidation;
- audio, dialogue, input, and active-gesture reset;
- terrain and renderer cache invalidation.

Acceptance criteria:

- Failed loads do not mutate the live editor.
- Successful loads preserve root runtime resources.
- Gameplay ownership pointers reference live objects, never serialized memory.
- Loaded fixtures can run for multiple frames without invalid handles.

## Milestone 5 — Save and load the current schema in the editor

Expose level-designer save/load actions for current-version fixtures. Migration
is deliberately out of scope here.

Acceptance criteria:

- A designer can save a configured playground.
- Mutating the scene and loading the fixture restores the saved situation.
- Saving always writes the newest schema version.
- User/session preferences and root runtime state remain unchanged.

## Midpoint sunk-cost check

Stop after milestone 5 and confirm the core behavior is demonstrable. If a
fixture cannot reliably reproduce a representative playground, migration work
must not begin.

## Milestone 6 — Generate migrations from schema changes

Diff consecutive schema manifests and generate exactly one migration step for
each version transition.

Acceptance criteria:

- Additions and other unambiguous changes receive generated mappings.
- Removed, renamed, split, merged, or semantically changed fields produce a
  failing Odin script stub with useful context.
- Missing, duplicate, or skipped migration steps fail validation.

## Milestone 7 — Run migration chains during editor load

Allow the editor to load old fixtures by running every migration in memory
before rehydration.

Acceptance criteria:

- A golden version-1 fixture loads under a later schema.
- Migrations execute once, in strict version order.
- A migration failure leaves the live editor and source file unchanged.
- Saving the migrated state writes only the newest schema.

## Milestone 8 — Batch-upgrade fixtures on disk

Build a CLI that uses the same migration registry to upgrade one fixture or a
directory tree.

Acceptance criteria:

- Dry-run reports planned migrations without writes.
- Successful upgrades use atomic replacement.
- Failure cannot leave a partially rewritten fixture.
- Re-running against current fixtures is a no-op.
- Custom Odin migration scripts can resolve ambiguous changes.

## Milestone 9 — Add schema guardrails and agent skill

Create a repository skill for agents changing `Fixture` or any reachable
serializable type. Add validation to the normal project workflow.

The skill must require agents to:

- run the schema check before and after relevant changes;
- bump the fixture schema version;
- generate the migration;
- resolve ambiguous script stubs;
- run migration goldens and fixture tests;
- batch-upgrade committed fixture files when required;
- inspect all VCS diffs in `jj --git` format.

Acceptance criteria:

- CI or the project check target rejects unversioned fixture schema changes.
- Skill evaluations cover an additive field, an ambiguous rename, and an
  unrelated non-fixture change.
- The skill triggers for relevant game-state changes and stays quiet for
  unrelated source changes.

## Milestone 10 — Define the SDF barrier schema

Add stable barrier IDs, transforms, dimensions, shape representation, and
validation to fixture-relevant state.

Acceptance criteria:

- Barrier data round-trips through fixtures.
- Invalid dimensions, transforms, and shape variants are rejected or
  normalized deterministically.
- No editor interaction or rendering behavior is required yet.

## Milestone 11 — Implement SDF barrier runtime behavior

Implement distance evaluation, gameplay/collision integration, and rendering
contract.

Acceptance criteria:

- Supported shapes produce deterministic signed distances.
- Collision/gameplay behavior agrees with rendered geometry.
- Runtime tests cover inside, surface, outside, transform, and degenerate cases.

## Milestone 12 — Implement SDF barrier authoring

Add create, select, move, rotate, scale, duplicate, and delete workflows with
undo support and clear visual guides.

Acceptance criteria:

- Every authoring action is reversible.
- Selection and gizmo behavior remain stable across camera angles.
- Saving and loading preserves authored barriers.

## Milestone 13 — Integration and polish

Run full fixture, migration, SDF, build, test, and representative capture
checks. Remove debug paths and temporary compatibility code.

Acceptance criteria:

- Existing tests pass.
- Golden fixtures migrate successfully.
- Representative playgrounds reproduce expected state.
- SDF barriers survive edit, save, load, migration, and runtime use.
- No known runtime handles or transient pointers enter fixture payloads.
