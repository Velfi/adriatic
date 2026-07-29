# Fixture Rework Plan

## Feature

Rework gameplay fixtures into versioned, lightweight editor saves.

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
- Fixture policy, schema tooling, and migrations stay product-local. Reachable
  engine types may be described by the schema walker, but product-specific
  tags or rules must not be added to vendored `zelda-engine`.

## Complexity

Large. The work crosses editor ownership, serialization, runtime rehydration,
schema tooling, migration execution, and agent workflow.

## Current phase

Milestone 4C is accepted. Before M4D, reconcile the seventh rebased baseline:
the fixture changes now sit on the ACE flight/story rewrite, whose new
fixture-reachable state no longer matches frozen schema v4. Audit the complete
4→live diff, choose the next schema version, and generate/resolve its migration
without modifying frozen v1–v4 artifacts.

Schema-v4 activation and migration remain accepted. The prior rebased baseline
introduced 118 persisted schema changes, which were resolved by schema version
4 and the 3→4 scripted migration.
M4B2B4C, M4B2B4B, M4B2B4A, and
M4B2B4AR are accepted. Source schema version 3 and its history package are
frozen. M4B2B3, M4B2B3R, and M4B2B3R2 are accepted.
Historical v1/v2 decodes authenticate the exact canonical portable type table
while ordinary migration decode remains schema-tolerant. M4B2B2B, M4B2B2BR,
M4B2B2A, M4B2B1, M4B2B1R, M4B2A, and M4B1 are accepted.
M3F1, M3F1R, M3F2A, M3F2B, M4A, and M4AR are accepted.
M3D2A, 3D2B1, 3D2B2, 3E1, 3E2, 3E3, and their repairs are accepted.
Milestones 1 through 3B, 3CR, 3CR2, 3D1, 3D1R, 3D1R2, and 3D1R3 are
accepted. Fixture schema versions 1 and 2 remain frozen and current source
schema version is 4.

## Seventh rebased baseline audit — 2026-07-30

The fixture stack was rebased again after harbor authoring, flock simulation,
player terrain spray, and mouse mailbag presentation state landed on `main`.
All already-accepted fixture schema versions 1 through 5 remain immutable.
Jujutsu ancestry moved; the wire-format history did not. The rebased state
delta therefore belongs to a new 5→6 boundary after the existing stack, not to
a rewrite of any frozen manifest or migration.

New root state is classified as follows:

- `harbor_authored_plan` and `harbor_authored_intervention` are durable level
  design state and remain persisted;
- `player_stop_spray_cooldown`, `player_stop_spray_speed`, both flock systems,
  `player_terrain_effects`, and all six mouse mailbag spring scalars are
  derived runtime/presentation state and use `fixture:"-"`;
- the flock fields retain `hs:"-"` as well as the fixture exclusion;
- harbor previews and default-harbor caches remain excluded, while authored
  harbor data is not hidden to preserve a passing old manifest.

At the founding change, after these exclusions, the live draft is deterministic
at 1,961
lines, 205 records, 156 root fields, and SHA-256
`fc9267d00f967f25858d0513a10723fd96ef56daad3f7fc2097afc0c2e1529e6`.
Compared with frozen v4, the rebase adds 128 semantic changes: 90
state-bearing and 38 supporting. The only direct root additions are the two
authored harbor fields, but reachable flight, story, terrain, farmland,
settlement, road, building, and animation-tweak state also changed. Conflict
repair must preserve exact v1–v5 bytes. A separate version-6 milestone must
generate the final live report, scaffold all state obligations, script the
ambiguous enum/structural transformations, activate 5→6, and upgrade fixtures.

## Sixth rebased baseline audit — 2026-07-29

The fixture change `mwytpkmk` was rebased from `uoqktrkp` onto current `main`
`vxzsozzw` (`Add settlement brush planning tools`). Jujutsu exposed two
two-sided conflicts in `Makefile` and `src/main.odin`.

The `Makefile` resolution retains main's `instrument-deep`, `mcp`, and
`test-rondine` targets and all fixture schema/history/scaffold/codec/migration
targets. The `Editor` resolution retains main's process/session-owned gameplay
physics, player placement, and photo-mode fields on `Editor`, plus all
fixture-rework session state already moved out of `Fixture`.

New fixture state is classified as follows:

- `farm_brush_yaw`, authored wreck controls/data, settlement brush
  shape/preset, Rondine runtime, and Rondine visibility are durable playground
  state and remain serialized;
- farm and wreck previews are derived interaction state and use
  `fixture:"-"`;
- `default_marinas`, `default_marina_islands`, and
  `default_marina_count` are derived caches and use both `hs:"-"` and
  `fixture:"-"`;
- gameplay/car physics, player-placement diagnostics, and photo-mode restore
  state remain process/session-owned `Editor` fields;
- `story.State.clinic_visits` and
  `story.State.resident_action_seen` are durable story progress and remain
  serialized;
- `player_tail` is derived simulation state and its new `fixture:"-"` is
  correct.

The live schema walker required one rebase compatibility extension. Odin
represents `[Resident]u64` as an enum-indexed array expression. The walker now
resolves local and imported enum index types, records their reachability,
accepts only non-empty contiguous unique value ranges, rejects overflow, and
preserves ordinary `Enum.Count` constant evaluation. Its deterministic focused
proof covers an imported enum index, a local `Count`, and a hostile gapped
enum. The exclusion sentinel now includes `default_marina_islands`.

Rondine also required immediate compatibility repairs without activating a new
wire value:

- fixture occupant derivation now validates the distinct Rondine vehicle
  pointer, aliases, and stray drivers;
- occupied Rondine fails closed because frozen schema-3
  `Fixture_Occupant` has no Rondine wire value;
- hot-state save clears `state.rondine.vehicle.driver`; its focused
  serialize/deserialize proof preserves the source graph and verifies every
  copied vehicle/driver pointer is nil;
- the current codec test fixture uses the replacement settlement brush
  shape/preset instead of the removed `architecture_brush_radius`.

No v4 schema, history package, wire enum value, migration scaffold, migration
implementation, or lifecycle implementation was created.

The read-only production 3→4 report is deterministic:

- frozen v3 SHA-256
  `210c2d82c27ac668bcdae75f18c5735726f7d88ca48609a8795bdaec56225b9f`;
- candidate SHA-256
  `ccf8490c493ca6e662242963a6abf4c49d08f84d595216a4a262b7ef4d885f97`;
- 1,610 lines, 167 records, and 154 root fields;
- 118 changes: 99 state-bearing and 19 supporting;
- 13 enum additions, 20 enum-value changes, 55 field additions, eight field
  removals, one field-type change, 19 type additions, and two type removals;
- direct `Fixture` delta is ten additions and two removals:
  `architecture_brush_shape`, `architecture_brush_preset`, `farm_brush_yaw`,
  five authored wreck fields, `rondine`, and `rondine_visible` are added;
  `architecture_brush_radius` and `player_tail` are removed.

The exact report makes schema version 3 intentionally blocked on this rebased
tree. `FIXTURE_SCHEMA_VERSION` must not remain 3 for fixture writes. Version 4
must resolve all 99 state obligations, including shifted enums, removed
airframe/settlement fields, the settlement-plan expansion, the brush-radius
replacement, story resident expansion, authored wreck state, Rondine runtime,
and a stable `.Rondine = 5` occupant discriminator.

Portable codec work is also mandatory before v4 activation:
`$.story_state.resident_action_seen` currently fails with
`.Unsupported_Type` because the portable reflection codec does not yet support
enum-indexed arrays. The focused codec error path exposes an existing 34-byte
owned path leak when its success-only assertions continue after that expected
failure; the v4 codec milestone must add support and retain zero-leak failure
proofs.

Verification after conflict resolution:

- `make check` passes;
- the hot-state Rondine pointer proof passes 1/1 in 4.785s with zero leak
  diagnostics;
- `make test` passes the separate Rondine package 19/19 and the main suite
  614/615; the sole main-suite failure is the expected frozen-v3 manifest
  assertion;
- v1/v2/v3 history checks and generated-package compilation pass;
- all three frozen schema hashes, all three frozen history hashes, and both
  resolved migration hashes remain exact;
- occupancy production intentionally changes from its schema-3 pre-rebase hash
  to
  `8d1b1f1fed5ddfa8f50b90b2a0d4cb02260564dcfd5208518ebd222624300487`;
- `make fixture-schema-check` reaches the frozen comparison and fails first at
  the new `architecture.City_Alley.household_demand`;
- `make fixture-codec-test` compiles both focused tests and fails 0/2 at the
  enum-indexed story array described above;
- `make fixture-migration-test` compiles all six tests and passes 3/6; the
  current transaction/OOM paths and story golden reserialization fail when
  they encode the unsupported live graph;
- no generated `fixture_schema`, `src.bin`, `tests.bin`, probe, v4 manifest,
  v4 history package, or 3→4 migration artifact remains.

## Fifth rebased baseline audit — 2026-07-28

The resolved working change `mwytpkmk` has no Jujutsu conflicts and sits on
`uoqktrkp` (`Clarify story objectives and emoji rendering`). The 3D1R2 parser
and test files are byte-identical to their pre-rebase reviewed state.

A direct isolated call to the production AST walker built the complete
pre-activation candidate without writing the repository. The pre-activation
source version was 1; the activated source version is now 2. The pre-activation
candidate remains deterministic at 1,371 lines, 149 records, 145 root fields,
and SHA-256
`eab829c2335fb7d61ceb5322b05c1f7b74f986aed30fead4d7837e975823a336`.
The activated v2 manifest is deterministic at 1,371 lines and SHA-256
`0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`.
Frozen version 1 remains 1,340 lines with 144 records, 142 root fields, and
SHA-256
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
Generated historical v1 remains SHA-256
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.

Using one record for a wholly added supporting type and one record for each
changed field, the semantic delta is exactly 21 changes: 16 state-bearing
changes and five supporting type additions.

State-bearing changes:

- `architecture.City_Plan.structures`: `[256]terrain.Structure` to
  `[dynamic]terrain.Structure`;
- `architecture.City_Plan.parcels`: `[256]architecture.City_Parcel` to
  `[dynamic]architecture.City_Parcel`;
- `architecture.City_Plan.alleys`: `[128]architecture.City_Alley` to
  `[dynamic]architecture.City_Alley`;
- `architecture.City_Plan.lamps`: `[256]architecture.City_Lamp` to
  `[dynamic]architecture.City_Lamp`;
- new `farmland.Plan.width`, `height`, and `tradition` fields;
- `terrain.Project.structures`: `[256]terrain.Structure` to
  `[dynamic]terrain.Structure`;
- new `Farm_Instance.scale_x` and `scale_z` fields;
- removed `Settlement_Plan.city_plan`;
- new `story.State.quest` and `story.State.airfield_errand` fields;
- new root `Fixture.tracked_quest_node`,
  `Fixture.quest_tracking_suppressed`, and
  `Fixture.quest_tracking_revision` fields.

Supporting type additions:

- `farmland.Tradition`;
- `quest.Node_ID`;
- `quest.State`;
- `quest.Status`;
- `story.Airfield_Errand_Stage`.

The new quest graph is durable game progress: `quest.State` owns its definition
identity, node statuses, completion counts, activation/completion sequences,
and revision. Tracked node, suppression choice, and the last-observed quest
revision preserve the designer's exact tracking situation. New
`flight_throttle_overlay_fade_started_at`, `dialogue_session`,
`story_catalog`, `story_quest_catalog`, and quest-log tab/focus/scroll fields
are correctly tagged `fixture:"-"` and absent from the candidate.

Quest migration is not a zero-fill operation. Frozen v1 legacy romance,
repair, repeat-delivery, and active-delivery state must seed the exact version-2
quest graph. The migration must freeze version-2 definition identity, 13 node
IDs, statuses, counts, sequence values, and revision rather than call a
future-mutable current catalog helper. It must project
`story.State.airfield_errand`, initialize `tracked_quest_node` to
`quest.no_node` (`-1`), initialize suppression deliberately, and set the
tracking revision consistently with the migrated quest revision.

Verification after conflict resolution:

- six exact historical-parser tests pass with zero leak diagnostics;
- double history generation, history check, and generated-v1 compilation pass
  with both immutable hashes unchanged;
- `make check` passes;
- `make fixture-codec-test` passes its real-fixture round trip with zero leaks:
  `size_of(Fixture)=47,880,616`, payload `28,662,517`, container `28,662,549`,
  encode about `879.473 ms`, decode about `921.406 ms`;
- `make test` executes 483 tests: 482 pass with zero leak diagnostics and only
  the expected frozen production-manifest assertion fails;
- `make fixture-schema-check` fails only at the first audited
  `architecture.City_Plan.structures` crossing.

## Fourth rebased baseline audit — 2026-07-27

The resolved working copy `mwytpkmk` has no Jujutsu conflicts and now sits on
`twtstlvt` (`renderer: grow frame geometry buffers`). The parent delta since
`mrtyuwru` is limited to renderer-buffer growth in `src/main.odin`,
`src/world_renderer.odin`, `src/dynamic_shadows.odin`,
`src/markov_marina_lab.odin`, and `src/tweaks.odin`. It does not alter the
fixture root or any reachable persisted type.

An isolated copied-source generation confirms that the complete current graph
still differs from frozen version 1 by exactly:

- `architecture.City_Plan.structures`: `[256]terrain.Structure` to
  `[dynamic]terrain.Structure`;
- `architecture.City_Plan.parcels`: `[256]architecture.City_Parcel` to
  `[dynamic]architecture.City_Parcel`;
- `architecture.City_Plan.alleys`: `[128]architecture.City_Alley` to
  `[dynamic]architecture.City_Alley`;
- `architecture.City_Plan.lamps`: `[256]architecture.City_Lamp` to
  `[dynamic]architecture.City_Lamp`;
- new `farmland.Plan.width`, `height`, and `tradition` fields;
- new two-value `farmland.Tradition`;
- `terrain.Project.structures`: `[256]terrain.Structure` to
  `[dynamic]terrain.Structure`;
- new `Farm_Instance.scale_x` and `scale_z` fields;
- removal of `Settlement_Plan.city_plan`.

The four city-plan collections are durable through
`Fixture.architecture_city_plan`; the terrain collection and all five farm
fields are also durable. `Settlement_Plan.city_plan` was historically unwired:
current code operates on the promoted top-level architecture plan and passes
city plans explicitly into the settlement pipeline. Its removal must still be
acknowledged by the version-1 migration. A nonempty historical value must not
be discarded silently.

Frozen version 1 remains 1,340 lines with SHA-256
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
The isolated current candidate is 1,347 lines with SHA-256
`3c6b64717f9036a19d40684bf5feb1b7ad3e4ddf01fb3c3f81a406d92a068e67`.
Generation occurred only in a temporary copied tree; the real manifest and
version constant were not changed.

Current verification after this rebase:

- both exact 3CR portable tests pass with memory tracking and no leak
  diagnostics;
- `make fixture-codec-test` passes its one real-fixture test with no leaks:
  `size_of(Fixture)=47,874,024`, payload `28,658,680`, container
  `28,658,712`, encode about `820.528 ms`, decode about `858.480 ms`;
- `make check` passes;
- `make test` runs 445 tests and has exactly one failure, the expected frozen
  production-manifest assertion;
- `make fixture-schema-check` fails at the first real delta,
  `architecture.City_Plan.structures`, as designed.

M3CR is not accepted. A disposable real-type probe using
`Node :: struct { children: [dynamic]Node }` proves that portable encode
succeeds and emits 89 bytes, then portable decode rejects those same bytes as
`Invalid_Metadata` because the by-value type graph contains a cycle. Discovery
reuses an existing handle but encode never runs the graph validator used by
decode.

The focused tests also leave four contract gaps:

- dynamic-to-fixed uses equal counts and never proves that excess elements are
  validated and skipped;
- the counting allocator only asserts a lower bound and does not prove
  allocation count is independent of element count;
- config validation newly rejects `max_array_elements > max(u32)` even though
  both fixed metadata and dynamic counts use `u64`; this changes prior valid
  configuration without a wire reason;
- the real fixture seeds only `architecture_city_plan.structures`, not the new
  `parcels`, `alleys`, and `lamps` dynamic arrays.

Repair only these findings in 3CR2. Do not bump the schema or begin migration
work until its acceptance gates pass.

## Third rebased baseline audit — 2026-07-27

The resolved working copy has no Jujutsu conflicts and now sits on
`wmptmtrk`. The latest upstream stack changed one durable container shape in
addition to the farmland additions already reported after 3C.

A current manifest generated in an isolated copied source tree differs from
frozen version 1 by exactly:

- `farmland.Plan.width`, `height`, and `tradition`;
- the new two-value `farmland.Tradition` enum;
- `Farm_Instance.scale_x` and `scale_z`;
- `terrain.Project.structures` changing from
  `[256]terrain.Structure` to `[dynamic]terrain.Structure`.

All five farm fields are durable. Width, height, and tradition drive validation
and rendering; instance scale drives placement bounds and rendering. The
structure collection is authored project state and cannot be excluded. The
new root `terrain_revision`, circulation plan/cache, dynamic circulation
structure scratch array, and scratch count are correctly excluded with
`fixture:"-"` and therefore do not appear in the schema delta.

The frozen version-1 manifest remains 1,340 lines with SHA-256
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
The isolated current graph is 1,348 lines. It was generated only in a temporary
tree; the frozen manifest and version constant were not changed.

Current verification:

- `make check` passes;
- `make test` runs 436 tests and has exactly one failure, the production schema
  graph assertion;
- `make fixture-schema-check` fails at the first farmland field, as designed;
- `make fixture-codec-test` now traps because its source builder indexes the
  new zero-length dynamic `project.structures` without allocating it;
- static inspection shows portable `hs` has no
  `rt.Type_Info_Dynamic_Array` kind, so fixing only that test allocation would
  next fail portable discovery;
- the 3C adapter files themselves did not change during the latest rebase.

Do not amend version 1 and do not hide these durable fields with exclusion
tags. First repair portable dynamic-array support and the real-fixture proof in
3CR. Then record schema version 2 and its explicit version-1 migration in 3D.

## Second rebased baseline audit — 2026-07-27

The rebase is conflict-free, but a large world-simulation change inserted new
fields at the old monolithic `Editor` location. Because the structural split
already occupied that location, every new upstream field landed in `Fixture`
without a fixture-policy decision. The schema tool correctly described those
fields, growing the draft manifest from 789 to 1,471 lines; the manifest is
therefore internally consistent but not yet a trustworthy persisted-state
contract.

Keep these newly added fields persisted:

- `foliage_hedgerow_mode`;
- authored marina state and brush radius;
- placed farms and farm brush radius;
- player scurry simulation state;
- `flight_camera`, boat traffic, and borrowed-dinghy state;
- lab/playground identity, generated settlement state, diagnostic selection,
  and shadow-lab settings;
- `gerta_position` and durable `story_state`.

Exclude these fixture-owned derived or active-session fields with
`fixture:"-"`:

- circulation plan, revision, and validity cache;
- marina preview plan, coordinates, reroll variation, validity, status,
  suitability, and attempt count;
- farm preview instance, validity, scores, coordinates, project revision, and
  reroll seed offset;
- generated default-marina plans and count;
- the complete cinematic transaction, including sampled focal length, authored
  temporary shots/script, restore pose, pending flag, and active flag;
- flight-throttle HUD value, wall-clock timestamp, and initialization flag;
- active dialogue resident;
- customization slider/preview drag state and preview yaw;
- `map_time`, which is overwritten from the process clock every frame.

Move these session-only fields to root `Editor`:

- `main_menu_active` and `main_menu_focus`;
- `console`.

Material evidence:

- `editor_circulation_plan` recomputes the circulation plan from `project`
  revision;
- marina and farm preview procedures regenerate their values from cursor,
  project, and reroll input;
- default marinas are deterministically generated from the current project;
- cinematic `Script.shots` is explicitly a borrowed slice and playback holds a
  pointer to that script, so partial cinematic persistence cannot be valid;
- dialogue conversation state is already excluded, leaving
  `dialogue_resident` meaningless by itself;
- main menu and console are process-session UI, not a level-designer
  playground;
- `map_time` is assigned from `rl.GetTime()` on every frame.

Verification after the rebase:

- no Jujutsu conflicts are present;
- `make fixture-schema-check` passes;
- two consecutive `make fixture-schema-generate` runs are no-ops;
- `make check` passes;
- `make test` passes all 377 tests with memory tracking enabled and no leak
  warnings;
- all six schema tests now invoke the temporary allocator guard in their own
  lexical procedure, so milestone 2R2 is accepted;
- at this audit, milestone 2 remained unaccepted pending milestone 2R3; that
  repair and its scope cleanup are now accepted below.

## Rebased baseline audit — 2026-07-27

The original split is present in change `lkolpltw`. A later rebase added fields
at the old `Editor` boundary and temporarily placed runtime-only state inside
`Fixture`. Milestone 1R repaired that layout before schema version 1.

Material findings:

- capture controls, benchmark flags, structure/terrain undo histories, terrain
  file-status feedback, and saved-revision bookkeeping had landed in
  `Fixture`; milestone 1R returned them to root `Editor`;
- `formation_brush_group_id` is new and correctly marked `fixture:"-"`;
- `petal_effects` is new fixture-relevant particle state and remains persisted,
  consistently with `vehicle_effects` and `wing_trails`;
- `Editor_UI_State.active_slider` and `debug_key_down` were nested transient
  fields without `fixture:"-"`; milestone 1R tagged them, and exclusion must
  work throughout the reachable type graph;
- hot save clears pilot, car, Postale, Libellula, and aircraft links, but hot
  load does not rebuild them; fixture rehydration and hot reload need one shared
  detach/rebind contract;
- terrain now uses six clipmap levels and stores per-level origins. The schema
  manifest must resolve constant-backed fixed-array lengths rather than hashing
  only field spelling;
- `packages/story` defines durable campaign `story.State`, but no live owner is
  reachable from `Editor`. Schema version 1 cannot silently imply story
  coverage: integration must either add the live state to `Fixture` or record
  that the package remains unwired;
- `zelda-engine` is now vendored at `zelda-engine/`; it remains product-neutral;
- `make check` passes with the current toolchain;
- the rebased test compile failures were repaired in change `qkzxpuuo`;
  `make test` now passes all 319 tests.

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
11. Do not add fixture file I/O, migration behavior, schema parsing, or new UI.
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

- The structural split is integrated in change `lkolpltw`.
- `make check` passes.
- The rebase repair is present in the current working change.
- `make test` passes all 319 tests.
- Milestone 1 and milestone 1R are accepted.

## Milestone 1R — Repair the rebased `Editor` split

### Goal

Restore the intended schema boundary and audit every field added or structurally
changed by the rebase before schema version 1 is established.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, `Fixture`, `Editor`, and every
   reachable struct touched by the rebase.
2. Confirm a clean working copy with `jj status`; inspect all resulting diffs
   with `jj diff --git`.
3. Move these fields from `Fixture` back to root `Editor`, preserving names,
   types, order within each logical group, and all existing promoted call sites:

   - `capture_world_only`;
   - all player-pose capture flags;
   - `capture_bougainvillea_seed_enabled`;
   - `capture_bougainvillea_structure_id`;
   - `capture_bougainvillea_seed`;
   - `benchmark_ground_grass_disabled`;
   - `structure_undo`, `structure_redo`, and both counts;
   - `terrain_undo`, `terrain_redo`, and both counts;
   - `terrain_file_status`;
   - `terrain_file_status_until`;
   - `terrain_saved_revision`.

4. Keep `formation_brush_group_id` in `Fixture` with `fixture:"-"`.
5. Keep `petal_effects` in persisted `Fixture` state. Do not independently
   reclassify the existing particle groups during this repair.
6. Mark `Editor_UI_State.active_slider` and `debug_key_down` with
   `fixture:"-"`; keep the collapsed-panel preferences persisted.
7. Audit every type reachable from persisted `Fixture` fields for:

   - raw, typed, procedure, C, GPU, physics, audio, allocator, and dylib-owned
     pointers or handles;
   - dynamic data whose ownership cannot survive replacement;
   - derived caches and active input/gesture state;
   - fixed arrays whose lengths come from constants;
   - nested fields needing `fixture:"-"`.

   Record each exception in this plan or tag it in source. Do not rely on a
   top-level tag to hide nested transient fields.
8. Audit durable state introduced by the rebase but not owned by `Editor`.
   Resolve `story.State` explicitly before schema version 1: add it to
   `Fixture` only when it becomes live game state; otherwise record it as
   currently unwired and out of the serialized graph.
9. Do not edit vendored `zelda-engine` to encode Adriatic fixture policy.
10. Do not add fixture I/O, migration code, or hot-load pointer fixes in this
    milestone.
11. Format changed Odin files, run `make check`, and run `make test`. All checks
    and all tests must pass.

### Acceptance criteria

- Every capture, benchmark, undo/redo, file-status, and revision field listed
  above is owned by root `Editor`.
- New fixture-relevant state is deliberately persisted or explicitly excluded.
- Nested transient UI state carries `fixture:"-"`.
- `Editor` still exposes fixture fields through `using fixture: Fixture`.
- Existing `editor.field` call sites remain unchanged.
- Hot reload still builds and retains its current behavior; lifecycle repair is
  deferred to milestone 4.
- `make check` passes and fixture changes add no test failures.
- Full `jj diff --git` contains only the boundary repair.

## Milestone 2 — Establish schema version 1

### Goal

Freeze a trustworthy, source-derived schema for the current persisted
`Fixture` graph. This milestone produces schema metadata and validation only:
no fixture payload codec, migration generator, or editor UI.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, `src/main.odin`,
   `src/editor_ui.odin`, `packages/hs`, the reachable gameplay structs, and the
   installed `core:odin/parser` and `core:odin/ast` sources.
2. Inspect `jj status` and the complete `jj diff --git`. Preserve the accepted
   milestone-1 changes already in the working copy. Do not rewrite, squash, or
   commit unrelated work.
3. Before production code, make a minimal parser spike that parses `src` and
   proves all of these against the actual installed Odin API:

   - locate the `Fixture` `Value_Decl`;
   - obtain its `ast.Struct_Type`;
   - print one field name, field type node kind, tag token text, and source
     position;
   - locate `terrain.CLIPMAP_LEVELS` through the `terrain` import.

   Delete the spike after the production test covers it. Do not guess AST
   layouts or copy examples for a different Odin revision.
4. Close the known pointer hole before freezing schema version 1. Add
   `fixture:"-"` to these product-local relationship fields:

   - `vehicles.Character.vehicle`;
   - `vehicles.Vehicle.driver`;
   - `vehicles.Aircraft_Slot.vehicle`.

   These are live links rebuilt during milestone 4, not persisted data. Audit
   the completed reachable graph and fail schema generation if any other raw,
   typed, multi, C, procedure, or relative pointer remains reachable without
   exclusion. Do not edit `zelda-engine` to add Adriatic policy.
5. Add `FIXTURE_SCHEMA_VERSION :: 1` beside the `Fixture` schema root. The
   schema tool must read this declaration from source; do not duplicate the
   current version inside the tool.
6. Keep implementation small:

   - one importable `packages/fixture_schema` library containing parsing,
     resolution, canonicalization, and comparison;
   - one thin `tools/fixture_schema` CLI;
   - focused tests in `tests/fixture_schema_test.odin`;
   - testdata only where an in-memory/synthetic AST would be more complicated.

   Start with one library source file and split only when distinct ownership is
   obvious. Do not build a general Odin compiler.
7. Model packages with stable logical IDs, never absolute paths:

   - `adriatic:src` for the schema root;
   - `adriatic:packages/<name>` for repository packages;
   - `zelda_engine:<collection-path>` for the vendored collection;
   - `core:<path>` only if a reachable declared type requires it.

   The CLI receives the repository root explicitly. The default
   `zelda_engine` collection root is
   `<repo>/zelda-engine/packages`. Absolute checkout paths, timestamps, map
   iteration order, and machine-specific compiler paths must never enter the
   manifest.
8. Parse packages lazily with `parser.parse_package_from_path`. Build a symbol
   index for type declarations and integer constants across every file in each
   reached package. Resolve:

   - same-package identifiers;
   - explicit import aliases;
   - default import package names;
   - relative imports;
   - `zelda_engine:` collection imports;
   - qualified selectors such as `terrain.Project`;
   - alias chains such as `canvas2d.Color -> render2d.Color`.

   Detect missing symbols, duplicate declarations, bad imports, and alias/type
   cycles. Report logical package, file, line, and field/type path.
9. Walk only the graph reachable from `adriatic:src.Fixture`. For every struct
   field, parse the tag token as an actual Odin struct-tag string. Use
   `reflect.struct_tag_lookup(..., "fixture")`; do not use substring matching.
   A value of `"-"` excludes the field and its entire subtree. Excluded fields
   must not require their type or constants to resolve.
10. Canonicalize the current graph with explicit node kinds. Support and record
    every form needed by the graph:

    - built-in scalar types and `string`;
    - named, aliased, and `distinct` types;
    - structs, including field order, names, `using`, and non-fixture tags;
    - enums with resolved implicit and explicit values;
    - unions with ordered variants and relevant modifiers;
    - fixed arrays with resolved lengths;
    - slices and dynamic/fixed-capacity dynamic arrays;
    - maps, matrices, bit sets, and anonymous composite types if reached.

    Reject pointers and unsupported forms with a diagnostic. Never emit an
    opaque node, silently skip syntax, or use source spelling as a substitute
    for resolved schema.
11. Implement a checked integer constant evaluator for array lengths and enum
    values. It must handle integer literals, parentheses, qualified and
    unqualified constants, unary signs, casts to integer types, and checked
    integer arithmetic/bitwise operations used by the current graph. Detect
    overflow, division by zero, non-integer expressions, and constant cycles.
    Required current sentinels include:

    - `terrain.CLIPMAP_LEVELS == 6`;
    - `particle_systems.MAX_PETAL_PARTICLES == 192`;
    - `VEHICLE_PAINT_TEXTURE_BYTE_COUNT ==
      VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_HEIGHT * 4`.

12. Emit a simple canonical UTF-8 line format at
    `fixtures/schema/v0001.fixture-schema`. This metadata is text for stable
    review and migration diffs even though fixture save files will be binary.
    Include:

    - format version;
    - fixture schema version;
    - root logical type;
    - sorted type records;
    - ordered members within each type;
    - resolved container dimensions and enum values.

    Escape names/tags unambiguously. Sort every map-derived collection before
    output. Do not include comments, whitespace trivia, source offsets, or
    absolute paths.
13. Provide exactly two CLI operations:

    - `generate`: write the manifest only when its versioned path does not
      exist; identical existing output is a no-op; refuse to overwrite a
      different historical manifest;
    - `check`: generate in memory and byte-compare with the manifest named by
      `FIXTURE_SCHEMA_VERSION`; missing or different output fails with the
      first useful type/field difference and instructions to bump the version.

    Write new manifests through a temporary file plus rename. Do not add a
    force-overwrite escape hatch.
14. Add explicit Make targets `fixture-schema-generate` and
    `fixture-schema-check`, passing the repository and collection roots. Do not
    wire schema validation into the normal `check` target yet; that guardrail
    belongs to milestone 9.
15. Tests must prove:

    - two generations are byte-identical;
    - the committed version-1 manifest matches current source;
    - a persisted additive field with version 1 makes `check` fail;
    - a root `Editor` field change does not change output;
    - direct and nested `fixture:"-"` changes do not change output;
    - excluded pointer fields are absent;
    - an unexcluded pointer fails with its field path;
    - qualified constants and arithmetic resolve to numeric dimensions;
    - enum implicit/explicit values and aliases are stable;
    - import, symbol, constant, and alias cycles fail cleanly;
    - output contains no repository absolute path;
    - current sentinels `project`, `petal_effects`, and the persistent vehicle
      paint arrays exist, while `structure_placing`, `active_slider`, and the
      three relationship pointers do not.

16. Generate `v0001.fixture-schema` only after the tests pass. Inspect it for
    suspicious runtime handles, unresolved spellings, and accidental engine
    internals. A small audited allowlist of built-in terminal types is fine;
    an allowlist that suppresses unresolved user types is forbidden.
17. Format changed Odin files. Run:

    - `make fixture-schema-check`;
    - `make check`;
    - `make test`;
    - the schema generator twice, confirming the second run is a no-op.

18. Inspect the full `jj diff --git`. Do not commit until every acceptance
    criterion passes.

### Acceptance criteria

- `Fixture` has one source-owned schema version constant set to 1.
- A committed deterministic version-1 manifest describes the full reachable
  persisted graph.
- Re-running the tool without source changes produces identical output.
- A persisted field change without a version bump fails validation.
- A root-only or `fixture:"-"` change does not alter the fixture schema.
- Changing a constant-backed persisted array length alters the schema.
- Nested `fixture:"-"` fields and their type subtrees are absent.
- Reachable relationship pointers are excluded; any new reachable pointer
  fails validation.
- Reachable vendored engine types resolve without modifying the engine.
- Diagnostics identify logical type/field and source position.
- `make fixture-schema-check`, `make check`, and `make test` pass.

### Verification status — 2026-07-27

- The version constant, schema walker, CLI, Make targets, pointer exclusions,
  and draft version-1 manifest exist.
- `make fixture-schema-check` passes.
- Running `fixture-schema-generate` twice is a no-op.
- `make check` passes.
- `make test` passes all 321 tests.
- Formatting checks pass.
- Milestone 2 is not accepted yet. The implementation has only two schema
  tests and does not cover most required failure behavior.
- Integer parse, overflow, division/modulo-by-zero, negation, and shift failures
  can return `ok=false` without recording a builder error. A containing type
  then records `type=invalid`, while `build_manifest` only checks
  `len(b.errors)` and can report success. This violates fail-closed schema
  generation.
- `Symbol` does not retain its name/value index. Multi-name declarations always
  resolve through `values[0]`.
- Default import aliases are inferred from directory basename rather than the
  parsed target package name.
- Several AST modifiers are silently omitted from canonical form, including
  struct alignment and `is_all_or_none`/`is_simple`. Reached syntax must be
  encoded or rejected, never ignored.
- The test named `fixture_schema_check_reports_unversioned_change` only appends
  text to an already generated manifest and tests string comparison. It does
  not prove that a source schema change with version 1 is rejected.

## Milestone 2R — Make schema generation fail closed

### Goal

Repair the schema tool and prove its negative behavior before version 1 becomes
historical input to migrations. Do not begin the fixture payload codec while
the schema validator can silently accept an invalid type.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, the complete schema
   implementation, its two tests, and the installed AST definitions for every
   node the tool handles.
2. Inspect `jj status` and the full `jj diff --git`. Preserve the accepted
   editor split and existing schema work. The current version-1 manifest is an
   unaccepted draft and may be regenerated in this working change if canonical
   output legitimately changes.
3. Add a tiny synthetic-repository test harness before changing production
   behavior. It must create isolated `src`, package, collection, and manifest
   paths under a test temporary directory, write minimal Odin source, call the
   real public schema API, and clean up automatically. Do not mutate production
   source during tests.
4. First reproduce the fail-open bug with a persisted array length that cannot
   evaluate, such as division by zero or checked overflow. The test must prove
   all of these:

   - `build_manifest` reports failure;
   - the diagnostic contains the logical fixture field path and source line;
   - no successful manifest containing `type=invalid` is returned.

   Keep this regression test after the fix.
5. Give `Builder` one authoritative failure state. Every diagnostic sets it.
   Every failed type or constant operation must either append one precise
   diagnostic or propagate an existing failure. `build_manifest` must fail if:

   - the builder failed;
   - any reachable type representation failed;
   - any record remains incomplete;
   - the version declaration is missing, mutable, non-integer, or invalid.

   Do not detect failure by searching emitted text for the word `invalid`.
   Invalid records must never reach emission.
6. Audit every `return ..., false` in constant evaluation. Add diagnostics for
   integer parse failure, signed overflow, divide/modulo by zero, invalid
   shifts, and negating `I64_MIN`. Avoid duplicate follow-on diagnostics when a
   child expression already failed.
7. Fix symbol identity. Store the declaration name index in `Symbol` and use
   the corresponding value when resolving a constant or alias. Before coding,
   compile a minimal Odin example to confirm legal multi-name constant syntax.
   Reject unsupported arity/tuple forms explicitly instead of choosing
   `values[0]`.
8. Fix default imports. For relative and `zelda_engine:` imports without an
   explicit alias, parse the target package and use its declared package name.
   Keep explicit aliases unchanged. Detect duplicate aliases instead of
   overwriting the import map. Core/base/vendor imports that cannot be resolved
   by this tool may remain unloaded until reached, but reaching one must produce
   a clear unsupported-import diagnostic.
9. Audit every handled AST type for silently discarded schema-relevant data.
   For each modifier, either include a canonical value or fail with source
   context. At minimum cover:

   - struct `align`, `min_field_align`, `max_field_align`,
     `is_all_or_none`, and `is_simple`;
   - union alignment and kind;
   - enum base type, `is_using`, implicit values, and explicit values;
   - tags/modifiers on array and dynamic-container type nodes;
   - bit-field members and widths;
   - anonymous type modifiers.

   Supporting syntax not reachable from the current fixture graph is optional;
   silently accepting it is forbidden.
10. Replace the weak unversioned-change test with source-level tests. Required
    synthetic cases:

    - same source generates identical bytes twice;
    - adding a persisted field while version remains 1 differs from the stored
      version-1 manifest and fails check behavior;
    - adding/changing a root `Editor` field leaves fixture output unchanged;
    - direct and nested `fixture:"-"` fields and their unresolved subtrees do
      not affect output;
    - an unexcluded pointer fails with its full field path;
    - excluded relationship pointers disappear;
    - qualified constants, arithmetic, and multi-name constants resolve to the
      correct array lengths;
    - implicit and explicit enum values are canonical;
    - an alias chain through a directory whose name differs from its declared
      package name resolves correctly;
    - duplicate imports, missing symbols, constant cycles, alias cycles,
      overflow, zero division, and unsupported reached syntax fail;
    - output from two different temporary checkout paths is identical and
      contains neither absolute path.
11. Keep a production-graph integration test that builds the real fixture
    schema and checks current sentinels. Also read
    `fixtures/schema/v0001.fixture-schema` and compare it byte-for-byte with the
    generated result.
12. Reinspect the draft manifest. It must contain no `invalid`, absolute path,
    runtime relationship pointer, root `Editor` state, or excluded transient
    field. It must still contain the resolved current sentinels:

    - six terrain clipmap levels;
    - 192 petal particles;
    - 8,388,608 vehicle-paint bytes;
    - the canvas color alias chain.

13. If canonical output changes, remove only the unaccepted draft
    `v0001.fixture-schema` and regenerate it. Do not bump to version 2; version
    1 has not shipped or become a migration source yet. Confirm the second
    generation is a no-op.
14. Format changed Odin files and run:

    - `make fixture-schema-check`;
    - `make check`;
    - `make test`;
    - `make fixture-schema-generate` twice.

15. Inspect the complete `jj diff --git`. Do not add codec, fixture file I/O,
    migrations, editor UI, or normal-check/CI integration.

### Acceptance criteria

- No reachable type or constant failure can produce a successful manifest.
- No emitted type reference can be incomplete or invalid.
- Multi-name declarations resolve by their own value slot.
- Default imports use the declared package name.
- Every reached schema-relevant AST modifier is encoded or rejected.
- Synthetic negative tests exercise every promised failure class.
- A real-source test compares generated schema with the draft version-1 file.
- The version-1 manifest contains only logical package IDs and audited persisted
  state.
- Generator/check behavior remains deterministic and overwrite-safe.
- `make fixture-schema-check`, `make check`, and all tests pass.

### Verification status — 2026-07-27

- Fail-closed propagation, indexed declaration values, file-scoped imports,
  declared package names, modifier handling, and synthetic negative tests are
  implemented.
- The production graph matches the draft manifest byte-for-byte.
- Schema check and two no-op generations pass.
- `make check` passes.
- All 325 test assertions pass functionally.
- Milestone 2R is not accepted because every schema test reports allocator
  leaks. The combined test run emitted roughly 28 MB of leak diagnostics.
- Root cause: `test_setup` calls
  `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()`. Its scope-exit lifetime ends
  when `test_setup` returns, before the test performs parser allocations.

## Milestone 2R2 — Make schema tests memory-clean

### Goal

Finish schema version 1 with a clean test process. This is a scoped allocator
lifetime repair, not permission to redesign the parser or begin the codec.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan,
   `tests/fixture_schema_test.odin`, and the implementation of
   `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD`.
2. Inspect `jj status` and the complete `jj diff --git`. Preserve all existing
   fixture and schema work.
3. Reproduce the leak warnings with `make test` and confirm they are attributed
   to the schema tests.
4. Remove the misleading `test_setup` lifetime abstraction. In every schema
   `@(test)` procedure, before any allocation:

   ```odin
   context.allocator = context.temp_allocator
   runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
   ```

   The guard must be invoked in the lexical test procedure so its implicit
   scope exit resets the arena after that test. Do not hide it in another
   procedure.
5. Do not individually free the parser AST unless the correctly scoped arena
   guard still leaves a verified allocation outside the arena. Bulk temporary
   ownership is the intended simple model for these short schema builds.
6. Run the schema tests and then the full suite. Passing assertions are
   insufficient: output must contain no schema-test `[WARN]` leak blocks.
7. Confirm temporary synthetic repositories are still removed on both success
   and assertion failure paths.
8. Run:

   - `make fixture-schema-check`;
   - `make fixture-schema-generate` twice;
   - `make check`;
   - `make test`.

9. Format the changed test file and inspect the full `jj diff --git`. Do not
   change production schema behavior, the manifest, codec code, migrations,
   editor UI, or CI wiring.

### Acceptance criteria

- All schema tests invoke the arena guard in their own lexical procedure.
- The schema tests produce no allocator leak warnings.
- The full test run produces no new memory warnings.
- All 325 or more tests pass.
- Schema check and repeated generation remain deterministic and clean.
- Production source and `v0001.fixture-schema` are unchanged by this repair.

### Verification status — 2026-07-27

- All six schema tests set the temporary allocator and invoke
  `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()` in their own lexical procedure.
- `make test` passes all 377 tests with memory tracking enabled.
- The test process reports no leak warnings.
- Schema check, two no-op generations, and `make check` pass.
- Milestone 2R2 is accepted.

## Milestone 2R3 — Repair the post-rebase fixture boundary

### Goal

Classify state introduced by the latest rebase before draft schema version 1 is
frozen. Remove derived, borrowed, wall-clock, active-input, and process-session
state from the persisted graph while retaining authored and reproducible
playground state.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, the complete `Fixture` and
   root `Editor`, and the owning procedures for circulation, marina/farm
   previews, default marinas, cinematics, story dialogue, console, main menu,
   customization, and the flight-throttle overlay.
2. Inspect `jj status` and the full `jj diff --git`. Preserve all accepted
   editor-split and schema-tool work. Do not commit, squash, or rewrite
   unrelated work.
3. Add `fixture:"-"` to all three circulation cache fields:

   - `circulation_plan`;
   - `circulation_revision`;
   - `circulation_plan_valid`.

4. Add `fixture:"-"` to the complete marina preview transaction:

   - `marina_preview_plan`;
   - `marina_preview_valid`;
   - `marina_preview_x` and `marina_preview_z`;
   - `marina_preview_variation`;
   - `marina_brush_status`;
   - `marina_brush_suitability`;
   - `marina_brush_attempts`.

   Keep `marina_paint_mode`, `marina_authored`,
   `marina_authored_plan`, and `marina_brush_radius` persisted.
5. Add `fixture:"-"` to the complete farm preview transaction:

   - `farm_preview`;
   - `farm_preview_valid`;
   - all three preview scores;
   - `farm_preview_x` and `farm_preview_z`;
   - `farm_preview_revision`;
   - `farm_preview_seed_offset`.

   Keep `farm_paint_mode`, `farm_brush_radius`, `farms`, and `farm_count`
   persisted.
6. Add `fixture:"-"` to `default_marinas` and `default_marina_count`. These
   are deterministic derived plans, not authored marina state. Do not move or
   exclude the authored marina plan.
7. Keep `cinematic_playback` excluded and add `fixture:"-"` to every other
   cinematic transaction field:

   - `cinematic_focal_length`;
   - `story_cinematic_shots`;
   - `story_cinematic_script`;
   - `story_cinematic_restore_pose`;
   - `story_meeting_cinematic_pending`;
   - `story_cinematic_active`.

   The script contains a borrowed `[]Shot`; do not attempt to make that
   relationship persistent in this repair.
8. Add `fixture:"-"` to all three flight-throttle overlay fields. The
   `changed_at` value is a process-clock timestamp and must never enter a
   fixture.
9. Keep `story_state` and `gerta_position` persisted. Add `fixture:"-"` to
   `dialogue_resident`, because its owning active conversation is already
   excluded.
10. Move `main_menu_active`, `main_menu_focus`, and `console` from `Fixture` to
    root `Editor`. Preserve their existing names and promoted call sites; do
    not rewrite uses.
11. Keep mouse appearance and scarf state persisted. Add `fixture:"-"` to:

    - `customization_slider_drag`;
    - `customization_preview_dragging`;
    - `customization_preview_drag_x`;
    - `customization_preview_yaw`.

12. Add `fixture:"-"` to `map_time`. It is a presentation clock assigned from
    `rl.GetTime()` every frame, not reproducible saved state.
13. Deliberately retain these new persisted groups; do not reclassify them
    merely because they came from the rebase:

    - `foliage_hedgerow_mode`;
    - placed farms and authored marina state;
    - player scurry simulation values;
    - `flight_camera`;
    - `boat_traffic` and `marina_dinghy_borrowed`;
    - lab/playground flags, target, settlement plan and diagnostics, and shadow
      lab controls;
    - `story_state`.

14. Extend the production-graph schema test. It must prove the newly excluded
    names and `Game_Console` type are absent, while representative durable
    additions remain present: `marina_authored_plan`, `farms`, `boat_traffic`,
    `settlement_plan`, and `story_state`. Keep existing sentinels.
15. Do not change `FIXTURE_SCHEMA_VERSION`. Version 1 is still an unaccepted
    draft. After source tests demonstrate the intended graph, remove only the
    draft `fixtures/schema/v0001.fixture-schema`, regenerate it, run generation
    again, and confirm the second run is a no-op.
16. Inspect the regenerated manifest. It must contain no circulation/default
    marina cache, preview transaction, cinematic transaction, throttle HUD,
    dialogue session, main-menu, console, customization drag, `map_time`,
    pointer relationship, absolute path, or `invalid` record.
17. Format only touched Odin files and run:

    - `make fixture-schema-check`;
    - `make fixture-schema-generate` twice;
    - `make check`;
    - `make test`.

18. Inspect the complete `jj diff --git`. Do not add fixture payload I/O,
    codec behavior, migrations, editor save/load UI, rehydration, or
    normal-check/CI wiring.

### Acceptance criteria

- Every derived/session field listed above is excluded or returned to root
  `Editor` exactly as specified.
- Authored and reproducible new playground state remains persisted.
- No existing promoted `editor.field` call site needs rewriting.
- The production schema test locks both exclusions and durable additions.
- Draft schema version 1 is regenerated from the repaired graph and is
  substantially smaller than the current 1,471-line draft.
- Schema check and repeated generation are deterministic.
- `make check` and all tests pass without memory warnings.
- The resulting diff contains no codec, migration, editor UI, rehydration, or
  CI implementation.

### Verification status — 2026-07-27

- Every requested `Fixture` exclusion and root `Editor` move is present.
- Production schema tests lock all requested exclusions and representative
  retained state.
- Draft version 1 is 1,340 lines and contains none of the excluded names.
- `make fixture-schema-check` passes.
- Two generations preserve SHA-256
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
- `make check` passes.
- All 377 tests pass with memory tracking and no leak warnings.
- Scope cleanup removed all 15 unrelated files and every formatter-only
  `src/main.odin` hunk. The isolated repair diff contains only fixture field
  classification, schema sentinels, and the regenerated manifest.
- Milestone 2R3 and fixture schema version 1 are accepted.

## Milestone 3A — Add a portable filtered `hs` payload

### Goal

Build a compact, self-describing binary payload that walks selected fields
instead of dumping raw struct memory. This milestone is memory-only: no fixture
container, file I/O, editor integration, migrations, or rehydration.

The existing `hs.serialize`/`hs.deserialize` hot-reload path must remain
unchanged. Its raw `SaveHeader` contains process-local slices and type IDs, its
root body includes excluded fixed arrays, and its decoder trusts input. It is
not a fixture file format.

### First codec slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, every file under
   `packages/hs`, `src/main.odin`, the version-1 manifest, and the installed
   Odin runtime/reflect definitions used by the codec.
2. Confirm M2R3 scope cleanup is complete. Inspect `jj status` and the complete
   `jj diff --git`. Do not begin codec work while unrelated formatter changes
   remain.
3. Before production code, compile tiny reflection spikes proving:

   - named and distinct types can be flattened to their base while preserving
     current field traversal;
   - `reflect.struct_tag_lookup(field.tag, "fixture")` returns `"-"` for direct
     and nested exclusions;
   - struct field offsets can read values without copying the enclosing struct;
   - current `Fixture` reaches only named/distinct values, structs, fixed
     arrays, enums, scalar primitives, and strings after exclusions.

   Delete spikes after focused tests cover them. Do not guess runtime type-info
   layouts.
4. Add a separate portable API under `packages/hs`, preferably one new
   `portable.odin` file. Do not modify legacy `serialize`, `deserialize`,
   `SaveHeader`, or hot-state call sites. Use a generic configuration rather
   than hard-coding Adriatic policy:

   ```odin
   Portable_Config :: struct {
       exclusion_tag: string,
       limits:        Portable_Limits,
   }
   ```

   Public encode/decode operations must return structured errors, never panic
   or assert on data or unsupported reachable types.
5. Give the wire format an explicit version and fixed-width little-endian
   integer encoding. Never write raw Odin structs, slices, pointers, `typeid`,
   allocator state, padding, source offsets, or machine addresses.
6. Emit one deterministic self-describing type table followed by packed value
   data:

   - type records use small integer handles local to the payload;
   - struct records store included field names and field type handles in source
     order;
   - fixed-array records store resolved count and element handle;
   - enum records store base width/sign and ordered names/values;
   - scalar records store explicit kind and width;
   - string records encode byte length followed by bytes;
   - named aliases and distinct types resolve through their base shape.

   Discovery order must be deterministic. Runtime `typeid` may be used only as
   an in-memory deduplication key and must never enter output.
7. Encode struct values in saved field order. For every struct at every nesting
   depth, parse `config.exclusion_tag`; a value of exactly `"-"` removes the
   field from both type table and value bytes. Do not zero excluded memory and
   dump it anyway.
8. Decode by validating the entire saved type table, matching saved struct
   fields to current fields by name, and recursively consuming packed values.
   Unknown saved fields must be safely skipped from saved metadata. Missing
   current fields remain zero. Decode only into caller-provided temporary,
   zeroed storage; live `Editor` mutation belongs to milestone 4.
9. Support exactly the forms reached by schema version 1:

   - booleans;
   - signed and unsigned integers/runes;
   - `f16`, `f32`, and `f64`;
   - strings;
   - enums;
   - structs;
   - fixed arrays;
   - named aliases and distinct wrappers.

   Reject pointers, `rawptr`, procedures, C strings, slices, dynamic arrays,
   maps, unions, bit fields, and any other reached form with error kind and
   logical field path. Do not silently treat unsupported values as opaque
   bytes.
10. Add checked reader/writer primitives. At minimum guard:

    - addition and multiplication overflow;
    - every cursor advance;
    - type, field, array, string, and recursion counts;
    - duplicate/zero/out-of-range type handles;
    - invalid scalar widths and enum bases;
    - invalid UTF-8 field/type names if names are required to be UTF-8;
    - output growth beyond configured maximum;
    - trailing unread bytes.

    Suggested default caps: 64 MiB payload, 4,096 type records, 65,536 fields,
    1 MiB per string, and recursion depth 256. Adjust only with measured
    version-1 evidence.
11. Tests in `tests/hs_portable_test.odin` must prove:

    - primitive, enum, string, nested struct, distinct, and fixed-array
      round-trip;
    - same value encodes byte-identically twice;
    - two values differing only in direct and nested excluded fields encode to
      identical bytes;
    - excluded field names and large excluded byte-array contents are absent;
    - an unexcluded pointer fails with its full field path;
    - an excluded pointer and excluded unsupported subtree do not block encode;
    - additive source/destination struct differences are handled without
      out-of-bounds access;
    - truncation at header, table, name, string, and body boundaries fails;
    - corrupt handles, counts, widths, lengths, enum metadata, recursion, and
      trailing bytes fail without panic;
    - configured size/count limits fail before oversized allocation;
    - temporary allocations produce no leak warnings.
12. Add a small representative binary-versus-TOML test fixture containing
    nested state and byte/float arrays. Serialize equivalent values and require
    portable `hs` output to be at most half the TOML byte count. Do not marshal
    the full 25 MiB paint array in the normal test suite.
13. Format only the new codec and test files. Run:

    - `make fixture-schema-check`;
    - `make check`;
    - `make test`.

14. Inspect the complete `jj diff --git`. This milestone may touch only the new
    portable `hs` codec, its tests, and this plan. No existing hot serializer,
    fixture container, `Fixture`, editor, manifest, or migrations.

### Acceptance criteria

- Portable output contains no process-local type IDs, pointers, slices,
  allocators, padding, or absolute paths.
- Excluded fields are absent from metadata and body, not merely zeroed.
- Current version-1 reachable forms are supported; every other reached form
  fails closed with field path.
- Decoder is bounded and returns errors for malformed data without assertion,
  panic, out-of-bounds access, or oversized allocation.
- Encoding is deterministic.
- Representative output is no more than half equivalent TOML size.
- Legacy hot reload remains byte-for-byte untouched.
- Schema check, build, and all tests pass without leak warnings.

### Verification status — 2026-07-27

- The isolated 3A diff contains only `packages/hs/portable.odin` and
  `tests/hs_portable_test.odin`; legacy hot reload, `Fixture`, the manifest,
  container work, migrations, and editor integration are untouched.
- The format is explicitly versioned, manually little-endian, deterministic in
  the exercised cases, self-describing, filtered at every struct depth, and
  fail-closed for unsupported reached types.
- `make fixture-schema-check` and `make check` pass.
- All 386 tests pass with memory tracking and no reported leaks.
- Two schema generations preserve SHA-256
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
- The passing memory result is not valid ownership evidence: every new codec
  test replaces the tracked allocator with `context.temp_allocator`.
  `portable_encode` retains its discovery map, type/field arrays, table bytes,
  and body bytes; `portable_decode` retains parsed type/field arrays. Error
  exits can also retain partially allocated buffers.
- Generic `hs` currently defaults `exclusion_tag` to `"fixture"`. This embeds
  Adriatic product policy in the generic codec instead of requiring the
  product adapter to opt into it.
- Array encode, decode, and skip construct a formatted path string for every
  element. Version 1 contains
  `[3][8388608]u8` paint state, so one fixture walk would create more than 25
  million temporary path strings.
- Array decode/skip loops do not stop after the first reader error. A malformed
  large count, especially through a cyclic saved type handle, can continue
  millions of formatted iterations after failure. The parser also accepts
  cyclic by-value type graphs and enum bases that point to non-scalar types.
- Limit validation permits values wider than the header's `u32` lengths, then
  narrows counts and byte lengths with unchecked casts.
- The size test builds ad hoc text with one synthetic key per array element; it
  does not serialize the equivalent value with the repository TOML codec.
- Corruption coverage omits cycles, invalid enum-base handles, oversized array
  work, several scalar forms, and tracked-allocator ownership. Several
  mutation branches can silently skip their assertion if the target record is
  not found.
- Milestone 3A is not accepted. Milestone 3AR is the only active implementation
  work; 3B remains blocked.

## Milestone 3AR — Repair and harden the portable `hs` payload

### Goal

Keep the 3A format and public separation, but make the implementation genuinely
generic, bounded on hostile bytes, usable on the real 25 MiB paint arrays, and
clean under the caller's tracked allocator.

### Repair slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, both new 3A files, all legacy
   files under `packages/hs`, and the Odin allocator/container definitions used
   by the codec. Inspect `jj diff --git` before editing. Preserve the 3A wire
   layout and do not touch legacy hot serialization.
2. Keep scope to `packages/hs/portable.odin`,
   `tests/hs_portable_test.odin`, and this plan. Do not add the fixture
   container, product adapter, file I/O, `Fixture` edits, migrations,
   rehydration, editor actions, or CI wiring.
3. Make the generic default policy-free:

   - set the default `exclusion_tag` to `""`;
   - add one test helper that explicitly returns a config with
     `exclusion_tag = "fixture"` and use it in exclusion tests;
   - prove a `fixture:"-"` field is included under the generic default and is
     excluded only when that tag key is requested.

   The Adriatic adapter will choose `"fixture"` in milestone 3C.
4. Define and enforce allocator ownership on every exit:

   - reject an allocator with a nil procedure as `.Invalid_Argument`;
   - add small cleanup helpers for discovery types, per-type field/enum arrays,
     maps, parsed tables, and writer buffers;
   - install cleanup immediately after each successful allocation;
   - on encode success, transfer ownership of only the returned payload to the
     caller and free every discovery/table/body scratch allocation;
   - on encode failure, free the partial output too;
   - after decode, free all parsed metadata on both success and failure while
     leaving successfully cloned destination strings owned by the caller;
   - document that callers own the successful encoded slice and any decoded
     string allocations.

   Do not hide scratch ownership behind `context.temp_allocator`.
5. Make every wire-width conversion checked. Reject configurations whose
   payload, type, field, or string limits cannot fit the corresponding wire
   integer. Check counts and lengths before every `u32` conversion, and return
   `.Overflow` for arithmetic/narrowing overflow rather than relying on a
   wrapped cast. Keep cursor math in subtraction form or checked addition.
6. Validate the complete saved type graph before reading the body:

   - every referenced handle must be nonzero and in range;
   - array, struct, and enum dependencies must form an acyclic by-value graph;
   - every enum base must resolve to a signed, unsigned, or rune scalar with a
     valid width/sign combination;
   - enum values must fit their declared base, and a body value must be
     declared by the saved enum before it is assigned to the destination;
   - reject invalid, duplicate, or unreachable metadata if the encoder cannot
     canonically produce it.

   Use a compact three-state DFS over type handles. Do not let corrupt metadata
   reach recursive value walking.
7. Make failure stop work immediately. Every array and struct decode/skip loop
   must break or return as soon as `reader.error` is set. Add a regression that
   forges a maximum-count self-referential array record with a tiny body and
   proves rejection during table validation, before element iteration.
8. Remove per-element path allocation from array hot loops. Use an
   allocation-free path representation or materialize an indexed path only
   when the first error is produced. Preserve full named field paths for
   unsupported fields. A normal encode/decode of a large fixed byte array must
   not allocate one string per element.
9. Expand focused tests:

   - round-trip all supported scalar widths, including rune and `f16`;
   - prove both direct and nested exclusion differences encode identically;
   - run successful encode/decode with the normal tracked allocator, delete
     the returned payload and decoded strings, and rely on the test runner to
     report any retained scratch allocation;
   - exercise failure after partial discovery, table encode, body encode,
     table parse, and decoded-string allocation under the tracked allocator;
   - corrupt an array count, self/cyclic handle, enum base kind, enum body
     value, scalar width, UTF-8 name, string length, reserved byte, root handle,
     field handle, and trailing length;
   - assert every helper successfully locates the record it intends to mutate
     before testing rejection;
   - add a moderate fixed-array regression large enough to catch per-element
     path allocation without putting the full paint array in the normal suite.
10. Replace the synthetic TOML text with real repository behavior. Construct
    a TOML-compatible mirror containing exactly the same included values, call
    `toml.marshal` and `toml.emit`, clean up the table, and compare emitted byte
    length with portable bytes. Adjust the representative array size if needed,
    but keep the requirement that portable output is at most half the actual
    equivalent TOML output.
11. Remove the duplicated scalar-kind comparison while touching that branch.
    Format only the two new Odin files, then run:

    - `make fixture-schema-check`;
    - `make fixture-schema-generate` twice and compare manifest SHA;
    - `make check`;
    - `make test`.

12. Inspect the complete `jj diff --git` and an isolated diff from the accepted
    M2R3 state. Record exact test count, leak result, manifest SHA, and the
    moderate-array payload size in this plan.

### Acceptance criteria

- Generic `hs` contains no Adriatic tag default or other product policy.
- Successful and failing codec calls retain no scratch allocations under the
  caller's tracked allocator; ownership of returned/decoded data is explicit.
- Malformed type graphs are rejected before value walking, and the decoder
  performs no meaningful work after its first error.
- Walking fixed arrays performs no allocation per element and is suitable for
  the version-1 `[3][8388608]u8` shape.
- Every count/length narrowing is checked against both configured limits and
  its wire width.
- The hardening mutations are mandatory and cover the promised corruption
  classes without conditional no-op branches.
- The size claim uses actual `toml.marshal` plus `toml.emit` output and remains
  at or below one half.
- Legacy hot reload and the 3A wire layout remain unchanged.
- Schema check, deterministic generation, build, and all tests pass with no
  leak warnings.

### Milestone 3AR implementation report

- Portable codec remains memory-only and keeps the 3A wire layout.
- Generic `hs` default exclusion tag is empty; tests opt into `fixture` policy.
- `make test`: 394 tests, zero leak diagnostics.
- Schema v1 SHA remains `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12` after double generation.
- Moderate `[4096]u8` array payload: 4,165 bytes; no per-element path allocations.
- Real `toml.marshal` plus `toml.emit` comparison passes the 2x size gate.

### Reviewer verification — 2026-07-27

- The isolated 3AR diff contains only `packages/hs/portable.odin`,
  `tests/hs_portable_test.odin`, and this plan.
- Generic policy, checked wire-width conversion, nil-allocator rejection,
  per-element path removal, cycle/enum validation, actual TOML comparison, and
  tracked success-path cleanup are present.
- `make fixture-schema-check` and `make check` pass.
- The first full test run hit an unrelated seeded farmland determinism failure.
  Its focused rerun passed, then all 394 tests passed with no leak diagnostics.
- Two schema generations preserve SHA-256
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
- Partial type-table parse cleanup is still incorrect. `owned_types := types`
  captures the dynamic array at length zero. On an error after struct or enum
  fields have been appended, cleanup frees the outer backing allocation but
  cannot visit and free any nested field arrays; the current partially parsed
  record is not owned by the array at all.
- Graph validation recursively follows hostile saved type handles without
  applying `max_recursion_depth`. A long acyclic chain therefore recurses
  beyond the configured default before body decoding and can exhaust the call
  stack.
- Error paths are cloned with the caller allocator, but public ownership is not
  represented or documented. Tests contain a private
  `portable_test_delete_error_path` heuristic; production callers cannot
  safely know whether a returned path is static or must be deleted.
- Duplicate field and enum-name checks remain quadratic inside attacker-sized
  counts. The 65,536-field default permits billions of string comparisons.
- Milestone 3AR is not accepted. Proceed only with 3AR2.

## Milestone 3AR2 — Close failure-path ownership and depth bounds

### Goal

Finish the portable codec without changing its wire layout: every partial
parse must clean up, every returned allocation must have an explicit public
owner, and hostile metadata work must remain within configured depth and
practical linear bounds.

### Final repair slave implementation plan

1. Keep scope to `packages/hs/portable.odin`,
   `tests/hs_portable_test.odin`, and this plan. Preserve all accepted 3AR
   behavior and the 3A wire bytes. Do not start container, adapter, fixture,
   migration, editor, rehydration, or CI work.
2. Repair partial table ownership:

   - keep one local parsed-type array whose current length always includes the
     record being filled;
   - append an empty record immediately after its fixed header is valid, then
     write struct fields or enum fields through that owned record;
   - on every failure, destroy that live array with
     `portable_delete_types`, including the current partial record;
   - transfer the array to the caller only on success.

   Do not capture a zero-length dynamic-array copy before appends.
3. Add tracked-allocator regressions that fail during parsing after at least
   one struct field allocation and after at least one enum-field allocation.
   Both must return errors with zero retained table metadata. Existing
   first-record reserved-byte failure is insufficient.
4. Give allocated error paths one public ownership rule. Prefer adding explicit
   ownership state plus one idempotent public cleanup procedure; static paths
   must be safe no-ops and allocated paths must be released with their original
   allocator. Document encode/decode error ownership beside the APIs. Replace
   the test-only `strings.contains(error.path, "$.")` deletion heuristic with
   that public operation.
5. Bound recursive type validation before recursing:

   - validate graph depth against `config.limits.max_recursion_depth`;
   - reject configurations above one compile-time safe recursion ceiling,
     because graph and value walkers use the call stack;
   - keep cycle detection and unreachable-type rejection;
   - return `.Limit_Exceeded` for an acyclic dependency chain deeper than the
     configured limit.

   Add a synthetic chain one level beyond the default limit. It must fail
   during table validation without reaching body decode or overflowing stack.
6. Replace per-record quadratic duplicate-name scans with a temporary set
   keyed by borrowed payload names. Clean the set on every exit. Preserve the
   total field cap and add duplicate struct-field and enum-name rejection tests
   under the normal tracked allocator.
7. Format only the two codec files. Run:

   - `make fixture-schema-check`;
   - `make fixture-schema-generate` twice and compare SHA;
   - `make check`;
   - `make test`.

8. Inspect `jj diff --git` from the accepted 3AR base. Record exact test count,
   leak result, schema SHA, deep-chain rejection, and partial-parse cleanup in
   this plan.

### Acceptance criteria

- Partial struct and enum table records retain no allocation on any parse
  failure.
- Every allocated error path has a documented, test-covered public cleanup
  contract; callers need no pointer/content heuristic.
- Saved type-graph validation cannot recurse beyond the configured and hard
  safe depth.
- Duplicate-name validation is linear in the amount of accepted metadata.
- 3A wire bytes, generic policy, real TOML ratio, array behavior, and legacy hot
  reload remain unchanged.
- Schema check, deterministic generation, build, and all tests pass without
  leak warnings.

### Milestone 3AR2 verification record

- Scope stayed limited to `packages/hs/portable.odin`,
  `tests/hs_portable_test.odin`, and this plan. The portable wire layout is
  unchanged.
- Partial struct and enum table records now enter the owned dynamic array
  before nested fields are appended. Normal tracked-allocator duplicate-name
  failures clean both partial records with zero leak diagnostics.
- `Portable_Error` records whether `path` is allocated and stores its original
  allocator. `portable_error_dispose` is public, idempotent, and tested for
  both ownership detection and repeated disposal.
- Graph validation rejects a 257-level acyclic chain against the default
  256-level limit, and configurations above the compile-time safe ceiling are
  rejected before discovery. Duplicate-name checks use one borrowed-name set.
- `make test`: 396 tests, zero leak diagnostics.
- `make fixture-schema-check`, double generation, and `make check` pass. Both
  generations preserve SHA-256
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.

### Reviewer acceptance — 2026-07-27

- The isolated 3AR2 diff contains only `packages/hs/portable.odin`,
  `tests/hs_portable_test.odin`, and this plan.
- Partial struct and enum records are inserted into the live owned array before
  nested allocations; tracked duplicate failures exercise cleanup.
- `portable_error_dispose` records the original allocator, releases only owned
  paths, and is idempotent. Public API comments define ownership.
- Graph traversal and configured recursion share a hard ceiling of 256. The
  257-level acyclic regression fails before body walking.
- Borrowed-name sets make duplicate validation linear and are cleaned on every
  parser exit.
- `make fixture-schema-check`, `make check`, and all 396 tests pass with no leak
  diagnostics.
- Two schema generations preserve SHA-256
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
- Milestones 3A, 3AR, and 3AR2 are accepted. Portable `hs` is frozen while 3B
  is implemented.

## Milestone 3B — Add the product-local fixture container

### Goal

Wrap a portable `hs` payload in a small validated Adriatic fixture envelope.
Keep operations memory-only; filesystem and editor actions remain milestone 5.

### First container slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, the accepted portable `hs`
   API, `packages/hs/utils.odin` for repository FNV usage, and nearby
   product-local package/test conventions. Inspect `jj status` and the complete
   `jj diff --git` before editing.
2. Scope this milestone to:

   - one new `packages/fixture_file/fixture_file.odin`;
   - one new `tests/fixture_file_test.odin`;
   - this plan.

   Do not modify portable or legacy `hs`, `Fixture`, schema tooling or
   manifests, `src`, `Makefile`, `zelda-engine`, migrations, file I/O,
   rehydration, or editor actions.
3. Define the product-local wire contract as constants, with these exact byte
   offsets:

   - bytes `0..7`: magic `ADRFIX\0\0`;
   - bytes `8..9`: container version `u16`, initially `1`;
   - bytes `10..11`: flags `u16`, initially `0`;
   - bytes `12..15`: nonzero fixture schema version `u32`;
   - bytes `16..23`: payload length `u64`;
   - bytes `24..31`: FNV-1a-64 checksum of payload bytes.

   Header size is exactly 32 bytes. Encode every integer manually in
   little-endian order. Never transmute, cast, or dump an Odin header struct.
4. Keep container version separate from fixture schema version. Container
   decode accepts any nonzero schema version; migration support later decides
   whether that schema is known. Reject unknown container versions and every
   nonzero flag.
5. Add a small public configuration with a payload-byte cap. Default to 64 MiB
   to match accepted portable `hs`; milestone 3C will replace this only if the
   measured real fixture needs a different value. Reject invalid configuration
   before allocating or slicing; the configured cap must fit a host `int`
   after adding the 32-byte header.
6. Add compact structured errors with stable kind, byte offset, and static
   message. Cover at least:

   - invalid argument or allocator;
   - truncated header/payload;
   - bad magic;
   - unsupported container version;
   - unsupported flags;
   - zero schema version;
   - payload above limit;
   - length overflow or mismatch;
   - trailing bytes;
   - checksum mismatch.

   Container errors need no allocated strings and no disposal API.
7. Expose two memory-only operations:

   - encode payload plus schema version into a newly allocated container;
   - validate a container and return a borrowed view containing schema version
     and payload slice.

   Document that the caller deletes successful encode output with the supplied
   allocator and that a decoded payload borrows the input buffer. Every encode
   failure returns nil bytes. Every decode failure returns a zero view; never
   expose even a partial payload before checksum validation succeeds.
8. Use `core:hash.fnv64a` over payload bytes. Do not add a second handwritten
   FNV implementation and do not involve `hs` in the container package.
9. Encode defensively:

   - require schema version greater than zero and a valid allocator;
   - compare payload length to the configured cap before allocation;
   - check `32 + len(payload)` for host-`int` overflow;
   - allocate exactly once for final output;
   - write header fields, checksum, then copy payload;
   - free partial output on any failure.

10. Decode in this order:

    - require at least 32 bytes;
    - validate magic, container version, flags, and nonzero schema version;
    - read payload length as `u64`;
    - reject values wider than host `int`, then compare to the configured cap
      and available bytes before conversion or slicing;
    - distinguish truncated payload from appended trailing bytes;
    - verify checksum;
    - only then construct and return the borrowed payload view.

11. Tests must prove:

    - representative and empty payload round-trip;
    - schema version survives independently of container version;
    - same schema/payload encodes byte-identically twice;
    - every fixed header offset contains the expected little-endian bytes;
    - every prefix shorter than the header fails as truncated;
    - every payload prefix fails without exposing a view;
    - mutation of each magic byte, version, flags, zero schema version,
      checksum, and payload fails with the expected error kind;
    - on a nonempty payload, forged length zero and one byte short report
      trailing data, one byte long reports truncation, and `max(u64)` reports
      length overflow;
    - appended bytes are rejected as trailing data;
    - a configured cap smaller than the payload rejects before allocation or
      payload slicing;
    - nil allocator encode fails;
    - decoded payload aliases the validated input, while encode output has
      explicit tracked-allocator ownership;
    - all corrupt cases return a zero schema version and nil payload.

12. Format only the two new Odin files. Run:

    - `make fixture-schema-check`;
    - `make fixture-schema-generate` twice and compare schema SHA;
    - `make check`;
    - `make test`.

13. Inspect the complete `jj diff --git` and an isolated 3B diff. Record exact
    test count, leak result, schema SHA, header bytes, and representative
    container size in this plan.

### Acceptance criteria

- Container is portable, deterministic, bounded, and exactly validated.
- Schema version is carried independently from container version.
- Payload corruption and length tampering fail before `hs` decode.
- Encode output ownership and decode borrowing are explicit and leak-free.
- Failure never exposes payload bytes or a nonzero schema version.
- Generic `hs` remains free of Adriatic policy.

### Milestone 3B verification record

- Scope is isolated to `packages/fixture_file/fixture_file.odin`,
  `tests/fixture_file_test.odin`, and this plan. Portable `hs`, schema files,
  `Makefile`, `src`, and engine code are untouched by 3B.
- The representative seven-byte payload produces a deterministic 39-byte
  container. Its complete 32-byte header is:
  `41 44 52 46 49 58 00 00 01 00 00 00 07 00 00 00 07 00 00 00 00 00 00 00
   e0 1f cf c6 df aa 30 43`.
- Tests cover empty and representative round-trips, independent schema
  versions, exact little-endian fields, every short header/payload prefix,
  magic/version/flags/schema/checksum/payload corruption, forged lengths,
  trailing bytes, caps, host overflow, nil allocators, deterministic bytes,
  tracked output ownership, and borrowed decode views.
- `make test`: 401 tests, zero leak diagnostics. `make check` and schema check
  pass. Two schema generations preserve SHA-256
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.

### Reviewer acceptance — 2026-07-27

- The isolated 3B diff contains only
  `packages/fixture_file/fixture_file.odin`,
  `tests/fixture_file_test.odin`, and this plan.
- Header offsets, manual little-endian primitives, magic, version, flags,
  schema version, length, and FNV-1a checksum match the approved 32-byte
  contract.
- Encode validates before its single allocation and transfers only successful
  output. Decode returns a borrowed zero-copy view only after exact length and
  checksum validation; every failure returns a zero view.
- Truncation, trailing bytes, host overflow, cap failures, corruption, nil
  allocators, empty payloads, deterministic output, and tracked ownership are
  covered.
- `make fixture-schema-check`, `make check`, and all 401 tests pass without leak
  diagnostics.
- Two schema generations preserve SHA-256
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
- Milestone 3B is accepted. Container bytes are frozen while 3C proves the real
  fixture.

## Milestone 3C — Prove current `Fixture` round-trip

### Goal

Connect `Fixture`, portable `hs`, and the container in memory and measure real
version-1 behavior without mutating a live `Editor`.

### First real-fixture slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, `src/main.odin`, the accepted
   portable `hs` and fixture-container APIs, the complete version-1 manifest,
   all reachable nested types used by chosen sentinels, existing
   `src/*_test.odin` conventions, and the Makefile's dev link/dependency rules.
   Inspect `jj status` and the complete `jj diff --git` before editing.
2. Scope 3C to:

   - one production adapter such as `src/fixture_codec.odin`;
   - one `when ODIN_TEST` file such as `src/fixture_codec_test.odin`;
   - one focused Make target if needed;
   - this plan.

   Do not change `Fixture`, tags, schema version/manifest, portable `hs`,
   container bytes, editor actions, file I/O, migration dispatch, live state
   replacement, rehydration, or `zelda-engine`.
3. Prove the package-main test command before writing the real test. Existing
   `src` tests are not run by `make test`. Compile and run one minimal
   `when ODIN_TEST` fixture-codec test through `odin test src`, using the same
   collection, native-library dependencies, and linker flags as the dev app.
   Once proven, add a focused non-default Make target such as
   `fixture-codec-test` that selects only the fixture-codec test names. Do not
   move `Fixture` into a package or import package `main` from `tests`.
4. Add a thin memory-only current-schema adapter. It must:

   - build portable config from the accepted default and explicitly set
     `exclusion_tag = "fixture"`;
   - encode exactly `Fixture`, never root `Editor`;
   - wrap portable bytes with `FIXTURE_SCHEMA_VERSION`;
   - container-decode and require schema version exactly equal to
     `FIXTURE_SCHEMA_VERSION`;
   - portable-decode only into caller-provided temporary `Fixture` storage;
   - free intermediate portable bytes on every encode exit;
   - preserve caller ownership of successful container bytes;
   - use the caller allocator for portable output and decoded strings.

5. Add one adapter error type that distinguishes portable encode, container
   encode, container decode, current-schema mismatch, and portable decode.
   Embed the underlying structured error instead of flattening it to text.
   Provide an idempotent adapter disposal operation that delegates to
   `hs.portable_error_dispose` when needed. Container errors remain static.
   Document that portable decode failure may partially mutate only the supplied
   temporary destination; callers must discard it.
6. Never place `Fixture` or `Editor` on the test thread stack. Allocate source
   and destinations with `new`. Use a dedicated growing arena for each decode
   destination so all decoded strings and the large destination can be
   discarded atomically with `arena_destroy`. Follow the already compiled
   `core:mem/virtual` arena pattern in `packages/dio/flame.odin`; do not guess
   arena syntax.
7. Seed persisted sentinels across the real graph, including at minimum:

   - project sea level/revision, one structure, a last-level height, and a
     distant city-density byte;
   - authoring tool/radius and architecture city-plan state;
   - authored marina seed/validity and one farm;
   - player position/motion, camera state, and flight-camera state;
   - boat-traffic clock plus one agent/route/schedule value;
   - pilot/car/Postale/Libellula/aircraft fleet values, availability, and slot
     name;
   - `vehicle_showcase_target` and `active_lab_scene` strings;
   - settlement counts/validity, story stages and delivery subject;
   - atmosphere, vehicle effects, tweaks, and customization values;
   - first and last useful bytes across separate persisted paint layers,
     including byte
     `vehicle_paint_layers[2][VEHICLE_PAINT_TEXTURE_BYTE_COUNT - 1]`.

   Use declared enum variants and valid counts. Do not seed invalid enum
   integers merely to make comparison easy.
8. Seed exclusions with unmistakable nonzero values:

   - direct derived/session fields such as circulation cache, preview state,
     cursor state, and paint dirty flags;
   - nested relationship pointers:
     `pilot.vehicle`, `car.driver`, and an aircraft slot's `vehicle`;
   - an excluded dynamic slice such as `vehicle_paint_open_pixels`;
   - distant bytes in excluded architecture density, paint preview/history,
     and texel-part scratch arrays.

   Put one unique multi-byte marker in an excluded large array and prove that
   marker plus representative excluded field names are absent from the real
   portable payload. Clean source-only dynamic allocations explicitly.
9. Run the complete success proof:

   - encode the same source twice and require byte identity;
   - container-decode and require schema version
     `FIXTURE_SCHEMA_VERSION`;
   - inspect the borrowed portable payload for excluded-name/marker absence;
   - decode into fresh arena-backed temporary `Fixture`;
   - verify every persisted sentinel;
   - verify every direct and nested exclusion is zero/nil;
   - re-encode the decoded fixture and require byte identity with the original
     container.

   Do not compare raw `Fixture` memory: padding and excluded data make that
   meaningless.
10. Record `size_of(Fixture)`, portable payload bytes, final container bytes,
    encode time, and decode time. Assert the container fits the 64 MiB cap.
    Keep that cap only if at least ten percent remains free. If measured output
    exceeds the cap or leaves less headroom, stop and report measurements; do
    not silently raise limits or add compression in 3C.
11. Add failure proofs:

    - every truncation of the 32-byte container header returns before portable
      decode and leaves a pre-seeded destination unchanged;
    - payload corruption without checksum repair fails at container validation
      and leaves destination unchanged;
    - a valid container carrying a different nonzero schema version fails at
      the adapter's current-schema gate and leaves destination unchanged;
    - a valid container wrapping malformed portable bytes reaches the portable
      stage, returns its structured error, and the temporary destination is
      destroyed without inspection or live-state use;
    - all returned adapter errors are disposed and all successful output is
      deleted.

12. Run:

    - the focused `make fixture-codec-test` target;
    - `make fixture-schema-check`;
    - `make fixture-schema-generate` twice and compare schema SHA;
    - `make check`;
    - `make test`.

13. Inspect the complete `jj diff --git` and an isolated 3C diff. Record exact
    focused/full test counts, leak results, schema SHA, size/timing
    measurements, and the exact proven package-main test target in this plan.

### Acceptance criteria

- Current schema-version-1 `Fixture` round-trips in memory.
- All fixture exclusions, including nested pointer links, are absent.
- Container schema version equals `FIXTURE_SCHEMA_VERSION`.
- Real payload fits the documented cap with measured headroom.
- Real payload excludes direct and nested `fixture:"-"` state.
- Full encode/decode/re-encode is byte-identical.
- Failed decode never mutates live editor state.
- No file I/O, editor actions, rehydration, or migrations exist yet.

### Milestone 3C implementation verification — schema gate blocked

- Isolated 3C diff contains `src/fixture_codec.odin`,
  `src/fixture_codec_test.odin`, the focused `fixture-codec-test` Make target,
  and this plan. `Fixture`, tags, portable `hs`, container bytes, and schema
  files were not changed.
- Proven package-main command is `make fixture-codec-test`; it selects
  `main.fixture_codec_real_fixture_round_trip_and_failures` through
  `odin test src` and uses the dev Jolt, textshape, HarfBuzz, FreeType, mesh,
  signpost, and libc++ link dependencies.
- Before the third rebase, the focused test passed with zero leak diagnostics.
  Measurements were:
  `size_of(Fixture)=47,996,008`, portable payload `28,744,609` bytes,
  container `28,744,641` bytes, encode about `853.886 ms`, decode about
  `877.556 ms`. The container remained below the 64 MiB cap with more than ten
  percent headroom.
- The real source/destination round-trip is byte-identical, all selected
  persisted and excluded sentinels pass, nested pointers are absent, malformed
  portable payloads reach the portable stage, and all adapter errors are
  disposed against that pre-third-rebase tree.
- The third rebase invalidated this acceptance. In addition to the complete
  schema delta recorded above, `terrain.Project.structures` is now a dynamic
  array. The focused test traps before encode because its source setup assumes
  fixed storage, and portable `hs` deliberately rejected dynamic arrays in
  3A. Milestone 3C therefore returns to blocked state until 3CR and 3D pass.

## Milestone 3CR — Repair portable dynamic-array support

### Goal

Extend the generic portable codec for owned Odin dynamic arrays, then restore
the real current-`Fixture` round-trip. Keep the frozen fixture schema and
container untouched; schema evolution belongs to 3D.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, all of
   `packages/hs/portable.odin`, `tests/hs_portable_test.odin`,
   `src/fixture_codec.odin`, `src/fixture_codec_test.odin`,
   `packages/terrain/terrain.odin`, and the installed runtime definitions for
   `rt.Type_Info_Dynamic_Array`, `rt.Raw_Dynamic_Array`, and allocator APIs.
   Inspect `jj status`, `jj resolve --list`, the complete `jj diff --git`, and
   the latest parent stack before editing.
2. Preserve all accepted work. Scope 3CR to:

   - `packages/hs/portable.odin`;
   - `tests/hs_portable_test.odin`;
   - `src/fixture_codec_test.odin`;
   - this plan.

   Change `src/fixture_codec.odin` only if the accepted adapter API genuinely
   cannot represent dynamic-array ownership. Do not change `Fixture`,
   `terrain`, tags, schema version/manifests, fixture container bytes,
   migration dispatch, editor lifecycle, file I/O, or `zelda-engine`.
3. Before production code, compile a minimal disposable Odin spike proving how
   to:

   - inspect a `[dynamic]T` through `rt.Type_Info_Dynamic_Array`;
   - read a value through `rt.Raw_Dynamic_Array`;
   - allocate one correctly sized and aligned erased backing block with a
     supplied allocator;
   - install data, length, capacity, and allocator into a zeroed destination;
   - delete the resulting typed dynamic array without leaks.

   Test zero and nonzero lengths. Delete the spike after focused production
   tests cover the syntax. Do not copy the legacy `hs` dynamic path blindly;
   it has weaker ownership assumptions.
4. Add `Dynamic_Array` after every existing `Portable_Kind` value. Never
   renumber existing kinds. Preserve `Portable_Magic`, `Portable_Version`, the
   28-byte header, and byte output for every previously supported value. This
   is an additive kind inside the existing tagged type-table grammar, not
   permission to rewrite the accepted wire layout. Stop and report if an
   existing kind's bytes must change.
5. Encode dynamic-array type metadata as exactly its element handle. Encode
   each value body as a checked little-endian `u64` element count followed by
   elements in index order. Do not serialize data pointers, capacity, or
   allocator fields. A nil and an allocated-empty dynamic array must produce
   the same canonical body.
6. During discovery and encode:

   - resolve the flattened element type through runtime metadata;
   - reject negative length, capacity below length, nil data with nonzero
     length, element-count limit violations, and checked byte-size overflow;
   - retain the existing recursion and type/field limits;
   - allocate no path or temporary object per element;
   - keep slices, maps, pointers, procedures, and all other unsupported forms
     rejected.

   An excluded dynamic-array field must be skipped before its type or raw
   header is inspected.
7. Harden table parse, graph validation, body skipping, and corruption paths
   for the new kind. Validate the element handle and count before allocation or
   iteration. Reject recursive dynamic-container type graphs for now rather
   than weakening the accepted cycle guard; recursive containers are not
   needed by the current `Fixture`.
8. Decode with the caller allocator and one aligned backing allocation per
   nonempty dynamic array. Require a zero/nil destination header before
   installation so decode cannot overwrite owned storage silently. On success,
   the typed array's allocator must be the supplied allocator. On partial
   failure, document that the caller owns all installed dynamic arrays and
   strings; fixture callers continue to discard the entire arena.
9. Support the schema-evolution crossings needed by the next milestone:

   - saved fixed array to current dynamic array: allocate the saved fixed
     count and decode every element;
   - saved dynamic array to current dynamic array: allocate the saved runtime
     count;
   - saved dynamic array to current fixed array: decode the fitting prefix and
     validate/skip excess elements exactly like the accepted fixed-array
     shrink behavior;
   - saved fixed array to current fixed array: preserve existing behavior
     byte-for-byte.

   Do not accept a slice destination.
10. Extend hardening tests with small purpose-built types. Prove:

    - empty, single-element, and multi-element dynamic arrays;
    - nested structs plus owned strings;
    - deterministic encode/decode/re-encode bytes;
    - fixed-to-dynamic and dynamic-to-fixed crossings;
    - excess dynamic elements are validated and skipped;
    - excluded dynamic fields are neither discovered nor inspected;
    - slices remain unsupported;
    - truncated count/body, excessive count, multiplication overflow,
      invalid element handle, recursive type graph, corrupt raw source header,
      nil allocator, and allocation failure return structured errors;
    - one backing allocation per decoded array, no allocation by the
      dynamic-array layer merely to derive an element index/path, correct
      allocator ownership, idempotent error disposal, and zero leaks on success
      and every failure path. Nested strings and nested containers retain their
      own documented allocations.
11. Repair the real fixture source setup:

    - allocate or append one `terrain.Structure` before indexing
      `source.project.structures[0]`;
    - delete source-owned project storage through the production terrain
      lifecycle in the test destructor;
    - seed and verify `farmland.Plan.width`, `height`, and `tradition`;
    - seed and verify `Farm_Instance.scale_x` and `scale_z`;
    - seed an excluded nonempty `circulation_structures` array, prove its field
      name is absent and the decoded field is nil, then clean it;
    - keep the decode destination arena-owned and preserve all prior sentinels,
      corruption cases, byte-identity checks, and 64 MiB headroom assertion.
12. Run the new portable dynamic tests directly by exact Odin test names, then
    run:

    - `make fixture-codec-test`;
    - `make check`;
    - `make test`;
    - `make fixture-schema-check`.

    At this milestone only, the last two schema gates may retain exactly the
    one already-proven production-manifest failure. No other test failure or
    leak warning is allowed. Do not run schema generation against the real
    tree.
13. Confirm frozen version-1 SHA remains
    `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
    Inspect complete and isolated `jj diff --git`. Record focused test names,
    counts, allocation evidence, new fixture size/payload/timings, full test
    count, and the sole known schema failure here.

### Acceptance criteria

- Generic portable `hs` round-trips owned dynamic arrays with caller allocator
  ownership and no raw process-local header data.
- Existing supported values retain their wire bytes and kind numbers.
- Fixed/dynamic crossings needed for version-1 fixture migration are proven.
- Unsupported slices and recursive container graphs still fail closed.
- Current `Fixture`, including dynamic authored structures and all new farm
  fields, encodes twice identically, decodes, and re-encodes identically.
- Excluded dynamic circulation scratch state is absent.
- Focused portable and fixture tests pass without leaks.
- `make check` passes; full tests have no failure beyond the separately scoped
  frozen-manifest mismatch.
- Fixture schema version, both schema files, and container format are
  unchanged.

### Milestone 3CR implementation verification — behavior green, schema gate retained

- Scope stayed inside `packages/hs/portable.odin`,
  `tests/hs_portable_test.odin`, `src/fixture_codec_test.odin`, and this plan.
  `Fixture`, tags, portable header/version, container bytes, manifests, and
  `src/fixture_codec.odin` were unchanged.
- Disposable runtime spike proved zero and nonzero `[dynamic]T` raw-header
  inspection, aligned erased backing allocation, header installation, and
  typed deletion. It was deleted before production verification.
- Added `Portable_Kind.Dynamic_Array` as kind `10`; existing kinds, headers,
  and their bytes remain unchanged. Dynamic metadata stores only the element
  handle. Bodies store a checked little-endian `u64` count and elements.
- Dynamic discovery skips excluded fields before inspecting their types;
  encode rejects corrupt source headers, invalid lengths/capacities, nil data
  with nonzero length, count limits, and byte-size overflow. Decode validates
  counts before iteration, rejects recursive graphs and occupied destination
  headers, installs one aligned backing allocation per nonempty array, and
  records caller-allocator ownership for partial failures.
- Exact portable test command passed both new tests:
  `tests.hs_portable_dynamic_arrays_round_trip_and_exclusions` and
  `tests.hs_portable_dynamic_arrays_cross_fixed_and_harden_failures`.
  Full `make test` reached 445 tests with zero leak diagnostics and only the
  separately scoped frozen-manifest assertion.
- `make fixture-codec-test` passed with zero leak diagnostics. Measurements:
  `size_of(Fixture)=47,874,024`, portable payload `28,658,680` bytes, container
  `28,658,712` bytes, encode about `857.488 ms`, decode about `879.079 ms`.
  The real dynamic project structures, architecture plan, farm width/height/
  tradition/scales, excluded circulation array, corruption cases, and
  byte-identical re-encode all pass.
- `make check` passed. `make test` and `make fixture-schema-check` retain the
  one known production-manifest mismatch: current
  `architecture.City_Plan.structures` is dynamic while frozen v1 records
  `array[256]`. No schema generation was run. Frozen v1 SHA remains
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.

### Reviewer correction — 2026-07-27

The implementation verification above records what the 3CR slave proved; it is
not acceptance. The fourth rebased audit found an encoder/decoder cycle
asymmetry and four focused-proof gaps. M3CR remains open through 3CR2.

## Milestone 3CR2 — Close dynamic-array codec and fixture-proof gaps

### Goal

Make portable encode reject every recursive by-value type graph that decode
rejects, restore the prior valid limit domain, prove excess-element validation
and allocation behavior, and exercise every new durable city-plan dynamic
array in the real fixture.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, and all of
   `packages/hs/portable.odin`, `tests/hs_portable_test.odin`,
   `src/fixture_codec_test.odin`, and
   `packages/architecture/architecture.odin`. Inspect `jj status`,
   `jj resolve --list`, the parent stack, the complete `jj diff --git`, and an
   isolated diff from the pre-3CR snapshot before editing.
2. Scope the repair to exactly:

   - `packages/hs/portable.odin`;
   - `tests/hs_portable_test.odin`;
   - `src/fixture_codec_test.odin`;
   - this plan.

   Do not change `src/fixture_codec.odin`, `Fixture`, tags, schema version,
   either manifest, fixture-container bytes, migration code, editor lifecycle,
   file I/O, or `zelda-engine`.
3. Add a production encode test using a real recursive dynamic type equivalent
   to:

   ```odin
   Recursive_Node :: struct {
       value:    i32,
       children: [dynamic]Recursive_Node,
   }
   ```

   Encoding even a value with an empty `children` array must fail with the same
   structured cycle error as table decode and return no bytes. Keep the
   existing fabricated cyclic-table decode test. Do not weaken the cycle guard
   or make behavior depend on runtime element count.
4. After discovery completes and before table sizing or body emission, validate
   the discovered encoder type graph with the same bounded DFS policy used for
   decoded tables. Reuse one graph-validation implementation or one shared
   primitive; do not maintain divergent encoder and decoder cycle rules.
   Allocate validator state only from the caller allocator, clean it on every
   exit, and preserve structured error disposal. Existing acyclic types must
   retain identical kind numbers, headers, table records, and body bytes.
5. Remove `max_array_elements` from the group constrained to `max(u32)` during
   config validation. Array metadata and dynamic value counts are `u64`, while
   actual allocation and iteration already check host `int`, configured count,
   byte-size overflow, and payload limits. Add a small-array encode/decode test
   with `max_array_elements = max(int)` proving the configuration remains
   usable; do not relax any actual value or allocation bound.
6. Replace or extend the dynamic-to-fixed crossing proof with a saved dynamic
   array longer than the fixed destination, for example five elements into
   `[3]T`. Require the fitting prefix to decode and every excess element to be
   parsed and validated. Mutate an excess element into an invalid enum or other
   structured corruption and require failure even though that element would
   not fit in the destination. A mere truncated tail is insufficient evidence.
7. Prove the dynamic-array layer does not allocate per element. Decode the same
   scalar dynamic type once with one element and once with at least 128
   elements through fresh counting allocators. Require equal successful
   allocation counts, correct values, caller-allocator ownership, and zero
   outstanding allocations after cleanup. Keep the allocation-failure proof
   and distinguish table/error bookkeeping from the one array backing block;
   do not assert only `allocs >= N`.
8. Expand the real fixture source with nonempty, valid
   `architecture_city_plan.structures`, `.parcels`, `.alleys`, and `.lamps`.
   Set their matching active counts, seed distinct persisted sentinels, and
   verify lengths, counts, and values after decode. Continue destroying source
   ownership only through `architecture.city_plan_destroy`; do not add manual
   deletes that conflict with that lifecycle. Preserve all project, farm,
   exclusion, corruption, identity, and headroom proofs.
9. Run the exact three focused portable tests: the two existing dynamic-array
   tests plus the new recursive-source encode test. Then run:

   - `make fixture-codec-test`;
   - `make check`;
   - `make test`;
   - `make fixture-schema-check`.

   The last two schema gates may retain exactly the one known frozen-manifest
   failure. No other failure or leak diagnostic is allowed. Do not generate a
   schema against the real tree.
10. Confirm frozen version-1 SHA remains
    `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
    Inspect the complete and isolated `jj diff --git`. Record exact test names,
    allocation counts for one versus many elements, real-fixture
    size/payload/timings, full test count, and the sole schema failure here.

### Acceptance criteria

- Encode and decode reject the same recursive dynamic-container graph before
  any body walk or usable output.
- All previously supported acyclic values retain identical wire bytes.
- `max_array_elements` accepts the full host-`int` configuration domain while
  actual counts and allocations remain bounded.
- Dynamic-to-fixed shrink validates and skips corruptible excess elements.
- Successful scalar-array allocation count is independent of element count.
- All four durable `architecture.City_Plan` arrays round-trip through the real
  fixture and use the production destruction lifecycle.
- Focused tests and `make check` pass without leaks; the only permitted full
  failure remains the frozen schema mismatch.
- Schema version, manifests, container, adapter, and product state stay
  untouched.

### Milestone 3CR2 implementation verification — behavior green, schema gate retained

- Scope stayed inside `packages/hs/portable.odin`,
  `tests/hs_portable_test.odin`, `src/fixture_codec_test.odin`, and this plan.
  No adapter, Fixture definition, tags, schema version, manifest, container,
  migration, editor, file-I/O, or engine files changed.
- Encoder discovery now runs the same bounded `portable_validate_type_graph`
  DFS as decoder table validation before table sizing or body emission. A real
  recursive dynamic node with empty children returns no bytes and the same
  structured cycle error; fabricated cyclic-table decode remains covered.
- `max_array_elements = max(int)` is accepted and small dynamic arrays still
  round-trip. The wire-width restriction remains on actual u32 fields; value
  counts retain host-int, configured-count, byte-size, allocation, and payload
  checks.
- Dynamic-to-fixed enum crossing uses five saved elements into `[3]`. The
  fitting prefix succeeds; corrupting an excess enum value fails during skip,
  proving excess elements are parsed and validated rather than ignored.
- Fresh counting allocators decode one and 128 scalar elements with exactly
  `6` successful allocations each and `0` outstanding allocations after
  cleanup. Existing allocation-failure coverage remains green.
- Real Fixture proof now seeds and verifies nonempty valid
  `architecture_city_plan.structures`, `.parcels`, `.alleys`, and `.lamps`,
  with source cleanup through `architecture.city_plan_destroy`.
- Exact focused command passed:
  `tests.hs_portable_dynamic_arrays_round_trip_and_exclusions`,
  `tests.hs_portable_dynamic_arrays_cross_fixed_and_harden_failures`, and
  `tests.hs_portable_recursive_dynamic_encode_rejects_before_body`.
  `make fixture-codec-test` passed with zero leak diagnostics:
  `size_of(Fixture)=47,874,024`, portable payload `28,658,762` bytes,
  container `28,658,794` bytes, encode about `839.831 ms`, decode about
  `881.789 ms`.
- `make check` passed. `make test` reached 447 tests with zero leak
  diagnostics and only the known frozen-manifest assertion. `make
  fixture-schema-check` reports the same sole mismatch: current
  `architecture.City_Plan.structures` is dynamic while frozen v1 records
  `array[256]`. No schema generation was run. Frozen v1 SHA remains
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.

### Reviewer acceptance — 2026-07-27

- The isolated M3CR2 delta contains only
  `packages/hs/portable.odin`, `tests/hs_portable_test.odin`,
  `src/fixture_codec_test.odin`, and this plan: 303 insertions and 5
  deletions. No conflict, formatter spill, generated binary, or unrelated
  source change remains.
- Encoder and decoder call the same bounded type-graph validator. Encoder calls
  it after discovery and before table/body writers exist, so the recursive
  dynamic source returns no usable bytes. Validator state uses the caller
  allocator and is released on every exit.
- Enum skip now validates base handle, integer base kind, signed conversion,
  and declared saved value. The five-to-three crossing corrupts saved element
  four and fails, proving an out-of-destination element is still validated.
- `max_array_elements` no longer inherits the unrelated u32 header-field cap.
  Actual fixed/dynamic counts retain configured, host-int, byte-size, payload,
  and allocation bounds.
- Counting allocators independently report six allocations for one and 128
  scalar elements, then zero outstanding blocks. The real fixture owns and
  destroys all four city-plan arrays through `city_plan_destroy`.
- Independent focused run passes all three selected tests with memory tracking
  and no leak diagnostics. Independent `make fixture-codec-test` passes:
  `size_of(Fixture)=47,874,024`, payload `28,658,762`, container
  `28,658,794`, encode about `849.969 ms`, decode about `883.466 ms`.
- Independent `make check` passes. Full `make test` reaches 447 tests with only
  the known frozen-manifest assertion; schema check reports that same first
  mismatch. Frozen v1 remains 1,340 lines with SHA-256
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
- M3CR and M3CR2 are accepted. Current-fixture behavior is green; schema
  activation and migration remain deliberately blocked behind 3D1–3F.

## Milestone 3D1 — Parse frozen manifests and generate historical types

### Goal

Turn immutable version-1 manifest data into one deterministic, compileable
Odin package that preserves historical field access and fixed container
shapes. Do not diff schemas, generate a migration script, bump the schema, or
dispatch migrations yet.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, all of
   `packages/fixture_schema/fixture_schema.odin`,
   `tests/fixture_schema_test.odin`, `tools/fixture_schema/main.odin`, the
   complete frozen v1 manifest, the fixture Make targets, and the relevant
   installed `core:odin` parser/AST/tokenizer APIs. Inspect `jj status`,
   `jj resolve --list`, the parent stack, the complete `jj diff --git`, and an
   isolated pre-3D1 diff before editing.
2. Before production code, compile a disposable Odin spike proving:

   - forward references among generated named types;
   - explicit-base enums with noncontiguous and negative values where the
     declared base permits them;
   - alias and `distinct` declarations;
   - nested fixed arrays and the largest v1 fixed array length;
   - the chosen generated-symbol syntax and package name.

   Delete the spike after focused tests cover the syntax. Do not guess emitted
   Odin grammar.
3. Scope 3D1 to:

   - small new parser/emitter files inside `packages/fixture_schema` rather
     than mixing code generation into the existing source AST walker;
   - `tools/fixture_schema/main.odin`;
   - focused schema/history tests;
   - two narrow Make targets;
   - generated
     `packages/fixture_history/v0001/schema.generated.odin`;
   - this plan.

   Do not change `Fixture`, `Editor`, tags, portable `hs`, fixture container,
   `src/fixture_codec.odin`, schema version, either schema manifest, migration
   registry/scripts, live editor behavior, file save/load, or `zelda-engine`.
4. Add one strict owned manifest model and parser. The API must accept manifest
   bytes plus a caller allocator, return a structured error with line/path,
   and have idempotent cleanup for every owned string, array, map, and error
   path. Parsing must understand the existing backslash escapes for `\\`,
   `\t`, `\n`, `\=`, and `\|`; splitting on raw `|` or `=` is forbidden.
   Reject malformed or unknown escapes.
5. Validate the complete manifest before emission:

   - exactly one supported `format_version`, positive schema version, and root;
   - unique type IDs, field names per struct, and enum names/values;
   - every field/enum line belongs to its declared record;
   - supported record kinds and required detail keys;
   - valid recursive type-expression grammar and nonnegative fixed lengths;
   - every named reference resolves;
   - root resolves to a struct and every record is reachable from it;
   - no duplicate, missing, trailing, reordered-header, unknown-key, or
     partially parsed input is accepted.

   Apply explicit sane caps to lines, records, fields, nesting, identifier
   length, and emitted bytes before allocating or recursing.
6. Generate a package with no imports at
   `packages/fixture_history/v0001/schema.generated.odin` and package name
   `fixture_v0001`. Remap every full logical type ID to one stable,
   collision-free Odin symbol; basename-only mapping is forbidden. Emit the
   original logical ID in an adjacent generated comment and expose the
   historical root as `Fixture`.
7. Support exactly the frozen-v1 shape grammar in this milestone:

   - builtin scalar and string types;
   - named references;
   - nested fixed arrays;
   - `struct`, explicit-base `enum`, `alias`, and `distinct` records.

   Preserve struct field order/names and `using`, enum base/names/explicit
   values, alias target, distinct target, and fixed lengths. Frozen manifests
   already omit `fixture:"-"` fields; non-serialization tags and layout
   padding need not be re-emitted. Fail closed on dynamic arrays, slices, maps,
   pointers, unions, matrices, bit types, anonymous records, or any other
   unsupported shape rather than emitting plausible junk. Later milestones
   may expand this grammar when a historical version actually needs it.
8. Validate every source field and enum identifier before placing it in
   generated code. Generated type symbols must derive only from validated
   canonical IDs or stable sorted ordinals, never raw unescaped text. Include
   a generated-file header with source manifest version and SHA-256. Output
   ordering must depend only on canonical manifest content, not map order,
   absolute paths, allocator addresses, or timestamps.
9. Extend the CLI without changing existing `generate` and `check` behavior:

   - `history-generate <version> <repository-root>` atomically writes the
     derived package for an existing committed manifest;
   - `history-check <version> <repository-root>` generates in memory and
     byte-compares without writing.

   Reject zero, future, missing, malformed, or path-escaping versions. Add
   `fixture-history-generate` and `fixture-history-check` Make targets pinned
   to v1. History check must also run Odin check on the generated package with
   no entry point.
10. Add focused synthetic tests for:

    - valid parse, escape/unescape, nested arrays, aliases, distincts, forward
      references, and explicit enums;
    - deterministic output across two allocations and two different temporary
      repository paths;
    - every malformed header/line/escape/detail/type expression;
    - duplicate records/fields/enums, unresolved references, unreachable
      records, invalid identifiers, symbol collisions, unsupported shapes,
      recursion-depth and size caps;
    - atomic write behavior and history-check mismatch diagnostics;
    - cleanup after every success and failure with memory tracking.

    Generate code in temporary repositories and parse/check the resulting Odin
    package; string-presence assertions alone do not prove valid code.
11. Generate the real v1 package and prove:

    - all 144 historical named records are represented;
    - `Fixture` exposes all 142 frozen root fields;
    - `Settlement_Plan.city_plan` remains accessible;
    - project structures remain `[256]`, and city-plan structures/parcels/
      alleys/lamps remain `[256]`, `[256]`, `[128]`, and `[256]`;
    - farmland v1 has no width, height, or tradition and `Farm_Instance` has no
      scale fields;
    - the package compiles without importing current product or engine types.

    Use compile-time or focused runtime field/capacity probes. Never place the
    48 MiB historical root on a thread stack.
12. Run:

    - focused parser/history tests by exact test names;
    - `make fixture-history-generate` twice and compare output SHA;
    - `make fixture-history-check`;
    - `make check`;
    - `make test`;
    - `make fixture-schema-check`.

    The last two schema gates may retain exactly the known frozen production
    mismatch. No other failure or leak diagnostic is allowed. Do not run
    normal schema generation against the real tree.
13. Confirm frozen v1 SHA remains
    `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
    Inspect complete and isolated `jj diff --git`. Record generated package
    SHA/line count, parser test names/count, compile proof, two-generation
    identity, full test count, leak result, and the sole schema failure here.

### Acceptance criteria

- Frozen v1 parses strictly with explicit ownership and bounded failure paths.
- Historical generated code is deterministic, path-independent, compileable,
  and contains no dependency on current mutable type definitions.
- Removed `Settlement_Plan.city_plan` and every old fixed capacity remain
  accessible to a future script.
- Malformed, unsupported, ambiguous, or injection-shaped manifest input fails
  before writing code.
- Existing schema commands remain byte-compatible; new history check never
  writes.
- Schema version/manifests, codec/container, product state, and migration
  behavior remain untouched.

### Milestone 3D1 implementation verification

Implemented the strict owned parser and historical emitter in two new
`packages/fixture_schema` files. The CLI keeps the existing `generate` and
`check` argument paths unchanged and adds pinned v1 history generation/check
targets. The generated package is import-free and uses ordinal symbols derived
from sorted logical IDs, with adjacent logical-ID comments.

Verified:

- Frozen manifest SHA remains
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
- Generated v1 package is 1,771 lines, SHA
  `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`, and
  contains all 144 historical records.
- Generated `Fixture` has 142 fields. Compile-time probes import only the
  generated package and validate `Fixture.project` and historical
  `Settlement_Plan.city_plan` layout without constructing the large root.
- Focused tests
  `fixture_history_manifest_accepts_frozen_grammar`,
  `fixture_history_manifest_rejects_malformed_inputs`,
  `fixture_history_package_is_path_and_allocator_deterministic`, and
  `fixture_history_frozen_v1_is_complete` pass with zero leak diagnostics.
- `make fixture-history-generate` twice is byte-identical; `make
  fixture-history-check` and generated-package Odin check pass. `make check`
  passes.
- Full `make test` runs 451 tests with exactly the pre-existing frozen-schema
  mismatch. `make fixture-schema-check` reports only the audited line-23
  dynamic-vs-fixed `City_Plan.structures` mismatch. No source schema
  generation was run.

### Reviewer rejection — 2026-07-27

The valid-v1 path is green, but the fail-closed contract is not.

- The isolated implementation delta has exactly the intended seven files.
  Frozen v1 generates the claimed 144 records, 142 root fields, 1,771 lines,
  and SHA-256
  `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
  Double generation, history check, generated-package Odin check, `make
  check`, and the reported 451-test result reproduce.
- A disposable real parser/emitter probe shows all three inputs return
  `parsed=true`, `emitted=true`:

  - `enum u8` with value `256`;
  - persisted `builtin:cstring`, which portable `hs` cannot encode;
  - `raw_union=1`, which the emitter silently rewrites as an ordinary struct.

- A field tag containing the invalid escape `\q` is rejected, but returns
  `History_Error_Kind.Out_Of_Memory` and message `cannot own field`. Invalid
  syntax and allocation failure are therefore conflated.
- Current four focused tests do not compile/parse generated synthetic output,
  exercise enum base ranges, invalid identifiers/symbol collisions, supported
  builtin boundaries, non-plain struct detail, caps, two repository paths,
  atomic generation, or non-writing mismatch checks. String-presence
  assertions cannot establish the promised compileable hostile-input
  boundary.

M3D1 is not accepted. Preserve its valid-v1 output byte-for-byte and repair
only these parser/emitter/test boundaries in 3D1R before schema diff work.

## Milestone 3D1R — Harden historical parsing and generation

### Goal

Reject every manifest shape that cannot be represented faithfully by the
generated package and portable codec, report invalid syntax accurately, and
complete the missing deterministic/atomic proof without changing valid v1
bytes.

### Repair slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan,
   `history_manifest.odin`, `history_emit.odin`,
   `tests/fixture_history_test.odin`, `tools/fixture_schema/main.odin`,
   portable scalar discovery in `packages/hs/portable.odin`, and the complete
   generated v1 package. Inspect `jj status`, conflicts, complete
   `jj diff --git`, and isolated M3D1 diff before editing.
2. Scope repair to:

   - `packages/fixture_schema/history_manifest.odin`;
   - `packages/fixture_schema/history_emit.odin` only if shared validation or
     error propagation requires it;
   - `tests/fixture_history_test.odin`;
   - `tools/fixture_schema/main.odin` only for atomic/check test seams;
   - this plan.

   Valid v1 generation must not change. Do not modify Make targets, generated
   v1 content, source schema/version/manifests, current state, codec/container,
   migration scripts, editor behavior, or engine code.
3. Add failing regression cases before production changes for the exact
   reviewer probes:

   - enum value above unsigned base maximum, below signed base minimum, and
     negative under an unsigned base;
   - `cstring`, 128-bit integers, complex, and quaternion builtins;
   - every non-plain struct flag or modifier, beginning with `raw_union=1`;
   - invalid field tag/type escapes returning `.Invalid_Input`, never
     `.Out_Of_Memory`.

   Require parser failure before emitter or filesystem write.
4. Replace the broad builtin name list with the actual portable scalar
   contract: one-byte booleans; signed/unsigned integer storage of 1, 2, 4, or
   8 bytes; rune; 2/4/8-byte floats; UTF-8 Odin string. Include aliases such as
   `byte`, `rawbyte`, `int`, `uint`, and `uintptr` only where their runtime
   metadata satisfies that contract. Explicitly reject C strings, 128-bit
   integers, complex/quaternion types, and every unsupported builtin.
   Centralize this table so field, alias/distinct target, and enum-base
   validation cannot drift.
5. Validate enum declarations before emission:

   - base is a supported integer/rune builtin;
   - every value fits the base signedness and width;
   - unsigned bases reject negatives;
   - enum is nonempty;
   - existing duplicate name/value rejection remains.

   Test exact base-width edges for `u8` and `i8`, exact i64 edges, and the
   manifest-representable domain for `u64` and host `uint`
   (`0..max(i64)`, because manifest enum values are i64). Reject negative
   unsigned values and out-of-i64 text. Do not rely on the Odin compiler to
   reject generated garbage after it has been written.
6. Make struct-detail handling faithful. For 3D1 history, accept only the exact
   plain struct detail represented by the emitter:
   `packed=0`, `raw_union=0`, `no_copy=0`, `all_or_none=0`, `simple=0`, and all
   three alignment values `none`. Reject every other value unless the emitter
   gains exact syntax and tests for it; silently dropping semantics is
   forbidden.
7. Validate `using` fields as compileable embeddings. At minimum require a
   direct or resolved alias to a struct-compatible generated type; reject
   scalar, array, enum, distinct-scalar, or cyclic embeddings. Keep enum
   `using=1` rejected because frozen grammar does not represent it.
8. Separate unescape outcomes into invalid syntax and allocator failure.
   Unknown/trailing escapes, raw control bytes, invalid identifiers, malformed
   type expressions, and bad details return `.Invalid_Input` with exact source
   line and a path containing record plus field/enum when available.
   `.Out_Of_Memory` is reserved for a real allocator error. Preserve
   idempotent error/manifest cleanup.
9. Complete focused hostile-input tests:

   - reserved/invalid field and enum identifiers;
   - two logical IDs with the same basename still receive distinct stable
     symbols;
   - record, line/byte, array-length, and type-depth caps;
   - unresolved and unreachable aliases/distincts plus cycles;
   - all rejected builtins/details above;
   - deterministic output from identical manifests stored under two different
     temporary repository roots.

   Use bounded test data; do not allocate 65,536 fields merely to prove a cap
   already dominated by the byte limit.
10. Write synthetic generated output to a temporary package and parse it with
    `core:odin/parser`; combine this with real generated-package `odin check`
    to prove syntax and semantic compilation. Add compile-time probes for
    forward references, fixed arrays, explicit enum values, alias, distinct,
    and `using` struct embedding. String searches remain supplemental only.
11. Prove filesystem behavior in temporary repository roots:

    - generate installs complete output atomically;
    - a second generate is byte-identical;
    - history check on matching output performs no write;
    - corrupt existing output makes history check fail without modifying it;
    - failed parse/emission leaves existing output intact and removes or
      deterministically reuses only the exact temporary file;
    - zero, padded, missing, and future versions cannot escape the pinned v1
      paths.

    Refactor the smallest CLI helpers into testable package procedures if
    needed; do not duplicate production write logic in tests.
12. Run exact repaired history tests, then:

    - `make fixture-history-generate` twice;
    - `make fixture-history-check`;
    - `make check`;
    - `make test`;
    - `make fixture-schema-check`.

    The last two schema gates may retain only the known frozen mismatch. No
    other failure or leak warning is allowed. Clean generated root binaries.
13. Confirm both immutable hashes remain:

    - manifest:
      `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
    - generated v1:
      `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.

    Inspect complete and isolated `jj diff --git`. Record focused test names,
    accepted/rejected scalar boundaries, synthetic parse/real compile proof,
    atomic/non-writing evidence, test count, and leak result here.

### Acceptance criteria

- Parser accepts only shapes emitter and portable codec represent faithfully.
- Enum bodies fit declared base; unsupported scalars and non-plain structs fail
  before output.
- Invalid syntax is never mislabeled as allocation failure.
- Synthetic output parses, real history compiles, and collision/path behavior
  is deterministic.
- Generate is atomic; check never writes, including mismatch failure.
- Valid v1 manifest and generated package bytes remain unchanged.
- Schema, codec, migration, product state, and engine remain untouched.

### Milestone 3D1R implementation verification

Implemented hostile-path hardening in the historical manifest parser, focused
history tests, and the history CLI temporary-file cleanup. The parser now uses
one portable scalar table: one-byte booleans, signed/unsigned 1/2/4/8-byte
integers, rune, 2/4/8-byte floats, and UTF-8 Odin string. It rejects C strings,
128-bit integers, complex/quaternion values, unsupported builtins, non-plain
struct details, invalid enum ranges, empty enums, and non-struct `using`
embeddings before emission. Enum checks cover unsigned `0..max`, signed i8
edges, i64 storage, and the manifest-representable u64/host-uint ceiling.
Invalid escapes are `.Invalid_Input`; allocator failures retain
`.Out_Of_Memory`; error paths include record plus field/enum when available.

Focused coverage includes `fixture_history_manifest_accepts_frozen_grammar`,
`fixture_history_manifest_rejects_malformed_inputs`,
`fixture_history_synthetic_output_parses`,
`fixture_history_basename_symbols_are_distinct`,
`fixture_history_package_is_path_and_allocator_deterministic`, and
`fixture_history_frozen_v1_is_complete`. Synthetic output parses through
`core:odin/parser`; the generated historical package passes real `odin check`.
The hostile suite covers identifier/detail/type/record/line/byte/array/depth
limits, unresolved/unreachable/cyclic references, rejected scalar families,
and deterministic symbol mapping.

Temporary-root CLI proof: history generation succeeds twice with identical
bytes; matching history-check succeeds without a write; corrupt generated
output makes history-check fail while its hash remains unchanged; invalid
manifest input makes generation fail while the existing generated output stays
unchanged; zero, padded, future, and missing version arguments are rejected.

Gates: 453 tests pass except the pre-existing
`fixture_schema_production_graph_matches_draft` frozen-schema mismatch; no
leak diagnostics. `make check`, double history generation,
`make fixture-history-check`, and generated-package check pass. The only
schema gate failure remains the known current-vs-frozen dynamic/fixed array
line. Immutable hashes remain manifest
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12` and
generated v1
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.

### Milestone 3D1R reviewer verification

The repair delta is isolated to the historical parser, focused history tests,
one failed-write cleanup line in the CLI, and this plan. Frozen manifest and
generated-v1 files are absent from the repair delta. The centralized scalar
table, enum range checks, exact plain-struct detail policy, resolved `using`
checks, and invalid-escape classification close the original hostile probes.

Six focused history tests pass with zero leak diagnostics.
`make fixture-history-generate` twice and `make fixture-history-check` pass;
the immutable hashes above remain exact. `make check` passes. The full runner
executes 453 tests: 452 pass and only the known
`fixture_schema_production_graph_matches_draft` test fails.
`make fixture-schema-check` reports only the known line-23 fixed-to-dynamic
`architecture.City_Plan.structures` difference.

Independent temporary-root CLI probes also pass: double generation is
byte-identical; a matching check leaves inode, size, modification time, and
change time unchanged; a mismatching check preserves corrupt bytes; invalid
manifest generation preserves existing output and leaves no `.tmp` file; and
zero, padded, future, and missing versions are rejected.

3D1R is not accepted because deferred validation does not retain the source
line on `History_Field` or `History_Enum`. A five-line manifest containing
`Fixture.value: builtin:cstring` returns the correct `.Invalid_Input` and
`adriatic:src.Fixture.value` path but reports the owning type line 4 instead
of field line 5. A seven-line `u8` enum containing value 256 likewise reports
the enum type line 6 instead of value line 7. This violates the 3D1R
requirement for exact source line plus field/enum path and is not asserted by
the current tests.

## Milestone 3D1R2 — Preserve deferred diagnostic locations

### Repair slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, the full
   `packages/fixture_schema/history_manifest.odin`, and
   `tests/fixture_history_test.odin`. Inspect `jj status`, conflicts, the
   complete `jj diff --git`, and the isolated delta since the 3D1R reviewer
   snapshot before editing.
2. Scope changes to:

   - `packages/fixture_schema/history_manifest.odin`;
   - `tests/fixture_history_test.odin`;
   - this plan.

   Do not modify the emitter, CLI, Makefile, frozen manifest, generated v1,
   current schema/version, codec/container, product state, migration code, or
   engine code.
3. Retain the one-based source line on every parsed `History_Field` and
   `History_Enum`. Populate it at the successful append point. This metadata
   is parser-owned diagnostic state only: disposal and emission must remain
   behaviorally unchanged.
4. Use the retained field line for every deferred field failure, including an
   invalid/unresolved type and an invalid `using` embedding. Use the retained
   enum-entry line for range failures. Record/type/root graph failures keep
   their record/header lines.
5. Where a field or enum name is already available during immediate parsing,
   report a child path rather than only the owning record. Cover malformed
   `using`, duplicate field, invalid enum integer text, duplicate enum
   name/value, and cap failures. If the child name itself is malformed, keep
   the safest representable record-plus-child path without weakening input
   rejection.
6. Add exact regression assertions, not merely `line > 0` or substring-only
   checks:

   - unsupported `Fixture.value: builtin:cstring` fails on its field line with
     path `adriatic:src.Fixture.value`;
   - unresolved field type fails on its field line and exact field path;
   - scalar/array/enum/distinct/cyclic invalid `using` embeddings fail on
     their field lines and exact field paths, while direct struct and
     alias-to-struct embeddings remain accepted;
   - `u8` value 256 and negative value fail on their enum-entry lines and
     exact enum paths;
   - invalid out-of-i64 enum text, duplicate enum name/value, malformed
     `using`, and duplicate field name report their own lines and available
     child paths;
   - invalid field tag/type escapes remain `.Invalid_Input` on the exact field
     line and path.
7. Fill the cheap boundary-test omissions while touching the hostile table:
   reject `no_copy=1`, `all_or_none=1`, `simple=1`, and non-`none` values for
   each alignment key; accept exact i64 minimum/maximum and
   u64/host-uint `0..max(i64)` values; reject text outside the manifest i64
   domain. Do not expand the accepted grammar.
8. Run the exact focused history tests, then:

   - `make fixture-history-generate` twice;
   - `make fixture-history-check`;
   - `make check`;
   - `make test`;
   - `make fixture-schema-check`.

   Only the known frozen-schema mismatch may remain. Clean exact generated
   root binaries. Confirm the immutable manifest and generated-v1 hashes
   above and inspect complete plus isolated `jj diff --git`.
9. Record every corrected line/path probe, focused test names, full test count,
   leak result, gate result, immutable hashes, and touched files here. Do not
   begin 3D2.

### Acceptance criteria

- Deferred field and enum failures report the exact offending one-based line
  and canonical child path.
- Immediate failures use child paths whenever the child name is available.
- Fail-closed scalar/detail/enum/`using` behavior from 3D1R remains intact.
- Valid v1 manifest and generated package bytes remain unchanged.
- No schema, codec, migration, product-state, or engine change occurs.

### Milestone 3D1R2 implementation verification

Added parser-owned one-based `line` metadata to every `History_Field` and
`History_Enum`. Deferred field type and `using` failures now use the field
line; deferred enum range failures use the enum-entry line. Immediate malformed
using, duplicate field, invalid enum text, duplicate enum, and cap failures
use child paths whenever the child name is available. Disposal and emission
remain unchanged.

Exact regressions now prove the five-line unsupported
`adriatic:src.Fixture.value` failure is line 5 with that exact path, unresolved
field types retain line 5, invalid tag/type escapes retain lines 5/12 with
exact field paths, and the seven-line u8 value 256/negative cases retain line
7 with exact enum paths. Duplicate field/name, malformed using, invalid enum
text, out-of-i64 text, scalar/array/enum/distinct/cyclic using embeddings,
and all non-plain struct detail values are covered. Direct and alias-to-struct
using embeddings pass. Exact i64 minimum/maximum and u64/host-uint
`0..max(i64)` values pass.

Focused history coverage includes the frozen grammar, hostile parser,
synthetic Odin parser proof, collision symbols, allocator/path determinism,
and frozen-v1 completeness tests. Full suite: 453 tests, with only the known
`fixture_schema_production_graph_matches_draft` frozen-schema mismatch; no
leak diagnostics. Double history generation, history check, generated-package
check, and `make check` pass. `make fixture-schema-check` retains only the
known dynamic-versus-fixed array mismatch at line 23.

Immutable hashes remain manifest
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12` and
generated v1
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
Touched files for this repair: `packages/fixture_schema/history_manifest.odin`,
`tests/fixture_history_test.odin`, and this plan only. Generated root binaries
were cleaned.

### Milestone 3D1R2 reviewer acceptance

Conflict resolution leaves the 3D1R2 parser and test files byte-identical to
their reviewed pre-rebase state. The repair delta remains limited to
`history_manifest.odin`, `fixture_history_test.odin`, and this plan. Six
focused tests prove exact one-based field/enum lines and canonical child paths,
expanded scalar/detail/enum/`using` boundaries, idempotent cleanup, and zero
leaks. Double generation, history check, generated-package compilation, and
`make check` pass. Frozen manifest and generated-v1 hashes remain unchanged.

The fifth audit changes only the current candidate and expected full-suite
count. It does not change historical parsing. M3D1, M3D1R, and M3D1R2 are
accepted. Schema-diff work may begin.

## Milestone 3D2A — Produce canonical semantic schema diff

### Goal

Produce one owned, deterministic, read-only semantic delta from immutable
version 1 to the current AST-built candidate. Do not generate migration source
or execute a migration.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, the complete
   `packages/fixture_schema` package, `tools/fixture_schema/main.odin`,
   `tests/fixture_schema_test.odin`, both immutable v1 artifacts, and the
   current `Fixture` plus every fifth-audit type. Inspect `jj status`,
   conflicts, complete `jj diff --git`, and the isolated post-3D1R2 delta
   before editing.
2. Scope implementation to:

   - new `packages/fixture_schema/schema_diff.odin`;
   - new `tests/fixture_schema_diff_test.odin`;
   - `tools/fixture_schema/main.odin`;
   - `Makefile` only for one focused read-only diff-test target if useful;
   - this plan.

   Do not modify the historical parser/emitter, frozen manifest, generated v1,
   `FIXTURE_SCHEMA_VERSION`, current fixture/state structs, portable codec,
   container, adapter, migration source, editor behavior, or engine code.
3. Keep historical grammar fail-closed. Do not teach
   `history_parse_manifest` to accept `dynamic<T>` or any shape its historical
   emitter cannot reproduce. Add a separate semantic snapshot parser/model for
   diffing canonical schema text. Require the frozen input to pass the strict
   historical parser before converting it.
4. Define explicit owned model and idempotent disposal for snapshot, record,
   field, enum, change, and report data. Every successful returned string and
   dynamic allocation belongs to the caller-selected allocator. Nil allocators,
   allocation failures, malformed input, duplicates, and partial construction
   must fail without leaks.
5. Parse the complete canonical line grammar needed by both inputs:
   headers/root, struct/enum/alias/distinct records, escaped details/tags,
   builtins, logical IDs, fixed arrays, and current dynamic arrays. Enforce
   limits, exact keys/order, unique records/fields/enum names and values,
   resolved references, reachable graph, and complete input consumption.
   Reuse small package-local lexical helpers where safe; do not weaken the
   historical portable/emitter boundary.
6. Compare by logical record and child identity. Emit explicit change kinds
   for:

   - type add/remove/kind/detail;
   - field add/remove/type/tag/`using`/order;
   - enum add/remove/value;
   - root change.

   A wholly added or removed type produces one type change containing its full
   canonical body, not one redundant change per new child. For existing
   records, report child changes individually. Ignore only candidate schema
   header version and semantically irrelevant record/explicit-enum ordering;
   never hide field-order or root changes.
7. Give every change a readable stable ID derived only from kind and canonical
   path, for example
   `field-type:adriatic:packages/architecture.City_Plan.structures`.
   IDs must contain no array index, repository path, allocator address, source
   line, or hash. Sort by ID, reject duplicate/contradictory IDs, and require
   byte-identical report output across repeated runs and different temporary
   checkout paths.
8. Record two independent properties:

   - class: `supporting` or `state`;
   - migration policy: `automatic` or `script_required`.

   New types reachable only through a changed state field are supporting.
   Field additions/removals, fixed/dynamic crossings, root changes, and
   semantic kind/detail changes are state-bearing. All 16 fifth-audit state
   changes are `script_required`; the five wholly added types are supporting
   and do not create duplicate script obligations.
9. Expose one library procedure that receives frozen/candidate bytes, planned
   contiguous versions 1→2, allocator, and limits, then returns an owned report
   or one disposable path-aware error. Require `to == from + 1`, positive
   versions, frozen header/version agreement, and current candidate build
   success. Candidate header version 1 is intentionally ignored only for the
   semantic comparison because activation occurs later in 3F.
10. Add read-only CLI operation:
    `migration-diff 1 2 <repository-root> <zelda-engine-packages>`. It reads
    frozen v1, builds the current candidate through
    `build_manifest_report`, prints one deterministic machine-readable report,
    and writes no file. Zero, negative, padded, missing, skipped, same, or
    future version pairs fail before schema work. Existing generate/check and
    history commands retain behavior.
11. Use a versioned canonical report header with frozen/candidate SHA-256,
    source/target versions, change counts, and escaped change lines containing
    ID, kind, class, migration policy, path, before, and after. Hashes are
    evidence only, never change IDs. Report parser/validator must reject
    duplicate IDs, count mismatch, bad escaping, unknown kinds/classes/policy,
    unsorted entries, and contradictory changes.
12. Add focused synthetic tests for every change kind, fixed↔dynamic
    crossings, added-record collapsing, field ordering, header-only version
    difference, shuffled record/enum order, escaping, malformed/duplicate
    input, unresolved/unreachable/cyclic types, version pairs, deterministic
    output, allocator failure, and idempotent disposal. Require zero leak
    diagnostics.
13. Add one production test requiring exactly 21 fifth-audit changes: 16 state
    and five supporting. Require these exact stable IDs:

    - four `field-type` IDs for
      `architecture.City_Plan.{structures,parcels,alleys,lamps}`;
    - three `field-add` IDs for
      `farmland.Plan.{width,height,tradition}`;
    - `field-type:adriatic:packages/terrain.Project.structures`;
    - two `field-add` IDs for `adriatic:src.Farm_Instance.{scale_x,scale_z}`;
    - `field-remove:adriatic:src.Settlement_Plan.city_plan`;
    - `field-add:adriatic:packages/story.State.quest`;
    - `field-add:adriatic:packages/story.State.airfield_errand`;
    - three `field-add` IDs for
      `adriatic:src.Fixture.{tracked_quest_node,quest_tracking_suppressed,quest_tracking_revision}`;
    - five `type-add` IDs for `farmland.Tradition`, `quest.Node_ID`,
      `quest.State`, `quest.Status`, and `story.Airfield_Errand_Stage`.

    Require candidate metrics 1,371 lines, 149 records, 145 root fields, and
    SHA-256
    `eab829c2335fb7d61ceb5322b05c1f7b74f986aed30fead4d7837e975823a336`.
    Require all fifth-audit excluded names absent. No test may rewrite frozen
    v1 or generate version 2.
14. Run exact diff tests and the CLI twice, comparing byte identity. Then run:

    - `make fixture-history-generate` twice;
    - `make fixture-history-check`;
    - `make fixture-codec-test`;
    - `make check`;
    - `make test`;
    - `make fixture-schema-check`.

    Only the known frozen-schema assertion/check may fail. Confirm both
    immutable v1 hashes, source version 1, no repository write from the diff
    command, and no generated root binaries.
15. Inspect complete and isolated `jj diff --git`. Record API/ownership,
    report format, exact ordered IDs/classes/policies, hashes, focused/full
    counts, leaks, and gate results here. Do not scaffold or execute migration.

### Acceptance criteria

- One deterministic report contains exactly the 21 audited changes.
- All 16 state changes are distinct script obligations; five added types are
  supporting without redundant child changes.
- Historical parser/emitter contract and both immutable v1 artifacts remain
  unchanged.
- Diff command is strict, owned, allocator-safe, path-independent, and
  read-only.
- Source schema remains version 1; no migration source or runtime behavior
  exists.

### 3D2A execution record

Implemented only `packages/fixture_schema/schema_diff.odin`,
`tests/fixture_schema_diff_test.odin`, `tools/fixture_schema/main.odin`, and
this plan. The diff API owns snapshots, changes, reports, strings, and
path-aware errors in the caller-selected allocator with idempotent disposal.
The frozen input is parsed through the strict historical parser first; the
candidate uses a separate semantic parser supporting current dynamic arrays.
The report is versioned, escaped, sorted by stable `kind:path` ID, validated,
and rendered without repository writes. The CLI operation is:
`migration-diff 1 2 <repository-root> <zelda-engine-packages>`.

Production evidence:

- candidate: 1,371 lines, 149 records, 145 root fields;
- frozen SHA-256:
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- candidate SHA-256:
  `eab829c2335fb7d61ceb5322b05c1f7b74f986aed30fead4d7837e975823a336`;
- 21 changes: 16 `state/script_required`, then five
  `supporting/automatic`; no added-type child changes.

Canonical sorted IDs:

```text
field-add:adriatic:packages/farmland.Plan.height state script_required
field-add:adriatic:packages/farmland.Plan.tradition state script_required
field-add:adriatic:packages/farmland.Plan.width state script_required
field-add:adriatic:packages/story.State.airfield_errand state script_required
field-add:adriatic:packages/story.State.quest state script_required
field-add:adriatic:src.Farm_Instance.scale_x state script_required
field-add:adriatic:src.Farm_Instance.scale_z state script_required
field-add:adriatic:src.Fixture.quest_tracking_revision state script_required
field-add:adriatic:src.Fixture.quest_tracking_suppressed state script_required
field-add:adriatic:src.Fixture.tracked_quest_node state script_required
field-remove:adriatic:src.Settlement_Plan.city_plan state script_required
field-type:adriatic:packages/architecture.City_Plan.alleys state script_required
field-type:adriatic:packages/architecture.City_Plan.lamps state script_required
field-type:adriatic:packages/architecture.City_Plan.parcels state script_required
field-type:adriatic:packages/architecture.City_Plan.structures state script_required
field-type:adriatic:packages/terrain.Project.structures state script_required
type-add:adriatic:packages/farmland.Tradition supporting automatic
type-add:adriatic:packages/quest.Node_ID supporting automatic
type-add:adriatic:packages/quest.State supporting automatic
type-add:adriatic:packages/quest.Status supporting automatic
type-add:adriatic:packages/story.Airfield_Errand_Stage supporting automatic
```

Verification: five focused diff tests pass with no leak diagnostics; full
suite runs 488 tests with only the pre-existing frozen-schema mismatch at the
dynamic `City_Plan.structures` line. CLI output is byte-identical across two
runs. `make fixture-history-generate` twice, `make fixture-history-check`,
`make fixture-codec-test`, and `make check` pass. `make fixture-schema-check`
and `make fixture-schema-generate` fail only on the known required schema
version bump mismatch. No migration is scaffolded or executed; source schema
version and immutable v1 artifacts remain unchanged.

### 3D2A reviewer rejection

The isolated delta contains only the planned four files. The canonical report
is correct and deterministic: two direct CLI runs are byte-identical at 6,873
bytes and contain the exact 21 changes, 16 state obligations, five supporting
types, expected metrics, and expected hashes. The five focused tests,
`make check`, both history generations, history check, and codec test pass.
The full suite runs 488 tests with only the known frozen-schema mismatch.
Immutable v1 hashes remain unchanged.

3D2A is not accepted because its allocator contract fails under real fault
injection. A counting allocator first observed 12 allocations for the candidate
parser. Repeating the same valid parse while failing each allocation terminates
with an Odin optional-value trap at allocation 1 instead of returning an owned
error; the process exits by signal 5. The temporary probe and binary were
removed. The current nil-allocator assertion does not exercise partial
construction.

Static review found two related strictness gaps:

- change-value unescaping in `schema_diff_report_parse` discards
  `History_Unescape_Result.Out_Of_Memory` and reports `Invalid_Input`;
- `schema_diff_report_validate` does not explicitly reject out-of-range
  `Schema_Diff_Change_Kind` or `Schema_Diff_Class` discriminants. Crafted
  in-memory reports can therefore pass the validator through the default text
  and class branches even though the text parser rejects unknown spellings.

The required fail-at-every-allocation, idempotent-disposal, invalid-discriminant,
and path-independent tests are also absent. Do not begin 3D2B until 3D2AR is
accepted.

## Milestone 3D2AR — Repair semantic diff ownership and validation

### Goal

Preserve the accepted 21-change semantics and report bytes while making every
3D2A public path fail cleanly under allocation faults and closing the report
validator gaps. Do not scaffold or execute a migration.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, all of
   `packages/fixture_schema/schema_diff.odin`, its five tests, and the strict
   history ownership helpers it calls. Inspect `jj status`, conflicts, complete
   `jj diff --git`, and the isolated post-3D1R2 delta before editing.
2. Scope edits to:

   - `packages/fixture_schema/schema_diff.odin`;
   - `tests/fixture_schema_diff_test.odin`;
   - this plan.

   Change `tools/fixture_schema/main.odin` only if a repaired library contract
   requires a cleanup call there. Do not modify the historical grammar,
   emitter, immutable artifacts, schema version, fixture/state structs, codec,
   Makefile, migration source, editor behavior, or engine code.
3. Before changing production code, use tiny disposable Odin programs to prove
   the fork's checked syntax for map/dynamic-array creation, append growth, and
   string builders under a failing allocator. Remove every probe and binary.
   Do not guess at optional-return behavior.
4. Audit every allocation in candidate parsing, frozen conversion, graph
   validation, comparison scratch state, canonical-body construction, report
   building, report parsing, validation, and rendering. Replace unchecked
   `make`, map insertion/reserve, append growth, builder write, clone,
   concatenate, hash, and scratch allocation paths with the smallest checked
   helpers possible. On failure, unwind only owned state and return
   `Out_Of_Memory`; never panic, leak, double-free, or return partial success.
5. Make nil allocator rejection explicit at every public allocation entry
   point. Errors must remain disposable even when their path/message could not
   be cloned. Snapshot, error, change, and report disposers must remain
   idempotent on zero, partial, successful, and already-disposed values.
6. Fault-inject the separate candidate parser and the top-level
   `schema_diff_build_report`. First measure the successful allocation count,
   then fail every allocation index from zero through the final allocation.
   Every run must return normally, report failure, dispose safely twice, and
   leave zero outstanding allocations. If the already-accepted strict history
   parser itself traps during the top-level sweep, stop and report the exact
   allocation index before expanding scope into 3D1 code.
7. Apply the same exhaustive sweep to `schema_diff_report_parse` using one
   valid rendered report. Preserve the exact unescape status: malformed escape
   is `Invalid_Input`; allocation failure is `Out_Of_Memory`. Partial header
   and change ownership must unwind with zero outstanding allocations.
8. Make report validation reject every unknown enum discriminant explicitly:
   change kind, class, and migration policy. Reject nil/zero malformed reports,
   invalid kind/path-derived IDs, invalid class-policy combinations, duplicate
   or unsorted IDs, contradictory before/after shapes, and bad counts. Rendering
   must return failure for an invalid in-memory report instead of emitting
   text the parser would reject.
9. Pass caller limits consistently through graph and `using` resolution; do
   not fall back to `SCHEMA_DIFF_DEFAULT_LIMITS` inside a custom-limits parse.
   Add a focused custom-limit case proving the same limit policy is used from
   lexical validation through graph validation.
10. Expand focused tests to cover the originally required gaps:

    - fail-at-every-allocation sweeps and zero outstanding allocations;
    - disposing each public error/snapshot/report twice;
    - forged unknown kind/class/policy discriminants;
    - malformed report rendering as well as parsing;
    - a wholly added struct and enum with children collapsing to one type
      change and no child obligations;
    - byte-identical output when the same frozen/candidate bytes are evaluated
      from different working paths;
    - fixed-to-dynamic and dynamic-to-fixed crossings.

    Keep hostile input, ordering, escaping, graph, and version-pair coverage.
11. Re-run the production assertion unchanged. Require exactly 21 sorted IDs,
    16 `state/script_required`, five `supporting/automatic`, candidate metrics
    1,371/149/145, candidate SHA
    `eab829c2335fb7d61ceb5322b05c1f7b74f986aed30fead4d7837e975823a336`,
    and frozen SHA
    `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
    The canonical report must remain byte-identical to the reviewed 6,873-byte
    output.
12. Run the focused diff tests and the CLI twice, including two temporary
    path aliases, then run:

    - `make fixture-history-generate` twice;
    - `make fixture-history-check`;
    - `make fixture-codec-test`;
    - `make check`;
    - `make test`;
    - `make fixture-schema-check`.

    Only the known frozen-schema assertion/check may fail. Confirm immutable
    hashes, source version 1, no repository writes from the diff command, and
    no generated root binaries.
13. Inspect complete and isolated `jj diff --git`. Record exact fault-sweep
    allocation counts, zero-outstanding evidence, validator hostile cases,
    report byte identity, production counts/hashes, focused/full results, and
    gates here. Do not touch 3D2B.

### Acceptance criteria

- Every injected allocation failure returns normally with the correct error
  class and zero outstanding allocations.
- Report parser, validator, and renderer reject malformed and unknown values.
- The accepted 21-change semantics and 6,873-byte canonical report are
  unchanged.
- Historical artifacts, source schema version, codec behavior, and runtime
  behavior are unchanged.

### 3D2AR execution record

Implemented only the semantic diff library, its tests, and this plan. The
candidate parser now checks dynamic-array/map creation and append growth,
uses fixed-capacity builders for unescape/body/report paths, preserves OOM
status through report parsing, and immediately disposes partial snapshots
before returning. Report rendering validates the complete in-memory report
first and rejects unknown kind, class, policy, malformed IDs, and invalid
shapes without allocating an expected ID.

Fault evidence:

- candidate parser successful allocation count: 29;
- report parser successful allocation count: 15;
- every candidate and report allocation index was failed independently;
- every injected failure returned `Out_Of_Memory`, survived double disposal,
  and left zero outstanding allocations;
- malformed `\\q` remains `Invalid_Input`, and forged kind/class/policy
  discriminants are rejected by both validator and renderer.
- custom graph limits reject nested dynamic and oversized fixed-array inputs;
  candidate parsing accepts both fixed-to-dynamic and dynamic-to-fixed forms.

Production and identity evidence remain unchanged:

- candidate: 1,371 lines, 149 records, 145 root fields;
- frozen SHA-256:
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- candidate SHA-256:
  `eab829c2335fb7d61ceb5322b05c1f7b74f986aed30fead4d7837e975823a336`;
- two aliased CLI runs are identical at 6,873 bytes, with 21 changes,
  16 state changes, and five supporting changes;
- `make check`, history generation twice, history check, and codec test pass;
- full suite runs 491 tests with zero leak diagnostics and only the known
  frozen-schema mismatch; `fixture-schema-check` reports that same mismatch.

The requested top-level fault sweep was stopped at allocation index 0 as
directed: the already-accepted strict historical parser performs an
unchecked dynamic-array `make` and traps before the repaired diff library can
handle the failure. No 3D1 code was expanded, no migration was scaffolded,
and no generated root binaries or temporary probes remain.

### 3D2AR reviewer result

The isolated repair changes only `schema_diff.odin`, its tests, and this plan.
The candidate/report portion is accepted: all eight focused diff tests pass;
the 29-allocation candidate sweep and 15-allocation report sweep cover every
failure index, double disposal, correct OOM classification, and zero
outstanding allocations. Unknown discriminants, render rejection, bad escapes,
custom limits, and both array syntaxes are covered. Full suite runs 491 tests
with zero leak diagnostics and only the known frozen-schema mismatch.

Independent gates match the execution record. `make check`, history generation
twice, history check, and codec test pass. Two different repository path
aliases produce byte-identical 6,873-byte CLI output with the expected
1,371/149/145 metrics, 21/16/5 counts, and hashes. Immutable v1 hashes remain
`2f29187e...4abd12` and `e80c15bd...eab93c`.

The dependency boundary is real, but its exact evidence differs from the
execution record. A small valid top-level diff succeeds with 53 allocations.
Failing global allocation index 0 returns `Out_Of_Memory` normally. Failing
global index 1 terminates by signal 5 at
`history_manifest.odin:377`, where `history_unescape` grows an empty
`strings.Builder` through an unchecked `strings.write_byte`. The temporary
probe and binary were removed. Historical parsing also contains unchecked
scratch maps/slices and append growth, and child dynamic arrays are not
explicitly initialized with the caller allocator.

Do not reopen the accepted history grammar or merge this dependency repair into
3D2B. Repair historical ownership first, then close 3D2A with one separate
top-level sweep.

## Milestone 3D1R3 — Harden historical parser allocation ownership

### Goal

Make the immutable v1 parser and shared manifest hash return cleanly for every
allocation failure while preserving grammar, diagnostics, generated bytes, and
both immutable hashes. Do not change semantic diff behavior.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, all of
   `packages/fixture_schema/history_manifest.odin`,
   `packages/fixture_schema/history_emit.odin`,
   `tests/fixture_history_test.odin`, both immutable v1 artifacts, and the
   allocator helpers/tests in `fixture_schema_diff_test.odin`. Inspect
   `jj status`, conflicts, complete `jj diff --git`, and the isolated 3D1R3
   delta before editing.
2. Scope edits to:

   - `packages/fixture_schema/history_manifest.odin`;
   - only `history_manifest_sha256_hex` in
     `packages/fixture_schema/history_emit.odin`;
   - `tests/fixture_history_test.odin`;
   - this plan.

   Do not modify historical grammar/detail rules, emitter ordering or generated
   text, immutable artifacts, `schema_diff.odin`, diff tests, CLI, Makefile,
   schema version, fixture/state structs, codec, migration source, editor
   behavior, or engine code.
3. Before production edits, use tiny disposable Odin programs to prove checked
   syntax for fixed-capacity builders, map/slice/dynamic-array construction,
   and `append_elem` ownership transfer in this Odin fork. Remove every probe
   and binary. Reuse the simplest proven pattern; no speculative allocator
   wrapper.
4. Reject a nil caller allocator explicitly in `history_parse_manifest` with
   a disposable `Out_Of_Memory` error whose borrowed fallback path/message
   remain safe. Keep `history_error_dispose`, `history_record_dispose`, and
   `history_manifest_dispose` idempotent for zero, partial, successful, and
   already-disposed values.
5. Replace `history_unescape`'s growable empty builder with a checked
   caller-allocator builder preallocated to exactly `len(raw)` bytes. No write
   may grow it. Preserve byte-for-byte escaping and the distinction between
   malformed escape `Invalid_Input` and allocation failure `Out_Of_Memory`.
6. Make parser container ownership explicit and checked:

   - initialize the root records array in the caller allocator;
   - preallocate the record index map for the hard record limit so insertion
     cannot allocate later;
   - initialize every record's field and enum arrays in the caller allocator,
     including empty bodies;
   - use checked `append_elem` for records, fields, and enum entries;
   - transfer ownership only after successful append and dispose the local
     value exactly once on failure.

   Any failed root/detail/name/tag/type/container allocation must unwind all
   preceding owned state and return `Out_Of_Memory` without changing the
   semantic line/path selected for malformed input.
7. Make `history_validate_manifest` scratch ownership checked: record-index
   map, `using` state, DFS state, and reachable array. Preallocate maps to
   their bounded maximum, return `Out_Of_Memory` on construction failure, and
   free each successful scratch allocation once. Keep reachability, cycle,
   enum-width, `using`, duplicate, and detail behavior identical.
8. Harden only the shared `history_manifest_sha256_hex` allocation boundary in
   the emitter file. Use one checked fixed 64-byte builder so the 32-byte digest
   cannot trigger growth; return `false` with no owned output on allocation
   failure. Do not touch `history_emit_package` in this milestone.
9. Add a caller-selected counting/failing allocator test fixture in the history
   tests. Use a compact valid manifest that reaches struct, enum, alias,
   distinct, `using`, fixed-array, escaped-detail, escaped-tag, field, and enum
   paths. First record the successful parser allocation count; then fail every
   allocation index independently. Every run must:

   - return normally;
   - fail with `Out_Of_Memory`;
   - survive two manifest and error disposal calls;
   - leave zero outstanding caller allocations.

   Deliberately keep `context.allocator` different from the supplied allocator
   so record child arrays cannot silently allocate from context.
10. Sweep every allocation of `history_manifest_sha256_hex` separately. Success
    must return the exact 64-byte digest in the caller allocator; every failure
    must return `false`, empty output, and zero outstanding allocations. Add
    explicit nil-allocator coverage.
11. Re-run existing hostile history tests unchanged and require the same exact
    line/path/error kinds for malformed escapes, duplicates, bounds, `using`,
    unresolved/unreachable/cyclic graphs, caps, trailing input, and partial
    records. Add direct double-disposal checks where absent.
12. Run focused history tests, then:

    - `make fixture-history-generate` twice;
    - `make fixture-history-check`;
    - `make check`;
    - `make fixture-codec-test`;
    - `make test`;
    - `make fixture-schema-check`.

    Only the known frozen-schema assertion/check may fail. Require frozen
    manifest SHA `2f29187e...4abd12`, generated-v1 SHA
    `e80c15bd...eab93c`, source version 1, byte-identical generation, no
    formatter spill, and no root binaries.
13. Inspect complete and isolated `jj diff --git`. Record parser/hash successful
    allocation counts, exhaustive failure results, caller-allocator proof,
    diagnostic identity, hashes, focused/full counts, leaks, and gates here.
    Do not run or edit the 3D2 top-level sweep yet.

### Acceptance criteria

- Historical parse and hash never trap or leak under any injected allocation
  failure.
- Every owned record, child array, string, scratch container, and digest uses
  the caller-selected allocator.
- Historical grammar, diagnostics, generation, and immutable bytes are
  unchanged.
- No semantic diff, migration, schema-version, codec, or runtime behavior
  changes.

### M3D1R3 execution record

Accepted for handoff to the separate M3D2AR2 top-level sweep.

- Scope stayed isolated to `history_manifest.odin`, the shared hash function,
  `fixture_history_test.odin`, and this plan. No Makefile, diff, CLI, codec,
  schema, generated source, editor, or engine changes were made.
- Historical parser success used 39 caller-allocator allocation attempts;
  every index failed independently and returned normal `.Out_Of_Memory`.
  Successful, partial, failed, and repeated manifest/error disposal left zero
  outstanding allocations. Context and caller allocators were different.
- Shared SHA-256 success used one caller allocation; its failure returned
  `false` with empty output and zero outstanding allocations. Nil allocator
  cases passed for both parser and hash.
- Focused allocator tests: 2 passed. Full suite: 493 tests, 492 passed; the
  only failure remains the known frozen-schema mismatch in
  `tests.fixture_schema_production_graph_matches_draft`.
- `make fixture-history-generate` twice, `make fixture-history-check`,
  `make check`, and `make fixture-codec-test` passed. History generation was
  byte-identical. The known `make fixture-schema-check` mismatch remains the
  dynamic `City_Plan.structures` versus frozen `array[256]` difference.
- Immutable hashes remain frozen manifest
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12` and
  generated v1 source
  `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
- Generated root binaries were removed; no leak diagnostics appeared.

### M3D1R3 reviewer acceptance

The isolated delta contains only the four planned files. Parser changes
explicitly own root records and every record's field/enum arrays in the caller
allocator, check map/slice creation and append transfer, use a fixed-capacity
unescape builder, and preserve idempotent partial cleanup. Validation scratch
state is checked. The shared hash now has one checked 64-byte allocation and no
growth path. Historical grammar and emitter body are unchanged.

Both focused tests pass independently. The parser test sweeps every successful
path allocation while `context.allocator` differs from the supplied allocator;
all failures require `Out_Of_Memory`, double disposal, and zero outstanding
allocations. The hash test applies the same ownership checks to its single
allocation. Full suite runs 493 tests with zero leak diagnostics and only the
known frozen-schema mismatch.

Independent `make check`, history generation twice, history check, codec test,
and expected schema-check failure match the execution record. Frozen manifest
and generated-v1 hashes remain
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`
and
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
M3D1R3 is accepted. No historical work remains before the final top-level
semantic diff sweep.

## Milestone 3D2AR2 — Close top-level semantic diff ownership

### Goal

Prove the complete frozen-parse → candidate-parse → semantic-report path owns
and unwinds every allocation. This is the final 3D2A gate. Do not scaffold a
migration.

### Next slave implementation plan

1. Read `AGENTS.md`, RTK instructions, this plan, complete
   `schema_diff.odin`, strict history parser/hash, all history/diff fault
   allocator tests, and both immutable v1 artifacts. Inspect `jj status`,
   conflicts, complete `jj diff --git`, and the isolated post-M3D1R3 delta
   before editing.
2. Scope the expected edit to:

   - `tests/fixture_schema_diff_test.odin`;
   - this plan.

   Modify `packages/fixture_schema/schema_diff.odin` only if the new sweep
   exposes a concrete unchecked allocation or cleanup defect. Do not modify
   history parser/emitter, frozen/generated artifacts, CLI, Makefile, schema
   version, fixture/state structs, codec, migration source, editor behavior, or
   engine code.
3. Reuse the existing `Fixture_Schema_Diff_Fault_Allocator`; do not add a
   second allocator implementation. Keep `context.allocator` different from
   the supplied fault allocator so accidental context ownership fails loudly.
4. Add compact frozen and candidate manifest constants dedicated to the
   top-level sweep. Frozen input must remain valid strict v1 grammar. Together
   they must reach:

   - root and embedded structs with a valid `using` field;
   - enum, alias, and distinct records;
   - nested fixed arrays in frozen input and a fixed-to-dynamic field change in
     candidate input;
   - one existing field type change;
   - one field addition and one field removal;
   - one wholly added supporting record with children;
   - one wholly removed record;
   - escaped detail/tag/body text;
   - sorted multi-change report construction.

   Every record must remain reachable in its own snapshot. Assert the exact
   synthetic change IDs/classes/policies before fault injection so the fixture
   cannot silently stop exercising a branch.
5. Build this report once with the counting allocator and record the successful
   allocation count. Dispose successful report and error twice and require zero
   outstanding allocations. Then fail every successful-path allocation index
   independently. Every run must:

   - return normally with `ok == false`;
   - return `Schema_Diff_Error_Kind.Out_Of_Memory`;
   - survive two report and error disposal calls;
   - leave zero outstanding caller allocations;
   - never alter either borrowed input buffer.

6. Add explicit top-level nil-allocator coverage. Also render one successful
   synthetic report through the fault allocator: success must own output in the
   supplied allocator; failing each render allocation must return `false`,
   empty output, and zero outstanding allocations. Keep report ownership
   separate from render-output ownership.
7. Do not add a dynamic-to-fixed top-level assertion. Frozen v1 grammar
   intentionally rejects dynamic arrays because the immutable v1 emitter
   cannot reproduce them. Current tests already prove both candidate forms
   parse; production v1→v2 correctly exercises fixed-to-dynamic. Future
   version history grammar must own the reverse-direction test when such a
   frozen format exists. Do not weaken the v1 parser to satisfy an impossible
   synthetic case.
8. Re-run the existing candidate-parser and report-parser sweeps unchanged.
   Require their successful counts and exhaustive OOM/zero-outstanding
   behavior to remain stable unless a justified production repair changes an
   allocation boundary. Keep forged-discriminant, escaping, custom-limit,
   hostile graph, and version-pair tests green.
9. Re-run the production assertion unchanged. Require exactly:

   - 1,371 candidate lines, 149 records, 145 root fields;
   - candidate SHA
     `eab829c2335fb7d61ceb5322b05c1f7b74f986aed30fead4d7837e975823a336`;
   - frozen SHA
     `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
   - 21 changes, 16 `state/script_required`, five
     `supporting/automatic`;
   - byte-identical 6,873-byte rendered report.

10. Run focused diff tests and the CLI twice through different temporary
    repository path aliases. Confirm identical output and no repository writes.
    Then run:

    - `make fixture-history-generate` twice;
    - `make fixture-history-check`;
    - `make fixture-codec-test`;
    - `make check`;
    - `make test`;
    - `make fixture-schema-check`.

    Only the known frozen-schema assertion/check may fail. Confirm both
    immutable hashes, source version 1, and no generated root binaries.
11. Inspect complete and isolated `jj diff --git`. Record top-level and render
    successful allocation counts, exact synthetic changes, exhaustive failure
    results, production report identity, focused/full counts, leaks, hashes,
    and gates here. Do not touch 3D2B.

### Acceptance criteria

- Top-level report construction and rendering survive every injected
  allocation failure with correct ownership and zero leaks.
- Strict v1 grammar remains unchanged.
- Canonical production report remains exactly 6,873 bytes and 21/16/5.
- 3D2A becomes accepted; 3D2B remains untouched.

### M3D2AR2 execution record

Accepted. The final top-level sweep touched only
`tests/fixture_schema_diff_test.odin` and this plan; no production repair was
needed.

- Dedicated valid v1 frozen/candidate fixtures exercise root and embedded
  `using` structs, enum, alias, distinct, nested fixed arrays, fixed-to-
  dynamic crossing, existing field type change, field add/remove, one added
  supporting struct with children, one removed record, escaped detail/tag/
  body text, and sorted report construction. Exact synthetic changes are:
  `enum-add:adriatic:test.src.Mode.On`,
  `field-add:adriatic:test.src.Root.new_field`,
  `field-remove:adriatic:test.src.Inner.remove_me`,
  `field-tag:adriatic:test.src.Root.tagged`,
  `field-type:adriatic:test.src.Root.grid`,
  `field-type:adriatic:test.src.Root.payload`,
  `type-add:adriatic:test.src.Added`, and
  `type-remove:adriatic:test.src.Removed`. Counts are 7 state/script-required
  and 1 supporting/automatic. No dynamic-to-fixed assertion was added, per
  the v1 grammar constraint.
- Top-level report success used 256 caller-allocator allocation attempts;
  every index failed independently with normal `.Out_Of_Memory`, double
  report/error disposal, unchanged borrowed inputs, and zero outstanding
  allocations. Nil allocator coverage passed.
- Render success used 1 caller-allocator allocation attempt; its exhaustive
  failure returned `false` with empty output and zero outstanding allocations.
  Successful output matched the context-allocator baseline. Report and
  output ownership stayed separate; nil render allocator coverage passed.
- Focused diff tests: 5 passed. Full suite: 495 tests, 494 passed; the only
  failure remains `tests.fixture_schema_production_graph_matches_draft`, the
  known frozen `array[256]` versus generated `dynamic` mismatch. No leak
  diagnostics appeared.
- Two temporary repository path aliases produced byte-identical 6,873-byte
  migration-diff output with no repository writes. The canonical report remains
  21 changes, 16 state, 5 supporting, with candidate metrics 1,371/149/145
  and candidate SHA
  `eab829c2335fb7d61ceb5322b05c1f7b74f986aed30fead4d7837e975823a336`.
- `make fixture-history-generate` twice, `make fixture-history-check`,
  `make fixture-codec-test`, and `make check` passed. `make fixture-schema-check`
  reports only the known frozen-schema mismatch. Immutable hashes remain
  frozen manifest
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12` and
  generated v1 source
  `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
- Generated root binaries and temporary aliases were removed. 3D2B remains
  untouched.

### M3D2AR2 reviewer acceptance

Accepted. The isolated delta from the accepted M3D1R3/M3D2AR baseline is only
the two planned files: 225 test lines and the execution record above. No
production code, manifest, generated history, codec, or version changed.

Independent review confirmed that the synthetic inputs are valid under both
strict parsers and reach the whole public operation: frozen-history parse,
candidate parse, graph validation, semantic report construction, sorting,
ownership transfer, and rendering. The exact eight-change assertion consumes
every expected ID and checks its 7/1 state/supporting classification.

Independent execution passed the five focused tests. The full suite ran 495
tests with 494 passing and only the known frozen-schema assertion failing.
`make check`, `make fixture-codec-test`, double history generation, history
check, and generated-history compilation passed. Schema check stopped only at
the known first fixed-to-dynamic crossing. Two repository aliases produced
byte-identical 6,873-byte reports with the exact 21/16/5 counts. Frozen and
generated-history hashes remain
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`
and
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
No leak diagnostics or review findings remain. M3D2A is accepted.

## Milestone 3D2B1 — Build the in-memory migration scaffold contract

### Status

Next slave handoff. This is deliberately in-memory only. Filesystem installation
and the real product stub are split into 3D2B2 so AST semantics and no-overwrite
installation are not debugged in one change.

### Goal

Consume an already accepted `Schema_Diff_Report`, render one deterministic Odin
migration scaffold, parse that source through `core:odin/parser`/`ast`, and
validate its immutable metadata against the report. The production v1→v2
render must expose exactly the 16 state changes as unresolved obligations.
The five supporting additions are context, not separate obligations.

### Allowed files

- add `packages/fixture_schema/migration_scaffold.odin`;
- add `tests/fixture_migration_scaffold_test.odin`;
- update only this plan with execution evidence.

Do not touch the CLI, Makefile, `src`, codec, manifests, generated v1 history,
schema version, or any existing schema-diff implementation in this milestone.
If an accepted 3D2A API is insufficient, stop and report the exact missing
contract instead of changing it.

### First proof and ABI decision

Completed before implementation. Locked Odin rejects
`^const fixture_v0001.Fixture`. Use the supported value-parameter directive
instead:

```odin
#by_ptr historical: fixture_v0001.Fixture
```

A disposable compiler probe proved that Odin rejects direct field assignment,
fixed-array element assignment, taking `&historical`, and slicing a fixed array
from this parameter. LLVM IR passes the argument as one pointer and emits no
call-site structure copy. This gives immutable value semantics with pointer ABI
for frozen v1 without exposing a mutable `^fixture_v0001.Fixture`.

The probe also confirmed that a `[dynamic]` element remains mutable through its
descriptor. Generated frozen v1 contains no `[dynamic]` fields, so this does
not weaken the concrete 1→2 contract. Milestone 6 must reevaluate the
historical-view contract before generalizing scaffold generation to a version
whose frozen root contains pointer-backed mutable collections. Do not claim
that `#by_ptr` is deep const for arbitrary future schemas.

### Library model and ownership

Add these product-neutral schema-tool concepts in package `fixture_schema`;
names may follow existing package style, but their responsibilities may not be
merged:

- a three-value resolution kind: `Unresolved`, `Automatic`, and `Scripted`;
- an owned resolution record containing one owned change ID and its kind;
- an owned scaffold model containing caller allocator, from/to versions, and
  the ordered resolution records;
- a bounded limits record with at least maximum input bytes and maximum
  obligations;
- a scaffold error kind with `None`, `Invalid_Input`, `Limit_Exceeded`, and
  `Out_Of_Memory`, plus owned path/message and source line/column;
- public idempotent scaffold/error disposal;
- one renderer from `^Schema_Diff_Report` to caller-owned source;
- one AST parser from borrowed source to the owned scaffold model;
- one validator from scaffold model plus accepted report to success/error.

The renderer must first run the accepted report validator. It rejects nil
reports, nil allocators, non-contiguous or out-of-range versions, malformed or
unsorted changes, duplicate IDs, and forged enum discriminants. It selects
only `.State` changes. It must not mutate or retain the report.

The AST parser borrows source only for its call. Check byte and UTF-8 limits
before constructing an AST. Build one in-memory `ast.File`, use a
`parser.Parser` with silent diagnostic handlers, and reject any tokenizer or
parser syntax count. Keep the AST in temporary allocator storage and copy every
retained string into the supplied allocator; no AST pointer may escape. Do not
parse metadata with substring search, regex, comments, or a second handwritten
Odin grammar.

Caller-owned results must be empty and safely disposable on every failure.
Nil allocators return normal `.Out_Of_Memory`. Preserve `.Out_Of_Memory`
through partial model/error construction. All source and report inputs remain
borrowed and unchanged.

### Exact rendered source contract

For the accepted report pair 1→2, render a normal package-main source file with:

- required import alias `fixture_v0001` bound exactly to
  `../packages/fixture_history/v0001`;
- required `core:mem` import;
- immutable literal declarations named
  `FIXTURE_MIGRATION_V0001_TO_V0002_FROM_VERSION`,
  `FIXTURE_MIGRATION_V0001_TO_V0002_TO_VERSION`, and
  `FIXTURE_MIGRATION_V0001_TO_V0002_RESOLUTIONS`;
- literal from/to values `1` and `2`;
- a `[?]Fixture_Migration_Resolution` compound literal containing exactly the
  16 canonical state IDs from 3D2A, in report order, once each, using direct
  named-field entries of the form
  `Fixture_Migration_Resolution{change_id = "...", kind = .Unresolved}`;
- procedure `fixture_migrate_v0001_to_v0002` with parameters
  `#by_ptr historical: fixture_v0001.Fixture`,
  `tentative: ^Fixture`, and `allocator: mem.Allocator`, returning
  `Fixture_Migration_Error`;
- a compile-oriented stub body that explicitly consumes the three parameters
  and returns `Fixture_Migration_Error{kind = .Unresolved}`.

`Fixture_Migration_Resolution` and `Fixture_Migration_Error` are intentionally
references to product runtime types installed in 3D2B2. Do not define shadow
copies in the generated source or in the schema package.

Derive the zero-padded symbol/procedure names from validated versions. Use one
fixed-capacity or exactly-sized builder and the supplied allocator. Do not use
repository paths, source-file absolute paths, current time, map iteration,
pointer values, comments from the input report, or context allocator in the
rendered bytes.

### AST validation contract

The parser/validator must enforce:

- package name exactly `main`;
- required history alias/path and `core:mem` import exactly once;
- each reserved metadata symbol and the migration procedure exactly once;
- from/to metadata is immutable `::` and a plain canonical decimal literal,
  not a variable, alias, cast, expression, or comment;
- positive versions in `1..9999`, exactly contiguous, and equal to the
  accepted report;
- the resolution declaration is the expected inferred-length array type;
- every entry is a direct `Fixture_Migration_Resolution` literal with literal
  `change_id` and selector kind;
- IDs are strict ascending report order, unique, and exactly equal to the
  report's state IDs; supporting changes are absent;
- only `Unresolved`, `Automatic`, and `Scripted` are recognized;
- the procedure name, required `#by_ptr` historical value parameter, historical
  type, current `Fixture` pointer, explicit allocator, and return type are
  exact; a mutable historical pointer is rejected.

Do not validate the migration body beyond valid Odin syntax. Extra imports,
private constants/types, and helper procedures must be allowed so a designer or
agent can script ambiguity resolution on top of the generated file. They may
not redefine a reserved metadata symbol or the migration entry procedure.
Comments are ignored and can never satisfy metadata or resolution obligations.

Structural validation accepts all three known resolution kinds. The initial
renderer emits only `.Unresolved`; a later readiness gate, not this parser,
will reject unresolved work. This separation is required so edited scripts are
validatable without regenerating them.

### Required tests

Use the already reviewed synthetic and production semantic reports. Add focused
tests that prove:

1. two independent render calls with distinct allocators are byte-identical;
2. the production render parses and validates as exactly 1→2 with 16
   `.Unresolved` state IDs and no supporting IDs;
3. the existing eight-change synthetic report produces exactly seven
   obligations and exact IDs despite escaped detail/tag text in the report;
4. replacing resolution kinds with known `Automatic`/`Scripted`, adding a
   harmless import/helper, and replacing the procedure body still validates;
5. comments that spell valid metadata or IDs do not satisfy missing AST nodes;
6. missing, duplicate, unknown, unsorted, supporting, and extra resolution IDs
   fail with the offending metadata path and line;
7. same, skipped, zero, negative, padded, overflow, and future from/to literals
   fail; computed or mutable metadata fails;
8. wrong package, history alias/path, import, procedure name, historical
   `#by_ptr` directive/type, mutable historical pointer, current type, allocator
   type, or return type fails;
9. malformed Odin, invalid UTF-8, input/obligation limit boundaries, and forged
   in-memory report/resolution discriminants fail normally;
10. report/source buffers remain unchanged and are never retained;
11. renderer and owned-model construction survive fail-at-every-caller-
    allocation sweeps, nil allocators, and double disposal with zero
    outstanding allocations.

Keep core parser AST allocations under the temporary allocator; the injected
allocator sweep covers only the public owned-result contract. Do not expose a
fake allocator guarantee for `core:odin/parser`.

Run the focused scaffold tests, the five accepted semantic-diff tests,
`make check`, `make fixture-codec-test`, double history generation/history
check, full tests, and schema check. Expected full/schema failure remains only
the frozen production mismatch. Remove generated root binaries.

### Acceptance criteria

- Deterministic source contains exactly 16 initial unresolved state
  obligations.
- Core Odin AST validation locks metadata and entry signature while allowing
  real scripted helpers/body edits.
- Every public owned result has explicit, idempotent allocator ownership.
- No filesystem write, migration execution, source schema change, codec change,
  or v2 artifact exists.

### Execution evidence — 3D2B1

Implemented in exactly the allowed code files:

- `packages/fixture_schema/migration_scaffold.odin` — deterministic renderer,
  temporary-AST parser, strict metadata/signature validation, owned model and
  idempotent error/model disposal;
- `tests/fixture_migration_scaffold_test.odin` — production 16-state render,
  seven-state synthetic render, known-kind/body/helper edits, dynamic padded
  names, forged discriminants, hostile AST cases, limits, UTF-8, and
  fail-at-every-allocation ownership sweeps.

The historical parameter is locked as
`#by_ptr historical: fixture_v0001.Fixture`; no mutable historical pointer or
`^const` weakening was introduced. Focused scaffold tests and five accepted
semantic-diff tests pass. `make check`, `make fixture-codec-test`, two
consecutive history generations, and history check pass. Full tests execute
500 cases with 499 passing; the sole failure is the pre-existing frozen-schema
mismatch (`array[256]` versus generated `dynamic`). Schema check reports that
same mismatch only. Generated root binaries were removed.

### Reviewer rejection — 3D2B1

Scope and baseline behavior are clean: the isolated change contains only the
two allowed code files plus this plan. Independent execution passes all ten
focused scaffold/diff tests, `make check`, codec test, double history
generation, history check, and immutable hashes. Full tests run 500 cases with
only the known frozen-schema mismatch. No leak diagnostics appeared.

3D2B1 is not accepted because four locked contracts remain open:

1. `Migration_Scaffold_Resolution` discards its AST source position.
   `migration_scaffold_validate` therefore constructs every version/count/ID/
   kind mismatch with an empty `tokenizer.Pos`, which becomes line 1, column 1.
   Unknown, extra, reordered, and future-report failures cannot identify the
   offending metadata line as required.
2. `migration_scaffold_parse` compares obligation count only with the
   caller-provided limit. A caller can set that above
   `MIGRATION_SCAFFOLD_MAX_OBLIGATIONS` and bypass the declared hard cap.
   `migration_scaffold_render` does not count state obligations against that
   cap at all, so it can emit source rejected by the default parser.
3. Reserved-name scanning ignores any `ast.Value_Decl` with more than one
   name. A multi-name declaration can therefore redefine a reserved migration
   metadata symbol without the structural validator noticing. Required import
   aliases also need collision checks so another `mem` or historical alias
   cannot shadow the locked bindings.
4. The test suite does not complete the required public-contract proof. The
   edited helper/body source is parsed but never validated; future 2→3 metadata
   is never validated against the accepted 1→2 report; nil renderer, successful
   double scaffold disposal, invalid/over-hard limits, reserved-symbol/import
   collisions, real source-line diagnostics, and independent borrowed-buffer
   snapshots are absent. Successful-path allocation sweeps do not exercise
   owned diagnostic construction.

## Milestone 3D2B1R — Close the scaffold contract

### Required repair

Touch only `packages/fixture_schema/migration_scaffold.odin`,
`tests/fixture_migration_scaffold_test.odin`, and this execution plan. Do not
start 3D2B2.

- Retain line/column for each resolution and for from/to/resolution metadata in
  the owned scaffold model. Keep file strings and AST pointers temporary.
  Validation errors must use the exact stored position for a bad resolution or
  version and the resolution declaration position for missing/extra count.
- Reject negative limits and any custom limit above its compile-time maximum.
  Enforce both caller limit and
  `MIGRATION_SCAFFOLD_MAX_OBLIGATIONS` before allocation. Count state changes in
  the renderer and reject a valid report above the hard cap with
  `.Limit_Exceeded`.
- Inspect every name in every `ast.Value_Decl`, not only single-name
  declarations, when detecting reserved metadata/procedure collisions. The
  required declaration itself must still have exactly one name. Reject any
  second import that binds `mem` or the derived historical alias, regardless
  of its path; still allow unrelated imports and helper declarations.
- Preserve deterministic bytes and the locked
  `#by_ptr historical: fixture_v0001.Fixture` signature. Do not inspect or
  restrict the scripted procedure body beyond Odin syntax.

### Required proof

- Assert exact non-1 source line/column for wrong resolution ID/kind, future
  version mismatch, and resolution count mismatch.
- Prove default boundary, custom lower boundary, custom-above-hard rejection,
  and hard-cap-plus-one rejection for both parse and render.
- Prove multi-name reserved redeclaration and `mem`/history alias collisions
  fail, while unrelated imports/helpers/body edits parse and validate.
- Validate a parsed 2→3 scaffold against the accepted 1→2 report and require a
  positioned version error.
- Clone report fields and source bytes independently before render/parse and
  compare after; do not compare two aliases of the same storage.
- Add nil renderer coverage; double-dispose successful scaffold and all errors.
  Sweep caller allocation failures for one valid parse/render and one
  positioned invalid-source diagnostic. Every failure returns an empty,
  disposable result with zero outstanding allocations.

Run the repaired focused tests, the five accepted diff tests, `make check`,
codec test, double history generation/history check, full tests, and schema
check. Expected repository failure remains only the frozen-schema mismatch.
Remove generated root binaries.

### Acceptance criteria

- Validation failures identify real AST metadata positions.
- Hard caps cannot be raised by custom limits and renderer output is
  default-parseable by construction.
- Reserved symbols/import aliases cannot be shadowed through AST shapes the
  scanner ignores.
- Public ownership, nil allocator, borrowed input, and extensibility contracts
  are directly tested.
- 3D2B2 remains untouched.

### Execution evidence — 3D2B1R

Repaired in exactly the allowed files:

- `packages/fixture_schema/migration_scaffold.odin` now retains source
  positions in owned metadata/resolution records, enforces negative/custom
  limits against both caller and compile-time caps, counts renderer state
  obligations, and scans every declaration name plus reserved import alias;
- `tests/fixture_migration_scaffold_test.odin` now proves positioned ID/kind/
  version/count diagnostics, default/lower/over-hard/plus-one limits for parse
  and render, multi-name/import collisions, independent buffers, nil and
  double disposal, and valid/invalid diagnostic allocation sweeps.

The locked signature remains `#by_ptr historical: fixture_v0001.Fixture`.
Six focused scaffold tests and five accepted semantic-diff tests pass with no
leak diagnostics. `make check`, the real fixture codec test, two consecutive
history generations, and history check pass. Full tests execute 501 cases
with 500 passing; the sole failure is the pre-existing frozen-schema mismatch
(`array[256]` versus generated `dynamic`). Schema generation remains refused,
and schema check reports that same mismatch only. Generated root binaries were
removed. 3D2B2 remains untouched.

### Reviewer acceptance — 3D2B1R

Accepted. The isolated repair changes only the two allowed implementation/test
files plus this plan. AST metadata and every resolution now retain owned-model
line/column values without retaining AST pointers. Version, count, ID, and kind
validation errors use those positions. Parser limits cannot exceed the hard
byte/obligation caps, and the renderer rejects a valid report with 1,025 state
changes before allocating output. Every declaration name is scanned for
reserved collisions; explicit `mem` and historical import aliases cannot
shadow the locked imports.

Independent execution passed all six scaffold tests and five accepted diff
tests with zero leak diagnostics. The tests exercise 1,024 and 1,025
obligations, lower and over-hard custom limits, renderer cap symmetry, real
non-default diagnostic positions, 2→3 metadata against a 1→2 report,
multi-name/import collisions, parsed-and-validated helper/body edits,
independent input copies, nil allocators, idempotent disposal, and allocation
failure through a positioned invalid diagnostic. `make check`, codec test,
double history generation, history check, and immutable hashes pass. Full tests
run 501 cases with 500 passing; only the known frozen-schema mismatch remains.
No review findings remain. 3D2B1 is accepted.

## Milestone 3D2B2 — Install the concrete unresolved scaffold safely

### Next slave handoff

### Allowed files

- add `src/fixture_migration.odin`;
- add generated `src/fixture_migration_v0001_to_v0002.odin`;
- add one narrowly scoped atomic installer file under
  `packages/fixture_schema`;
- add focused installer/CLI tests under `tests`;
- update `tools/fixture_schema/main.odin`, `Makefile`, and this plan.

Do not touch the codec, schema walker/diff/scaffold semantics, fixture/history
manifests, generated v1 history, serializable structs, or schema version. If
the accepted 3D2B1 API is insufficient, stop and report the missing contract
instead of changing it.

After 3D2B1 acceptance, add stable product-local
`Fixture_Migration_Resolution`, `Fixture_Migration_Error`, their enums, and
only the ownership/error fields required by the locked 3D2B1 signature in
`src/fixture_migration.odin`. Do not add a registry or execute a migration.

The minimal runtime declarations are:

- `Fixture_Migration_Resolution_Kind` with `Unresolved`, `Automatic`, and
  `Scripted`;
- `Fixture_Migration_Resolution` with `change_id: string` and
  `kind: Fixture_Migration_Resolution_Kind`;
- `Fixture_Migration_Error_Kind` with `None`, `Unresolved`,
  `Invalid_Source`, and `Out_Of_Memory`;
- `Fixture_Migration_Error` with its kind and a borrowed constant
  `change_id`. It owns no allocation and needs no disposal in this milestone.

Do not import the tooling enum into runtime code or add unused registry/chain
types. The generated unresolved function must compile against these exact
product types and continue to return `.Unresolved`.

Extend the fixture-schema CLI with:

- `migration-scaffold 1 2 <repository-root> <zelda-engine-packages>`;
- `migration-scaffold-check 1 2 <repository-root>
  <zelda-engine-packages>`.

Both operations rebuild the accepted report in memory. Check is read-only and
AST-validates the existing product script against it. Scaffold renders and
installs `src/fixture_migration_v0001_to_v0002.odin` only when absent. If the
target exists, validate it and return without changing any byte, even when it
contains legitimate scripted edits. If it is invalid, fail without repairing,
appending, formatting, replacing, or deleting it.

Command outcomes must be unambiguous:

- check: missing, unreadable, or structurally invalid script is nonzero;
- check: valid unresolved or edited valid script is zero and never writes;
- scaffold: absent target installs and validates generated bytes;
- scaffold: existing valid script is zero with an explicit already-existing
  status and no write;
- scaffold: existing invalid script is nonzero and byte-identical afterward;
- any candidate/report/render/install failure is nonzero and exposes no
  partially accepted script.

For an absent target, create an exclusive temporary file in the target
directory, write and sync the complete bytes, close it, then use
`os.link(temporary, target)` as the atomic no-replace install operation.
Hard-link creation must fail if another process created the target; remove only
the known temporary path in every branch. Never implement `exists` followed by
overwriting `rename`. First syntax-probe the exact `core:os` open/sync/link
calls. If a required primitive is unavailable on a supported target, stop and
ask sis.

Return an install result that distinguishes `Installed`, `Already_Exists`, and
`Not_Installed`. An error after the hard link succeeds must still report that
the target was installed; never misreport committed state as absent. Temporary
names may be nondeterministic, but final source bytes may not be.

Add concrete Makefile targets for the two commands, focused filesystem tests in
temporary directories, and the real generated unresolved script. Tests must
prove independent byte-identical first generation, exact 16 IDs, actual
`odin check src` compileability, idempotent valid-existing behavior, preservation
of an edited valid script, preservation of invalid existing bytes, exclusive
install collision, cleanup after every write/link failure, path aliases, and
read-only check behavior. Formatter-check a disposable copy of generated bytes;
never format an existing script.

Also prove zero-length/oversized source rejection, nonexistent target
directory, exclusive temporary-name collision, short-write loop, pre-link
cleanup, target-won-race behavior, and post-link cleanup-error status. Use a
small injected file-operation seam only if real filesystem tests cannot
deterministically force an operation; do not build a general virtual
filesystem.

Keep schema version 1, both immutable v1 hashes, codec dispatch, and manifests
unchanged. Do not resolve an obligation, add registry dispatch, execute a
migration, or generate v2.

### Acceptance criteria

- The product contains one compileable, structurally valid unresolved 1→2
  script with exactly 16 obligations.
- Both CLI operations use the accepted in-memory report and AST contract.
- Existing script bytes are never changed; absent-file install is atomic and
  no-replace.
- No migration executes and no schema/codec behavior changes.

### Execution evidence — 3D2B2

Implemented in the allowed runtime, tooling, installer, build, test, generated,
and plan files:

- `src/fixture_migration.odin` defines only the locked product-local runtime
  resolution/error types; no registry or migration execution exists;
- `packages/fixture_schema/migration_install.odin` uses an exclusive temporary
  file, complete short-write handling, sync/close, hard-link no-overwrite, and
  result-preserving cleanup status, with a narrow injected file-operation seam;
- `tools/fixture_schema/main.odin` adds read-only
  `migration-scaffold-check` and validating, no-overwrite
  `migration-scaffold`; `Makefile` exposes both commands;
- `src/fixture_migration_v0001_to_v0002.odin` is generated, formatter-clean,
  compiles, validates as 1→2, and contains exactly 16 unresolved obligations.

Twelve focused installer/scaffold tests pass with zero leak diagnostics. Full
tests execute 507 cases with 506 passing; the sole failure is the known frozen
schema mismatch.
Edited valid scripts are accepted without writes; invalid existing bytes are
rejected and preserved; absent installation, idempotent existing installation,
short writes, missing parents, exclusive temp collisions, target races, and
post-link cleanup status are covered. `make check`, codec, double history
generation/history check, and full tests pass except the known frozen-schema
mismatch (`array[256]` versus generated `dynamic`). Schema version, manifests,
codec, and immutable hashes remain unchanged. 3D2B3 remains untouched.

### Reviewer rejection — 3D2B2

The isolated 3D2B2 change stays inside its allowed runtime, tooling, installer,
test, build, generated-source, and plan files. Runtime types are minimal, the
installed script has the exact 16 unresolved state IDs, and the production
installer uses an exclusive temporary file, complete write loop, sync, close,
hard-link no-replace commit, and result-preserving cleanup status.

Independent execution passes the 12 focused tests with zero leak diagnostics,
`make check`, the codec test, two consecutive history generations, and history
check. The frozen manifest remains
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
generated v1 remains
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
the currently generated migration source is
`c83a719bdeeffc4fd952595c4ed2fe23d0992bf7321737cfd38288a8fb8ba15a`.
Full tests run 507 cases with only the known frozen-schema mismatch, now
reported as `City_Plan.structures` fixed array versus current dynamic array.

3D2B2 is not accepted because three required proofs are false or missing:

1. The injected `.Short_Write` operation returns a partial byte count without
   writing those bytes to the file. The installer advances its source slice as
   instructed, so the test reaches `.Installed` with only the final byte on
   disk. The test checks status but never reads the target. This does not prove
   complete short-write handling and actively masks corrupted output.
2. Both CLI operations build the current schema report before inspecting the
   existing target. Because the target lives under `src`, an invalid existing
   migration is fed to the full source walker before the dedicated scaffold
   parser can reject it. In an isolated repository copy, replacing the target
   with malformed non-Odin text makes `migration-scaffold` emit tokenizer
   diagnostics and terminate with signal 11. The bytes happened to remain
   unchanged, but the locked contract requires a normal nonzero validation
   failure, not a tool crash. The focused tests call library helpers only and
   contain no end-to-end CLI regression for this path.
3. The generated script is not formatter-clean. Running repository `odinfmt`
   on a disposable copy changes the package/import/declaration semicolons,
   indentation, all resolution literals, and the procedure body, beginning at
   line 1. The renderer emits this noncanonical form directly, so regenerating
   the product file cannot satisfy the required formatter comparison.

The execution note's reference to “3D2B3” has no matching milestone in this
plan. The next implementation milestone remains 3E only after this repair is
accepted.

## Milestone 3D2B2R — Fail closed before walking an existing script

### Required repair

Touch only `packages/fixture_schema/migration_scaffold.odin`,
`tools/fixture_schema/main.odin`, `tests/fixture_migration_scaffold_test.odin`,
`tests/fixture_migration_install_test.odin`,
`src/fixture_migration_v0001_to_v0002.odin`, and this plan. If a true
end-to-end CLI test cannot be expressed through the existing test executable,
one narrowly scoped test helper under `tools/fixture_schema` or one Makefile
test target may be added; stop before widening production APIs. Do not change
scaffold parse/validation semantics, the installer implementation, runtime
types, schema diff/walker, manifests, codec, serializable structs, or schema
version. Do not start 3E.

Change only the scaffold renderer's source layout to repository `odinfmt`
canonical form. Preserve every symbol, import, metadata value, obligation ID,
signature, resolution kind, and procedure behavior accepted in 3D2B1R.
Regenerate the product script from that renderer; never hand-format it.
Update exact-render assertions, and prove rendering twice remains
byte-identical. The migration-source SHA will legitimately change; record the
new deterministic SHA rather than preserving the noncanonical
`c83a719b...15a` value.

Repair the injected short-write operation so it calls the real file write with
the exact prefix whose length it reports. Never report bytes that were not
written. Track the number of write calls if needed, assert that the forced
short-write path uses more than one call, then read the installed target and
compare every byte with the source. Preserve the existing failure and cleanup
cases.

Reorder each CLI path around the existing target:

- derive the target path and determine whether it exists before building the
  current schema report;
- for `migration-scaffold-check`, reject a missing/unreadable target before
  report construction, then parse the existing bytes with the accepted
  migration-scaffold AST parser;
- for `migration-scaffold`, if the target exists, read and parse those bytes
  with the same parser before report construction;
- only after the existing source parses normally, build the current report and
  validate the owned parsed model against it;
- for an absent scaffold target, retain the accepted
  report/render/self-validation/atomic-install sequence.

Use one helper that reads and parses an existing target into the owned
`Migration_Scaffold` model so check and scaffold cannot drift. Keep its byte
buffer alive only for the parse call; the accepted parser owns everything it
retains. Dispose the owned model and every diagnostic exactly once on all
paths. A parse failure must print its position/path/message and return false
without invoking the current-schema walker.

Do not weaken later semantic validation: a syntactically valid but stale,
edited-invalid, reordered, or wrong-version scaffold must still build the
report and fail against the accepted AST contract. A valid edited designer
script must remain successful and byte-identical. A target that appears during
absent-file installation must retain the accepted `Already_Exists` nonzero
race result.

### Required proof

- Force real partial writes, prove multiple write calls, and compare the final
  target bytes exactly with a multi-byte source.
- Run the built CLI against an isolated repository copy with an invalid
  existing target containing malformed/tokenizer-hostile text. Both
  `migration-scaffold` and `migration-scaffold-check` must return normal
  nonzero status, preserve exact bytes, inode, and modification time, and
  leave no temporary file. No signal termination is acceptable.
- In the same end-to-end layer, prove an existing valid unresolved script and
  one legitimate edited valid script return zero with exact bytes, inode, and
  modification time unchanged.
- Prove a missing check target is nonzero and creates nothing. Prove an absent
  scaffold target installs the exact deterministic bytes and a second run is
  idempotent.
- Run repository `odinfmt` on a disposable rendered/generated copy and require
  byte identity. Parse and validate those exact bytes after the formatter
  comparison. Never run the formatter on an existing designer script.
- Retain the existing installer failure/race/cleanup tests and all accepted
  scaffold validation tests. No test may simulate a write by returning a count
  without performing that write.

Run the repaired focused tests, all accepted scaffold/diff tests,
`make fixture-migration-scaffold-check`, `make check`,
`make fixture-codec-test`, double history generation/history check, full
tests, and schema check. Formatter-check only a disposable copy of generated
source. Expected full/schema failure remains only the frozen
`City_Plan.structures` mismatch. Verify the two immutable v1 hashes above,
record the new deterministic migration-source hash, and remove generated root
binaries and temporary repositories.

### Acceptance criteria

- Forced short writes install the exact complete source, not merely a success
  status.
- Invalid existing scripts fail normally before the broad source-schema walk
  can consume them.
- Freshly rendered and generated migration source is byte-identical after
  repository formatting.
- Valid existing designer scripts are semantically checked and never written.
- Absent installation remains deterministic, atomic, and no-replace.
- No runtime migration, registry, schema activation, codec change, or v2
  artifact exists.

### Execution evidence — 3D2B2R

The three rejected contracts are repaired inside the six-file scope:

- the short-write seam writes the exact reported prefix, tracks calls, and the
  test reads back every installed byte;
- both CLI operations resolve existence and parse an existing scaffold before
  building the schema report, so malformed targets fail normally without
  entering the source walker; valid edited targets remain byte- and inode-stable;
- the renderer emits repository `odinfmt` layout directly, including optional
  semicolons, tabs, and multiline literals. Rendering twice is byte-identical,
  and formatting a disposable generated copy is byte-identical.

The regenerated product source SHA is
`c620f48f4a258cc7c5c5a42793acd6b6b22f8315a9d0c66c4af2a9e4b037b705`.
The frozen v1 manifest and generated historical v1 hashes remain unchanged.

The 12 focused scaffold/installer tests pass with zero leak diagnostics. Full
tests execute 507 cases with 506 passing; the only failure remains the known
frozen `City_Plan.structures` mismatch (`array[256]` versus generated
`dynamic`). `make check`, scaffold check, real codec, two history generations,
and history check pass. Invalid existing targets fail nonzero for both CLI
commands without a signal or file mutation; missing check, absent install, and
second idempotent install also pass.

### Reviewer acceptance — 3D2B2R

Accepted. The isolated repair changes exactly the renderer, CLI, two focused
test files, regenerated product source, and this plan. The short-write seam now
performs each reported prefix write and the test proves multiple writes plus
exact final bytes. Existing targets are parsed into an owned scaffold before
the broad source report is built. Renderer output is canonical under repository
`odinfmt`, deterministic across two renders, and structurally valid with the
locked `#by_ptr` ABI.

Independent execution passes all 12 focused tests with zero leak diagnostics.
An external built-CLI matrix proves malformed existing targets fail normally
for check and scaffold before schema walking, with exact bytes, inode, and
modification time preserved. Missing check creates nothing. Absent scaffold
installs exact generated bytes. Valid unresolved, legitimately edited, repeated
scaffold, and symlink-alias paths succeed without mutation or temporary files.

`make check`, the real codec test, scaffold/check commands, two history
generations, and history check pass. Full tests execute 507 cases with 506
passing; schema check and the sole full-test failure report only the frozen
`City_Plan.structures` fixed-to-dynamic mismatch. Frozen v1 hashes remain
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`
and
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
Canonical migration source is
`c620f48f4a258cc7c5c5a42793acd6b6b22f8315a9d0c66c4af2a9e4b037b705`.
No review findings remain. 3D2B2 is accepted.

## Milestone 3E1 — Build the migration transaction and registry boundary

### Next slave handoff

### Allowed files

- update `src/fixture_migration.odin`;
- add one narrowly scoped runtime implementation under `src`;
- add one focused runtime test file under `src`;
- add one focused Makefile test target if required;
- update this plan.

Do not change the generated 1→2 script or any resolution kind. Do not touch the
fixture codec, fixture container, portable `hs`, schema walker/diff/scaffold,
manifests, generated history, serializable structs, authored quest catalog, or
schema version. Do not begin structural or story migration behavior from 3E2
or 3E3.

Build one product-local, memory-only migration transaction. It accepts a
borrowed validated portable payload, explicit source and target schema
versions, a registry view, and a caller allocator. It does not read or write a
file and does not mutate an `Editor`.

Use a homogeneous step wrapper ABI:

- metadata contains exact `from_version`, `to_version`, and one non-nil wrapper
  procedure;
- wrapper receives the original borrowed portable payload, the shared
  tentative current `^Fixture`, and the transaction allocator;
- each version-specific wrapper decodes its own generated historical type into
  fresh scratch arena storage, calls the typed generated migration procedure,
  then destroys historical storage on every return;
- do not erase the typed generated procedure ABI or store incompatible typed
  procedures behind `rawptr`.

Add the production 1→2 wrapper and registry entry, but leave the accepted
generated script unresolved. Production execution from version 1 must
therefore return its exact `.Unresolved` error and expose no result. An
internal registry-injection entry point may exist only to prove the generic
transaction; keep the default production entry point fixed to the product
registry.

Validate the complete requested chain before decoding or allocating result
state:

- source and target versions are nonzero and source is not greater than target;
- every entry has nonzero adjacent versions with
  `to_version == from_version + 1`;
- entries are strictly sorted, unique, contiguous, and have non-nil wrappers;
- exactly one path covers every version from source through target;
- missing, duplicate, reversed, skipped, zero, or future steps fail before a
  wrapper executes.

Decode the borrowed payload into a tentative current `Fixture` exactly once,
using the existing fixture portable configuration and a fresh owned arena.
For `source_version == target_version`, perform that current decode and execute
zero migration steps. For an older source, call each validated wrapper in
order against the same tentative current state. Never re-encode between steps.

Return one explicit owned migration result containing the usable current
fixture and its backing arena only after every step succeeds. Provide
idempotent disposal. On registry, tentative-decode, historical-decode, step, or
allocation failure, destroy every arena, return an empty disposable result,
and leave no caller-visible fixture or pointer. Borrowed payload, registry,
resolution IDs, and constant `change_id` strings must never be freed.

Extend migration errors only as needed to distinguish invalid argument,
invalid registry, unsupported version/chain, tentative portable decode,
historical portable decode, step failure, and out-of-memory. If an owned
`hs.Portable_Error` is retained, record its allocator and dispose it exactly
once; otherwise translate it before its source allocator dies. Preserve the
accepted borrowed constant `change_id` contract for script errors.

### Required proof

- Syntax-probe the exact Odin procedure-type and arena ownership shapes before
  production edits.
- Build deterministic current-layout and generated historical-v1 payloads in
  memory; never add fixture files.
- A test-only valid registry proves zero-step current decode and one/multiple
  contiguous wrapper execution order against one tentative fixture.
- The production 1→2 registry reaches the generated script, returns its exact
  unresolved change, and exposes no result.
- Missing, duplicate, reversed, skipped, zero, future, and nil-wrapper
  registries fail before any wrapper counter changes.
- Corrupt portable bytes fail separately in tentative and historical decode
  paths with empty results and owned diagnostics disposed.
- A wrapper that mutates tentative state and then fails still exposes no
  fixture. Successful test wrappers preserve their mutation until result
  disposal.
- Source equals target executes no wrapper. Source newer than target and target
  beyond the registry fail without decode.
- Payload and registry snapshots remain byte-identical. Result/error disposal
  is nil-safe and idempotent.
- Sweep caller allocation failures through current decode, historical decode,
  wrapper execution, and successful result ownership with zero outstanding
  allocations.

Run the focused runtime tests, all 12 accepted scaffold/installer tests,
accepted semantic-diff tests, `make check`, real codec test, scaffold check,
double history generation/history check, full tests, and schema check.
Expected repository failure remains only frozen `City_Plan.structures`.
Verify all three accepted hashes above and remove generated root binaries and
probe files.

### Acceptance criteria

- One validated contiguous registry drives one memory-only transaction.
- Historical and tentative state have explicit disjoint arena lifetimes.
- Failed migration exposes no fixture; successful result has one disposable
  owner.
- Production 1→2 dispatch reaches the still-unresolved generated script.
- No obligation, codec, schema, editor, or file behavior changes.

### Execution evidence — 3E1

Implemented the product-local memory transaction and registry boundary in the
allowed runtime files. The transaction validates versions and the complete
registry chain before allocation or decode, decodes current payloads once for
zero-step runs, dispatches older payloads through homogeneous typed wrappers,
and keeps tentative and historical arenas disjoint. The production 1→2 wrapper
decodes generated historical v1 state, calls the unchanged unresolved generated
procedure, and returns the exact first unresolved change ID.

Successful results own one disposable tentative arena. Every registry,
tentative decode, historical decode, step, and allocation failure destroys all
arena state and returns an empty result. Error and result disposal are nil-safe
and idempotent; borrowed payloads, registries, and constant IDs are untouched.

The focused `fixture-migration-test` target passes 3 tests with zero leak
diagnostics. Project `make check`, real codec, scaffold check, two history
generations, and history check pass. Full tests remain 507 cases with 506
passing; the only failure is the known frozen `City_Plan.structures`
fixed-to-dynamic mismatch. Schema version, v1 manifest/history hashes, and the
canonical unresolved migration source SHA remain unchanged.

### Reviewer rejection — 3E1

The isolated change stays inside the five allowed runtime, test, build, and
plan files. Registry shape, historical wrapper, production unresolved dispatch,
result/error disposal, and broad failure cleanup are present. Three focused
tests pass repeatedly with zero leak diagnostics. `make check`, real codec,
scaffold check, double history generation/history check, and all three accepted
hashes pass. Full tests execute 507 cases with only the known frozen
`City_Plan.structures` mismatch.

3E1 is not accepted because the central transaction and ownership contracts
are broken:

1. `fixture_migration_run_with_registry` decodes the portable payload into the
   tentative current `Fixture` only when `source_version == target_version`.
   Every older-source path allocates a zeroed tentative fixture and immediately
   calls wrappers. A direct no-op 1→2 probe loses saved `authoring_tool`,
   `farm_count`, and `project.structures`; all three preservation assertions
   fail. The 3E2 structural script therefore has no automatically crossed
   current state to repair.
2. Successful decode stores a custom allocator whose `data` points to local
   stack `transaction_state`. Every decoded dynamic array retains that
   allocator in its header after the function returns. A direct result probe
   confirms `project.structures` still uses
   `fixture_migration_transaction_allocator_proc`; subsequent append, resize,
   or delete dereferences dead stack state. The returned fixture is not usable.
3. Equal source/target versions bypass chain coverage for any positive value.
   Production registry can therefore accept a current payload labeled a future
   version such as 3→3 even though its only endpoint is version 2. Tests cover
   reversed versions but omit equal future versions and do not lock the
   logical target to the registry endpoint.

Required proof is also incomplete. The ordered-wrapper test expects mutations
from a zero fixture instead of proving preserved decoded fields. A synthetic
`fixture_migration_step_scratch` allocation exists only to manufacture an OOM
site rather than testing real wrapper allocation. Dynamic-arena bookkeeping
uses `runtime.default_allocator()` instead of the caller allocator, so the
caller sweep cannot cover all transaction ownership. Registry snapshots, nil
allocator, live post-return dynamic-array mutation, and a non-racy
before-decode wrapper counter are absent. Two focused tests share a mutable
global counter while the test runner executes them on separate threads.

## Milestone 3E1R — Restore the transaction contract

### Required repair

Touch only `src/fixture_migration.odin`,
`src/fixture_migration_runtime.odin`, `src/fixture_migration_test.odin`, and
this plan. Change the Makefile only if the focused target's test selection or
thread policy must change. Do not touch the generated script, resolution
kinds, codec, container, portable `hs`, schema/history tooling, manifests,
serializable structs, authored story data, or schema version. Do not start
3E2.

Decode the borrowed payload into the tentative current `Fixture` exactly once
for every valid transaction, before any migration wrapper runs. Use the same
path for zero-step and older-source transactions. If tentative decode fails,
destroy the arena and execute zero wrappers. Once it succeeds, run the selected
wrappers against that populated fixture. A v1 fixed array decoded into a
current dynamic array must retain the saved full array until 3E2 shortens it to
its historical active count.

Remove the stack-backed transaction allocator. Prefer passing
`mem.dynamic_arena_allocator(result_arena)` directly to portable decode and
wrappers so every dynamic-array allocator header points at the heap-owned arena
that survives in `Fixture_Migration_Result`. The version-specific wrapper may
recover the arena's caller/block allocator only through a syntax-probed,
type-safe core API or arena pointer; do not identify an allocator by unsafe
procedure/data assumptions. If the core API cannot support that simply,
allocate one stable transaction state with the caller allocator, make the
result own it explicitly, and free it after arena destruction. Never retain a
pointer to stack state.

Initialize dynamic-arena block tracking with the caller allocator for both
`block_allocator` and `array_allocator`. The caller fault allocator must see
arena object, internal tracking arrays, blocks, and out-of-band allocations.
Keep historical and tentative arenas disjoint, and preserve historical
destruction before wrapper return.

Remove `fixture_migration_step_scratch`. Production must not allocate a dummy
byte merely to make a test sweep longer. Test actual wrapper allocation by
having a synthetic wrapper allocate through the supplied transaction
allocator; its allocation and mutation must survive success, and every caller
failure point must still clean up.

Lock transaction target semantics. The production entry point targets exact
logical version 2, using
`FIXTURE_MIGRATION_V0001_TO_V0002_TO_VERSION`, even while source-owned
`FIXTURE_SCHEMA_VERSION` remains 1 until 3F. A zero-step current-layout proof
uses 2→2 and executes no wrapper. Equal future or older labels not matching the
registry's current endpoint fail before decode. Internal injected registries
may use another endpoint only when the complete validated registry ends at
that target.

Keep registry validation allocation-free and fail closed. Validate the whole
registry, then require requested target to equal its final endpoint before
allowing zero-step or migrated execution. Empty, missing, duplicate, reversed,
skipped, nil-wrapper, zero, older-equal, and future-equal cases fail before any
decode or wrapper side effect.

### Required proof

- Build a nonzero generated historical-v1 payload and run it through 1→2 with
  a no-op wrapper. Assert shared scalar sentinels, strings/enums, `farm_count`,
  and all five fixed-to-dynamic arrays decode into current tentative state with
  exact saved capacity/content before wrapper-specific mutation.
- In an ordered two-step test, assert step one sees decoded sentinels and step
  two sees both those sentinels and step-one mutation. Expected output must not
  be derivable from a zero fixture.
- Inspect every populated dynamic-array header in a successful result. Its
  allocator must remain valid after the run returns and must not reference
  stack state. Force at least one post-return append/resize allocation, verify
  preserved contents, then dispose the result twice with zero leaks.
- Production 1→2 still decodes tentative current plus generated historical v1,
  calls the unchanged script, returns the first exact unresolved ID, and
  exposes no result.
- Tentative corruption executes zero wrappers. Use a valid current-decodable
  payload plus a deliberately incompatible real historical decode in a
  test-only wrapper to prove historical failure separately.
- Prove 2→2 current decode executes zero wrappers. Prove 1→1, 3→3, target
  before registry endpoint, target beyond endpoint, and source newer than
  target all fail before decode/wrapper activity.
- Replace shared mutable test counters with per-test state that cannot race,
  or exact atomics with independent counters. Full tests run with normal
  parallelism; do not hide the race by forcing the whole suite to one thread.
- Snapshot every payload and every registry field/procedure before execution
  and compare afterward. Add explicit nil allocator plus nil-safe,
  double-disposable empty/success/error cases.
- Sweep caller failures through arena object/tracking/block allocation,
  tentative decode, real synthetic wrapper allocation, historical decode, and
  successful returned ownership. Every failure returns an empty result and
  zero caller/default outstanding allocations.

Run repaired focused tests repeatedly under normal parallelism, all 12 accepted
scaffold/installer tests, accepted semantic-diff tests, `make check`, real
codec, scaffold check, double history generation/history check, full tests,
and schema check. Expected repository failure remains only frozen
`City_Plan.structures`. Verify all three accepted hashes and remove binaries
and probes.

### Acceptance criteria

- Every valid transaction decodes tentative current state once before steps.
- Returned dynamic arrays retain only live result-owned allocation state.
- Registry endpoint determines the only valid logical target.
- Real wrapper allocations, not dummy probes, drive OOM coverage.
- Failed transactions expose nothing; successful results remain usable until
  idempotent disposal.
- Generated script stays unresolved and 3E2 remains untouched.

### Execution evidence — 3E1R

Repaired the transaction in the four allowed files. Every valid source path
decodes the borrowed payload into one current tentative `Fixture` before any
wrapper, including older migrations and 2→2 zero-step runs. The transaction
now passes the heap-owned dynamic-arena allocator directly, uses the caller
allocator for arena metadata, blocks, tracking arrays, and out-of-band data,
and lets the production wrapper recover only the known core arena pointer.
Historical decoding remains in a separate arena destroyed before wrapper
return. The dummy step allocation is gone; synthetic wrappers perform real
arena allocations and mutation.

Registry validation now covers the complete contiguous chain and requires the
requested target to equal the final endpoint. Equal older/future labels,
empty or malformed registries, endpoint mismatches, newer sources, and nil
allocators fail before decode or wrapper activity. Results retain usable
dynamic-array allocator headers after return, support append, and dispose
idempotently. Tests snapshot payloads and registry fields, use no shared
mutable counters, and cover tentative versus historical corruption, real
wrapper allocation failure, historical decode failure, caller ownership, and
nil/double disposal.

Focused migration tests pass under normal three-thread execution with zero
leak diagnostics. `make check`, real codec, scaffold check, two history
generations, and history check pass. The full suite executes 507 tests with
506 passing; its only failure is the known frozen-v1
`City_Plan.structures` fixed-to-dynamic mismatch. Schema check and generation
continue to stop at that expected frozen-manifest mismatch. Frozen schema v1,
generated history v1, and unresolved migration source hashes remain
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`,
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`, and
`c620f48f4a258cc7c5c5a42793acd6b6b22f8315a9d0c66c4af2a9e4b037b705`.

### Reviewer acceptance — 3E1R

Accepted. The isolated repair changes only the transaction runtime, focused
tests, and this plan. Every valid path now decodes one current tentative
fixture before wrappers. The heap-owned dynamic arena allocator is retained in
all decoded dynamic-array headers, while its block and tracking allocations use
the caller allocator. Historical state remains in a separate arena destroyed
inside the typed wrapper. Registry validation requires the requested target to
equal the complete chain endpoint before allocation.

Independent execution passes the three focused tests three consecutive times
under normal parallelism with zero leak diagnostics. Nonzero generated-v1
scalars, enum/string fields, farm state, and all five fixed arrays survive the
tentative decode before ordered wrapper mutations. Current and migrated result
arrays retain the result-arena allocator, append after return, and dispose
twice. Real wrapper allocations and caller fail-at-every-allocation sweeps
cover arena metadata, blocks, tentative decode, wrapper work, and historical
decode. No shared mutable test counter remains.

`make check`, real codec, scaffold check, double history generation/history
check, and all accepted hashes pass. Full tests execute 507 cases with 506
passing; schema check and the sole full-test failure remain the frozen
`City_Plan.structures` fixed-to-dynamic mismatch. No review findings remain.
3E1 is accepted.

## Milestone 3E2 — Implement structural migration 1→2

### Next slave handoff

### Allowed files

- edit `src/fixture_migration_v0001_to_v0002.odin`;
- add one focused structural migration test file under `src`, or extend
  `src/fixture_migration_test.odin` if that remains simpler;
- update the focused Makefile target only when adding test names;
- update this plan.

Do not change `src/fixture_migration_runtime.odin`, registry/transaction/error
types, fixture codec/container, portable `hs`, schema/history/scaffold
tooling, manifests, generated historical v1, serializable structs, authored
story/quest code, or schema version. Do not implement any story behavior from
3E3.

After 3E1 is accepted, resolve only the 11 non-story obligations: five
fixed-to-dynamic crossings, three farm-plan defaults, two farm-instance scale
defaults, and explicit removal of the old settlement city plan. Keep all five
story/quest/tracking obligations unresolved, so the production transaction
still fails and discards tentative state.

Mark exactly these 11 resolution entries `.Scripted`:

- `field-add:adriatic:packages/farmland.Plan.height`;
- `field-add:adriatic:packages/farmland.Plan.tradition`;
- `field-add:adriatic:packages/farmland.Plan.width`;
- `field-add:adriatic:src.Farm_Instance.scale_x`;
- `field-add:adriatic:src.Farm_Instance.scale_z`;
- `field-remove:adriatic:src.Settlement_Plan.city_plan`;
- the four `field-type:adriatic:packages/architecture.City_Plan.*` entries;
- `field-type:adriatic:packages/terrain.Project.structures`.

Leave exactly these five entries `.Unresolved`: story `airfield_errand`,
story `quest`, and the three `Fixture` quest-tracking fields. After successful
structural mutation, return `.Unresolved` with exact borrowed change ID
`field-add:adriatic:packages/story.State.airfield_errand`. Do not rely on the
runtime wrapper's empty-ID fallback because the first resolution is now
scripted.

Freeze migration capacities and defaults inside the versioned script. Use
literal historical capacities `256` for terrain structures, `256` city
structures, `256` parcels, `128` alleys, `256` lamps, and `16` farms. Do not
read current capacity constants or future editor defaults. Use exact farm
defaults width `25`, height `19`, `.Ancient_Enclosure`, `scale_x = 1`, and
`scale_z = 1`.

Perform one complete validation pass before the first write:

- historical `project.structure_count` must be in `0..256`, and tentative
  `project.structures` must contain exactly the 256 elements produced by
  fixed-to-dynamic decode;
- historical top-level city `count`, `parcel_count`, `alley_count`, and
  `lamp_count` must respectively be in `0..256`, `0..256`, `0..128`, and
  `0..256`; each tentative dynamic array must still have its exact historical
  capacity length;
- historical `farm_count` must be in `0..16`;
- each of the four removed `historical.settlement_plan.city_plan` counts must
  first be within its frozen capacity and then equal zero.

Map each validation failure to the exact related resolution ID. Terrain and
top-level city count/length failures use their corresponding `field-type` ID.
Farm-count failure uses one stable farm default ID documented in tests.
Removed-city-plan negative, over-capacity, or nonzero counts use the
`field-remove` ID. Return `.Invalid_Source`; do not clamp, partially shorten,
or apply any farm default after a failed validation.

After validation succeeds, shorten the five tentative dynamic arrays to their
historical active counts without reallocating. First syntax-probe the exact
Odin dynamic-array resize operation. Tests must prove data pointer, capacity,
and allocator remain unchanged while only length changes. Do not copy active
elements: the accepted 3E1 tentative decode already copied all historical
content.

For each active farm index `0..<historical.farm_count`, assign the five frozen
new fields on tentative state. Preserve every pre-existing farm plan, origin,
yaw, parcels, count, validity, and seed. Inactive farm slots keep zero values
for the five new fields; do not apply defaults beyond the active prefix.

The removed nested city plan has no current destination. Validation is the
entire migration behavior: all four zero counts explicitly authorize the
already-skipped field. Any active removed structures, parcels, alleys, or lamps
must fail rather than silently discard authored data.

### Required proof

- Parse/validate the edited script against the accepted 1→2 report and assert
  exactly 11 scripted plus five unresolved IDs in sorted order.
- Build generated-v1 historical payloads with distinct sentinels at the first
  and last fixed-array elements. Decode tentative current state through 3E1,
  call the typed step directly, and prove all five arrays retain exact active
  prefix content with unchanged pointer/capacity/allocator.
- Cover zero and maximum valid count boundaries for terrain, all four top-level
  city arrays, farms, and all four removed-city-plan arrays.
- For every count, cover `-1` and capacity-plus-one. For each tentative dynamic
  array, forge a short and overlong decoded length. Every failure returns the
  exact stable change ID and leaves the complete tentative fixture
  byte/header-equivalent to its pre-call snapshot.
- Set each removed city-plan active count to one independently and prove
  `.Invalid_Source` with the removal ID and no mutation.
- Prove all 16 active farms receive exact defaults at the upper boundary while
  inactive farms retain zeros. Preserve old farm fields byte-for-byte.
- On structurally valid input, direct typed execution applies structural
  changes then returns the exact first story unresolved ID.
- Run the same valid payload through the production transaction. It must return
  that unresolved ID with an empty result, proving structural mutations cannot
  escape before 3E3.
- Run every invalid case through production dispatch as well. Runtime may
  classify the step as `.Step_Failure`, but must preserve the borrowed related
  change ID and expose no result.
- Sweep allocation failures for direct preparation and transaction execution;
  the structural script itself must allocate zero bytes.
- Format the edited script, run scaffold check, and record its new SHA. Frozen
  schema/history hashes remain immutable; the prior unresolved-script SHA is
  expected to change because this is the first legitimate designer edit.

Run focused structural and 3E1 tests, all accepted scaffold/installer/diff
tests, `make check`, real codec, scaffold check, double history generation and
history check, full tests, and schema check. Expected repository failure
remains only frozen `City_Plan.structures`. Remove binaries and probes.

### Acceptance criteria

- All five arrays use validated historical active prefixes.
- Every active v1 farm receives exact frozen defaults.
- Only an empty removed city plan is acknowledged.
- All invalid counts/lengths fail before any mutation with stable change IDs.
- Exactly 11 resolutions are scripted and five story resolutions remain
  unresolved.
- Transaction failure still exposes no partial state.

### Execution evidence — 3E2

Implemented the eleven non-story structural obligations in the allowed
versioned migration script. The script freezes historical capacities at 256
terrain structures, 256 city structures, 256 parcels, 128 alleys, 256 lamps,
and 16 farms. It validates every historical count, every tentative
fixed-to-dynamic length, and all four removed settlement city-plan counts
before writing. Valid arrays are shortened in place without reallocating;
active farms receive width 25, height 19, `.Ancient_Enclosure`, and scale 1,
while inactive slots and prior farm state remain untouched.

Exactly eleven resolution entries are `.Scripted`; exactly five story and
quest/tracking entries remain `.Unresolved`. Structural success returns the
borrowed `field-add:adriatic:packages/story.State.airfield_errand` ID. Invalid
historical counts, forged tentative lengths, and removed-city data return
stable related `.Invalid_Source` IDs before mutation. Production dispatch
maps those failures to `.Step_Failure`, discards the result, and preserves the
same ID.

The focused target runs four migration tests with zero leak diagnostics.
`make check`, real codec, scaffold check, two history generations, and history
check pass. Full tests remain 507 cases with 506 passing; the only failure is
the known frozen-v1 `City_Plan.structures` mismatch. Schema check stops at that
same expected mismatch. Frozen schema and generated-history hashes remain
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12` and
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
The edited structural migration script SHA is
`885ff3efb77ea9856e0e9787c020249d245c54d6e308fa3cd58403862be51c99`.

### Reviewer verification — 3E2

Not yet accepted. The implementation itself matches the structural contract:
exactly 11 entries are scripted and five story entries remain unresolved; all
historical ranges, tentative lengths, farm count, and removed-city counts are
checked before the first mutation; the five arrays are shortened in place;
active farms receive the frozen defaults; and successful direct execution
returns the exact first story obligation. The isolated diff remains inside the
allowed files.

Independent gates reproduce the submitted evidence. The four focused
migration tests pass with zero leak diagnostics. `make check`, the real codec,
scaffold check, two history generations, and history check pass. Full tests
execute 507 cases with 506 passing. Schema check and the only full-test failure
remain the known frozen `City_Plan.structures` fixed-to-dynamic mismatch. The
frozen schema, generated history, and edited migration hashes are respectively
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`,
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`, and
`885ff3efb77ea9856e0e9787c020249d245c54d6e308fa3cd58403862be51c99`.

Acceptance is blocked by missing required proof, not by a demonstrated
production-code defect:

- the direct invalid cases compare only `structure_selected` and one farm
  width after failure; they do not prove that the complete root state, all
  five dynamic-array headers, and their backing elements are unchanged;
- production dispatch is exercised for only the negative terrain count.
  It does not cover the other top-level counts, farm count, or any of the four
  removed-city count families, so their exact IDs and empty-result behavior
  are unproved across the real typed wrapper;
- the existing transaction OOM sweep reaches the production wrapper, but
  direct preparation is not fail-at-every-allocation tested and the structural
  step is not explicitly proved to make zero allocator calls;
- removed-city tests cover negative, capacity-plus-one, and one active item,
  but omit each exact frozen-capacity nonzero boundary required by the handoff.

## Milestone 3E2R — Complete structural proof

### Next slave handoff

This is a test-only repair unless a new test exposes a production defect.
Keep `src/fixture_migration_v0001_to_v0002.odin` byte-identical. Edit only
`src/fixture_migration_structural_test.odin`, the focused Makefile target if a
test procedure is split, and this plan. Do not touch the runtime, codec,
schema/history/scaffold tooling, generated files, fixture structs, story code,
or schema version.

Add reusable helpers that make the assertions compact:

- capture and compare the complete tentative root bytes plus the data pointer,
  length, capacity, allocator procedure, and allocator data for all five
  dynamic arrays;
- capture and compare every element in each array backing prefix that exists
  before the call, so a failed step cannot mutate data while leaving headers
  intact;
- construct historical payloads with one selected invalid count without
  changing unrelated fields;
- run one payload through production dispatch and assert failure kind, exact
  borrowed change ID, empty result, idempotent error/result disposal, and zero
  outstanding allocations.

Avoid copying the nearly full `Fixture` onto the stack. Use owned heap
snapshots, bounded byte comparisons, or a collision-resistant test digest,
and dispose every snapshot on every path. Snapshot allocation belongs to the
test harness and must happen before the measured step.

Expand the direct invalid table to prove full pre-write atomicity for:

- `-1` and capacity-plus-one for terrain, four top-level city counts, and farm
  count;
- short and overlong tentative lengths for all five dynamic arrays, using
  `255/257`, `255/257`, `255/257`, `127/129`, and `255/257`;
- each removed-city structures/parcels/alleys/lamps count at `-1`, exact
  frozen capacity, capacity-plus-one, and `1`.

Every direct failure must compare the complete snapshot and exact related ID.
Run every payload-representable invalid family through production: both
polarities for terrain, four top-level city counts, and farm count, plus all
four removed-city fields at negative, exact-capacity nonzero,
capacity-plus-one, and one. Forged tentative dynamic lengths remain a direct
typed-step test because production decode necessarily reconstructs their
historical fixed lengths.

Make direct preparation accept a supplied tracked allocator, then perform a
successful run to count its allocations and fail at every allocation index.
Every failure must clean up and report zero outstanding allocations. Separately
prepare valid state, record the tracking count, execute only
`fixture_migrate_v0001_to_v0002`, and prove the count does not change. Also
retain the existing pointer/capacity/allocator/header checks after successful
shrinks. Do not add a dummy allocation to the migration script.

Keep the existing 11/5 resolution assertions, zero/maximum valid successful
cases, active-prefix sentinels, all-16-farm defaults, inactive farm zeros,
old-farm preservation, exact story unresolved ID, successful production
unresolved/empty-result proof, and existing transaction allocation sweep.

Run the repaired focused test at least three consecutive times under normal
parallelism. Then run `make check`, real codec, scaffold check, double history
generation/history check, full tests, and schema check. Expected repository
failure remains only the frozen `City_Plan.structures` mismatch. The three
accepted hashes above must remain unchanged. Remove generated binaries and
temporary files.

### Acceptance criteria

- every invalid structural input is proven atomic with its exact stable ID;
- every payload-representable invalid family is proven through production
  dispatch with an empty result;
- direct preparation survives every allocation failure with no leaks;
- the structural step performs zero allocations;
- production source and all accepted hashes remain unchanged.

### Execution evidence — 3E2R

The structural proof was hardened without changing
`src/fixture_migration_v0001_to_v0002.odin` or any runtime, codec, schema,
history, scaffold, fixture, story, or version files. The test now owns a
complete root-byte snapshot plus all five dynamic-array headers and backing
prefixes, and compares that state after every direct invalid family. It also
exercises every payload-representable invalid count through production
dispatch, checking exact stable IDs, `Step_Failure`, empty results,
idempotent disposal, and zero outstanding tracked allocations.

Direct preparation accepts a supplied tracked allocator and fails at every
successful preparation allocation index with cleanup verified. A separate
valid run proves the structural step makes zero allocator calls. Removed-city
tests cover negative, exact frozen capacity, capacity-plus-one, and one for
all four fields. The existing successful boundary, preservation, inactive
farm, pointer/capacity/allocator, unresolved, and transaction sweeps remain.

The repaired focused target passed three consecutive normal four-thread runs:
4 tests each, zero leak diagnostics. `make check`, real codec, scaffold check,
two history generations, and history check pass. Full tests execute 507 cases
with 506 passing; the only failure remains the frozen
`City_Plan.structures` mismatch. Schema check reports that same mismatch.
Frozen schema/history hashes remain
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12` and
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`; the
unchanged migration script remains
`885ff3efb77ea9856e0e9787c020249d245c54d6e308fa3cd58403862be51c99`.

### Reviewer acceptance — 3E2R

Accepted. The repair changes only the focused structural test and this plan.
Complete root bytes, all five dynamic-array headers, and every backing-capacity
byte are captured before each direct invalid call and match afterward. The
direct table covers both invalid bounds for all six top-level counts, exact
short/overlong lengths for all five arrays, and negative, exact-capacity,
capacity-plus-one, and active removed-city counts. Every
payload-representable family crosses the production wrapper with its stable
change ID, empty result, idempotent disposal, and zero outstanding tracked
allocations.

Direct preparation is caller-allocator driven and survives every successful
allocation index failing. A separately measured valid call proves the
structural step performs no underlying allocation. The existing successful
array-header, active-prefix, farm-default, preservation, unresolved, and
transaction OOM proofs remain.

Independent execution passes the four focused tests three consecutive times
under normal four-thread parallelism in 1m38.978s, 1m47.812s, and 1m38.908s,
with zero leak diagnostics. `make check`, real codec, scaffold check, double
history generation/history check, and all hashes pass. Full tests execute 507
cases with 506 passing; schema check and the sole full-test failure remain the
known frozen `City_Plan.structures` mismatch. No binaries remain. Milestone
3E2 and its repair are accepted.

## Milestone 3E3 — Resolve story migration and prove golden v1 upgrade

### Next slave handoff

### Allowed files

- edit `src/fixture_migration_v0001_to_v0002.odin`;
- add `src/fixture_migration_story_test.odin`;
- update `src/fixture_migration_structural_test.odin` only for the new
  16-scripted/zero-unresolved and successful-step expectations;
- update `src/fixture_migration_test.odin` only where the production 1→2 path
  changes from unresolved to successful, including its existing OOM sweep;
- update the focused Makefile target or add one story-only target;
- update this plan.

Do not change migration runtime/registry/result ownership, fixture codec or
container, portable `hs`, schema/history/scaffold tooling, frozen manifests,
generated v1 types, current `story`/`quest` gameplay code, fixture structs, or
schema version. Do not start 3F file integration.

Before editing production source, syntax-probe assignment of literal `-1` to
the current distinct quest node ID and direct contextual assignment of quest
statuses. Remove the probe. Keep target values literal inside the versioned
script; do not read `quest.no_node`, `story.Quest_Node`, current capacity
constants, current quest catalog, or current initialization/projection
procedures.

Mark all five remaining entries `.Scripted`:

- `field-add:adriatic:packages/story.State.airfield_errand`;
- `field-add:adriatic:packages/story.State.quest`;
- `field-add:adriatic:src.Fixture.quest_tracking_revision`;
- `field-add:adriatic:src.Fixture.quest_tracking_suppressed`;
- `field-add:adriatic:src.Fixture.tracked_quest_node`.

The resolution table must then contain exactly 16 scripted and zero unresolved
entries in accepted report order. Successful typed execution returns `.None`;
production 1→2 returns an owned result. Remove the obsolete story-unresolved
return, but leave runtime fallback behavior untouched.

### Validate frozen v1 story invariants

Perform every story validation and build the complete migrated quest into a
local value before the first existing array resize or farm write. Any story
failure returns `.Invalid_Source` with exact borrowed change ID
`field-add:adriatic:packages/story.State.quest`. Direct failure must leave the
whole tentative fixture byte/header/backing-equivalent to its pre-call state;
production failure must discard both arenas and return the same ID as
`.Step_Failure`.

Freeze the old counter rules from the actual pre-quest implementation:

- completed main deliveries by romance stage are `0, 1, 2, 3, 4, 4` for
  `Unintroduced`, `First_Letter`, `Corresponding`, `Invitation`, `Meeting`,
  and `Together`;
- `repeat_deliveries` must be zero before `Together` and nonnegative at
  `Together`;
- `completed_deliveries` must equal the frozen main count plus
  `repeat_deliveries`;
- historical `stamps_earned` must equal historical
  `completed_deliveries`;
- reject any addition or new-airfield reward that would overflow host `int`;
  use checked bounds before arithmetic;
- `has_wing_patch` must be true only at `Diagnosed` and false at
  `Not_Seen`, `Crash_Reported`, `Patched`, and `Repaired`;
- `Meeting` and `Together` require repair stage `Repaired`, because v1 could
  not complete the regatta acceptance before repair.

Inactive delivery payloads may retain the last completed delivery and must be
preserved without reinterpretation. An active delivery must match this exact
frozen table:

- `First_Letter`: romance `Unintroduced`, Niko→Iva, West→East, subject
  `A recipe for a clear morning`;
- `First_Reply`: romance `First_Letter`, Iva→Niko, East→West, subject
  `The lighthouse keeper's reply`;
- `Regatta_Invitation`: romance `Corresponding`, Niko→Iva, West→East,
  subject `An invitation for the regatta`;
- `Regatta_Acceptance`: romance `Invitation`, repair `Repaired`, Iva→Niko,
  East→West, subject `Meet me beneath the blue awning`;
- `Repeat_Eastbound`: romance `Together`, even `repeat_deliveries`, Niko→Iva,
  West→East, subject `Bread, postcards, and one pressed flower`;
- `Repeat_Westbound`: romance `Together`, odd `repeat_deliveries`, Iva→Niko,
  East→West, subject `Lamp glass and a note for supper`.

Active `.None`, wrong kind/stage, wrong repair, wrong repeat parity, wrong
resident, island, or subject is invalid. Do not normalize or recreate the
delivery; the accepted portable decode already preserved it.

### Freeze version-2 quest state

Build a zeroed local current quest state with definition ID
`two-island-story`, node count `13`, and these frozen index/ID pairs:

- `0/1` First Letter, `1/2` First Reply, `2/3` Regatta Invitation;
- `3/4` Crash Reported, `4/5` Wing Diagnosed, `5/6` Wing Patched;
- `6/7` Repair Verified, `7/8` Ready To Fly;
- `8/9` Regatta Acceptance, `9/10` Awning Meeting, `10/11` Post Route;
- `11/12` Magneto Westbound, `12/13` Magneto Eastbound.

Tail entries `13..<128` remain exact zeros. Freeze status values through
contextual target assignments and generate revision/sequence fields with
small local helpers; never call current quest traversal.

Pristine v1 state means romance `Unintroduced`, repair `Not_Seen`, no active
delivery, and all validated counters zero. Its migrated graph has only
Magneto Westbound `.Available`, activation sequence `1`, revision `1`,
airfield errand `.Not_Offered`, and stamps `0`.

Any started romance branch, started repair branch, or active delivery resolves
the lost airfield chronology by treating the new introduction as completed.
Freeze this base sequence:

1. activate Magneto Westbound as `.Available` at revision `1`;
2. accept it as `.Active` at revision `2`;
3. complete it at revision `3`;
4. activate First Letter `.Available` at revision `4`;
5. activate Crash Reported `.Available` at revision `5`;
6. activate Magneto Eastbound `.Active` at revision `6`;
7. complete Magneto Eastbound at revision `7`.

Both magneto completion counts become `1`; the errand becomes `.Completed`;
current stamps become historical stamps plus the one frozen magneto reward.

Resolve lost inter-branch chronology deterministically: advance repair first,
then romance. Starting from revision `7`, freeze repair transitions:

- `Crash_Reported`: accept Crash, complete it, activate Wing Diagnosed;
- `Diagnosed`: additionally complete Wing Diagnosed and activate Wing Patched;
- `Patched`: additionally complete Wing Patched and activate Repair Verified;
- `Repaired`: additionally complete Repair Verified.

Each acceptance, activation, and completion increments revision exactly as the
version-2 traversal did. Activation and completion arrays record only their
respective transitions. Completed nonrepeatable nodes use `.Completed`;
the next repair objective remains `.Active`.

Then freeze romance transitions:

- an active v1 First Letter at `Unintroduced` accepts First Letter and leaves
  it `.Active` without completing it;
- `First_Letter` accepts and completes First Letter, then activates First
  Reply;
- `Corresponding` additionally completes First Reply and activates Regatta
  Invitation;
- `Invitation` additionally completes Regatta Invitation. If repair is
  `Repaired`, activate and auto-complete Ready To Fly, then activate Regatta
  Acceptance;
- `Meeting` additionally completes Regatta Acceptance and activates Awning
  Meeting;
- `Together` additionally completes Awning Meeting and activates Post Route.

For `Together`, set Post Route completion count directly to the validated
repeat count, leave its status `.Active`, advance revision by that count, and
set its final completion sequence only when the count is nonzero. Do not loop
once per historical repeat. The other active delivery kinds already correspond
to the active objective created by their frozen stage.

After all validations and local construction succeed, retain the accepted 3E2
structural writes, then assign:

- the local quest state to `tentative.story_state.quest`;
- `.Not_Offered` or `.Completed` to
  `tentative.story_state.airfield_errand`;
- validated current completed/repeat counters and projected stamps, preserving
  romance, repair, delivery, wing-patch, tarot, and every unrelated field;
- literal node ID `-1` to `tentative.tracked_quest_node`;
- `false` to `tentative.quest_tracking_suppressed`;
- migrated quest revision to `tentative.quest_tracking_revision`.

The step must still allocate zero bytes.

### Required proof

Add a separate story migration test file; do not make the already-large
structural test absorb the new matrix.

- Build historical values only with
  `packages/fixture_history/v0001.Fixture`. Encode them with portable `hs`,
  wrap at schema version `1` with `fixture_file`, decode the borrowed
  container view, and pass that payload through production 1→2. This is the
  golden v1 container path.
- Assert the container remains version `1`, production returns an owned
  migrated fixture, result arrays retain their arena allocator and survive an
  append, and result/error disposal remains idempotent.
- Assert all 16 report entries are scripted and scaffold validation accepts the
  edited source.
- Cover every inactive romance stage with every repair stage that v1 could
  reach, including both valid inter-branch orderings collapsed into the frozen
  repair-first result. Cover `Together` at zero and nonzero repeats.
- Cover all six valid active delivery kinds, both repeat parities, exact
  metadata preservation, active First Letter at otherwise-pristine progress,
  and inactive stale delivery preservation.
- For golden successes, assert the complete 13-entry status and completion
  arrays, every nonzero activation/completion sequence, final revision,
  definition ID/count, airfield projection, current counters/stamps, and all
  three tracking fields. Also prove all tail quest entries remain zero.
- Copy the migrated story state and run current
  `story.apply_quest_projection` only as a compatibility assertion; frozen
  literal expectations remain authoritative and must not be generated by the
  current catalog or helper.
- Cover counter negatives/mismatches/overflow, illegal patch state,
  `Meeting`/`Together` before repair, active `.None`, every wrong active
  kind/stage, acceptance before repair, repeat parity, and each wrong delivery
  metadata family. Direct failures use the existing complete structural
  snapshot helper and prove no mutation. Representative cases from every
  invariant family also cross production and expose no result.
- Update 3E2 success assertions from exact story `.Unresolved` to `.None`.
  The structural production success must now return and dispose an owned
  result. Keep every structural invalid assertion unchanged.
- Update the existing production historical OOM sweep to use the now-successful
  1→2 baseline, capture its real allocation count, fail every index, and prove
  zero outstanding allocations. Keep current-layout `2→2` bypass proof and
  verify it executes no migration wrapper.
- Measure the typed combined step separately and prove zero new allocations.
  Run golden success at least twice and compare the complete serialized
  migrated state byte-for-byte for determinism.

Add a story-only focused Makefile target if that keeps iteration fast, and add
the story test to the accepted migration target. Format all edited Odin files.
Run story-only, full migration, `make check`, real codec, scaffold check,
double history generation/history check, full tests, and schema check.
Expected repository failure remains only frozen `City_Plan.structures`.
Frozen schema/history hashes remain unchanged; record the new migration source
hash. Remove binaries and probes.

### Acceptance criteria

- One contiguous 1→2 step uses both historical and tentative current views.
- All 16 fifth-audit state changes are scripted and explicitly tested.
- Every valid v1 story state maps to one deterministic frozen v2 graph.
- Ambiguous or impossible v1 story state fails before any tentative mutation.
- Golden v1 container migration succeeds with owned, disposable current state.
- Failure discards both arenas and exposes no migrated fixture.
- Combined structural/story step allocates zero bytes.
- No live editor, file I/O, rehydration, or schema bump exists yet.

### Execution evidence — 3E3

The version-1-to-version-2 script now marks all 16 audit resolutions
`.Scripted` and returns `.None` on success. It builds the frozen quest graph
from literal version-1 rules before any structural resize or farm write. No
current catalog, quest traversal, projection, capacity constant, or runtime
fallback is used by the migration source. Story validation rejects invalid
counter arithmetic, wing-patch state, repair/romance combinations, active
delivery stage/kind/repair/parity, and all delivery metadata families with
the exact quest change ID before tentative mutation.

The dedicated story test builds historical generated v1 values, wraps them in
a schema-version-1 product container, decodes a borrowed view, and runs the
production migration. It covers every valid romance/repair matrix, all six
active delivery kinds and repeat parities, stale inactive delivery
preservation, hostile counter/branch/delivery cases through both direct and
production paths, idempotent disposal, zero outstanding allocations, result
array append ownership, current projection compatibility, and a combined
zero-allocation typed step. Two successful golden migrations are serialized
and compared byte-for-byte.

The focused migration target passes 5 tests with zero leak diagnostics.
`make check`, real codec, scaffold check, two history generations, and
history check pass. Full tests execute 507 cases with 506 passing; schema
check and the sole full-test failure remain the frozen
`City_Plan.structures` mismatch. Frozen schema/history hashes remain
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12` and
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
The migration source hash is
`82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`.

### Reviewer verification — 3E3

Not yet accepted. The isolated implementation stays inside the six allowed
files. Production migration matches the frozen design: all 16 entries are
scripted; legacy counters, patch state, branch compatibility, active delivery
metadata, and overflow are validated before any tentative write; repair is
advanced before romance; exact v2 quest state is built without current
catalog/traversal helpers or allocation; structural writes remain intact; and
success returns `.None`. No production defect was found in static review.

Independent execution of the five focused tests passes under the locked
`e80202a09` compiler in 2m18.493s with zero leak diagnostics. Frozen
schema/history hashes remain
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12` and
`e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
the submitted migration hash
`82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`
matches. Subsequent independent project-gate execution was blocked because the
shared `/Users/wolfie/install/odin/odin` changed during review from locked
`e80202a09` to `77d6e8a9a`; `make check` correctly rejected that external
toolchain drift before compiling.

Acceptance remains blocked by proof gaps:

- the golden assertion checks activation and completion sequences only for
  being nonzero. It does not assert their exact frozen values, exact complete
  13-entry completion array, or final quest revision. Tracking revision is
  compared only to that unverified result, so repair-first chronology could
  drift while every test stays green;
- the direct hostile helper does not construct the valid delivery metadata
  used by the container helper and ignores `metadata_mode`. Active wrong-stage,
  repair, parity, and all five metadata cases therefore fail for blank or zero
  metadata before the intended invariant is isolated. Production cases are
  precise, but direct atomic cases do not prove the claimed matrix;
- `Meeting` before repair is covered, but `Together` before repair and a
  positive stamps-only mismatch are absent. Only one generic wrong
  kind/stage pair exists rather than one for every active delivery kind;
- the successful production 1→2 result is disposed but never checks its array
  allocator or appends after return. Existing append tests cover current 2→2
  and custom wrappers, not the new golden production migration. Execution
  evidence overstates this proof.

## Milestone 3E3R — Complete frozen story proof

### Next slave handoff

Test-only repair unless a new exact oracle exposes a production mismatch. Keep
`src/fixture_migration_v0001_to_v0002.odin` byte-identical at SHA
`82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`.
Edit only:

- `src/fixture_migration_story_test.odin`;
- `src/fixture_migration_test.odin` for golden production result ownership;
- the focused Makefile target only if a story-only test is split;
- this plan.

Do not touch structural tests, runtime, codec/container, portable `hs`,
schema/history/scaffold tooling, manifests, generated history, current
story/quest code, fixture types, or schema version.

Replace loose story assertions with one independent frozen expected-state
oracle. It may use test-local helpers, but it must use literal node indexes,
statuses, and event order from the 3E3 handoff and must not call production
migration helpers, current quest traversal, current catalog initialization, or
current projection to generate expectations. For every successful case,
compare exactly:

- definition ID, node count, and final revision;
- all 128 statuses;
- all 128 completion counts;
- all 128 activation sequences;
- all 128 completion sequences;
- airfield stage, completed/repeat/stamp counters, and three tracking fields.

Keep current `story.apply_quest_projection` only as an additional compatibility
assertion after exact frozen comparison.

Pin explicit canonical checkpoints so the oracle itself cannot silently share
one off-by-one rule with production:

- pristine: revision `1`, only Magneto Westbound `.Available`, activated at
  `1`;
- active First Letter with otherwise pristine v1 state: revision `8`, both
  magneto nodes completed, First Letter `.Active`;
- repaired-only with no romance: revision `15`;
- Invitation without repair: revision `13`, Ready and Acceptance locked;
- Invitation with repair: revision `24`, Ready completed and Acceptance active;
- Meeting with repair: revision `26`, Acceptance completed and Meeting active;
- Together with repair and zero repeats: revision `28`, Post Route active;
- Together with repair and one repeat: revision `29`, Post completion count
  `1`, final Post completion sequence `29`.

Factor one historical-story population helper used by both container and
direct paths. It must first create a valid case with exact counters, patch
state, delivery kind, residents, islands, and subject, then apply only the
requested hostile mutation. The direct helper must honor `metadata_mode`.
Before executing a direct hostile case, prove its baseline counterpart
migrates successfully; then mutate one field, take the complete 3E2 snapshot,
call the step, and prove exact quest ID plus no mutation.

Expand hostile coverage:

- one correct-metadata wrong-stage case for each of the six active delivery
  kinds;
- Acceptance at Invitation before repair;
- both repeat kinds with wrong parity;
- both Meeting and Together before repaired state;
- negative repeats, repeats before Together, completed mismatch, positive and
  negative stamps-only mismatch, checked-add overflow, and inverted patch
  state at each repair stage;
- active `.None`;
- subject, source resident, destination resident, origin island, and
  destination island changed independently.

Run every case directly with the full atomic snapshot. Cross at least one
precise case from each invariant family through the schema-v1 product
container and production dispatch, preserving exact quest ID, empty result,
idempotent disposal, and zero outstanding allocations.

On successful production 1→2 in
`fixture_migration_transaction_paths_and_ownership`, inspect at least one
migrated dynamic-array header and prove its allocator points at the returned
arena. Append one element after return, verify length/content, then dispose
twice. Add the same assertion to one golden container case if it remains
cheap. This proof must use the production registry, not current-layout bypass
or a custom wrapper.

Retain all existing valid stage/repair cases, six active deliveries, stale
inactive delivery, determinism, combined zero-allocation step, current 2→2
bypass, transaction OOM sweep, and scaffold/report checks.

Run story-only first if a target is added, then the five-test migration target
under the locked compiler. Run `make check`, real codec, scaffold check,
double history generation/history check, full tests, and schema check.
Expected repository failure remains only frozen `City_Plan.structures`.
All three accepted hashes must remain unchanged. Clean binaries and probes.

### Acceptance criteria

- every golden graph byte of durable quest state has an exact frozen oracle;
- every hostile case fails for its intended single invalid invariant;
- repair-first revision/sequence chronology is pinned against off-by-one drift;
- successful production v1 migration owns appendable arrays after return;
- production source and accepted hashes remain unchanged.

### Execution evidence — 3E3R

The story test now uses an independent literal event oracle for all 128 quest
slots, exact revision checkpoints, valid baseline fixtures for every hostile
case, the complete active-delivery stage matrix, metadata mutations, repair
patch inversions, Together-before-repair, and positive/negative stamp-only
mismatches. Direct hostile cases preserve valid delivery metadata before one
requested mutation and prove the baseline migration succeeds. The product
1→2 result and a golden migrated result both prove arena-backed array headers,
append after return, appended content, and idempotent disposal.

The five focused migration tests pass under the repository-pinned compiler
`dev-2026-07:a6e9c7f2f` (`a6e9c7f2` pin) in 2m51.449s with zero leak
diagnostics. `make check` passes. Frozen v1 schema/history hashes and the
production migration hash remain unchanged:

- `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`
- `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`
- `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`

### Reviewer verification — 3E3R (superseded by 3E3R2)

The prior review confirmed the repaired test compared the
exact definition, count, revision, and all 128 entries of every durable quest
array. The valid romance/repair matrix, six active delivery kinds, stale
inactive delivery, 29 hostile cases with successful baselines, all five
metadata mutations, repair patch inversions, stage/parity/stamp/counter
families, direct atomic snapshots, product failures, and both product/golden
append ownership proofs are present. No production migration defect was found.

The five focused migration tests pass independently under the repository's
current locked `dev-2026-07:a6e9c7f2f` compiler in 2m51.449s with zero leak diagnostics.
The repository pin changed outside this repair from `e80202a09` to
`a6e9c7f2`; `make doctor` now succeeds, so the submitted note about a
`77d6e8a9a` lock blocker is stale. The three accepted hashes remain unchanged.

The former literal-checkpoint hole was the blocker handed to 3E3R2: the
successful active kind-6 one-repeat Together case did not enter the checkpoint.
3E3R2 repairs that branch and adds direct Post Route status, count, and
completion-sequence assertions.

## Milestone 3E3R2 — Execute the repeat-one literal checkpoint

### Next slave handoff

This is a test-and-plan-only repair. Edit only:

- `src/fixture_migration_story_test.odin`;
- this plan.

Do not touch the production migration, runtime, structural or transaction
tests, Makefile, toolchain lock, codec/container, portable `hs`, schema or
history tooling, manifests, generated history, current story/quest code,
fixture types, or schema version. Keep production migration SHA
`82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`
byte-identical.

Make the existing successful active Together case with kind `6` and one repeat
execute a literal checkpoint independent of
`fixture_migration_story_test_expected_quest`. The simplest repair is to make
the romance `5`, repair `4` checkpoint cover both active and inactive delivery
states, then distinguish literal repeat counts:

- repeat `0`: revision `28`, Post Route status `.Active`, completion count `0`,
  and completion sequence `0`;
- repeat `1`: revision `29`, Post Route status `.Active`, completion count `1`,
  and completion sequence `29`.

Use literal Post Route index `10`. Do not derive these values by calling a
production helper, catalog traversal, current projection, or the expected-state
oracle. Keep the exact 128-slot oracle and every existing case intact. Invalid
cases must not reach the success checkpoint.

Run `make fixture-migration-test` under the repository-pinned compiler and
record the exact compiler/version and duration. Because this repair changes no
production code, also run `make check`, confirm no leak diagnostics, verify the
three accepted hashes, and remove any generated binary. Replace the stale
3E3R execution note with current locked evidence; do not edit `toolchain.mk`.

### Acceptance criteria

- an existing successful one-repeat Together case demonstrably executes the
  literal revision/completion checkpoint;
- zero-repeat Together still pins revision `28` and an empty completion
  sequence;
- all five migration tests and `make check` pass with zero leaks;
- production source and all three accepted hashes remain unchanged;
- the isolated 3E3R2 diff contains only the story test and this plan.

### Execution evidence — 3E3R2

The literal Together checkpoint now covers both active and inactive delivery
states. It uses literal Post Route index `10` and directly pins revision `28`
with `.Active`, completion count `0`, and completion sequence `0`, or revision
`29` with `.Active`, completion count `1`, and completion sequence `29`. The
existing active kind-6 one-repeat case therefore executes the independent
revision-29 proof.

Only `src/fixture_migration_story_test.odin` and this plan changed. The five
migration tests pass under locked `dev-2026-07:a6e9c7f2f` in 2m51.449s;
`make check` passes; zero leak diagnostics were reported; and no generated
binaries remain. The schema, generated-history, and production-migration
hashes remain unchanged.

### Reviewer verification — 3E3R2

Accepted. The isolated delta contains only the story test and this plan. The
existing successful active kind-6 case now enters the literal Together
checkpoint. Literal Post Route index `10` pins `.Active`, count `0`, sequence
`0`, and revision `28` for zero repeats, or `.Active`, count `1`, sequence
`29`, and revision `29` for one repeat. These assertions do not use the
expected-state oracle, production migration helpers, catalog traversal, or
projection.

Independent `make fixture-migration-test` passes all five tests under locked
`dev-2026-07:a6e9c7f2f` in 2m57.912s with zero leak diagnostics.
`make check` passes. No generated binary remains. Frozen schema, generated
history, and production migration retain their accepted hashes:

- `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`.

## Milestone 3F1 — Freeze and activate schema version 2

### Next slave handoff

This milestone only activates the already-audited current schema. It does not
integrate migration into the fixture codec yet.

### Allowed files

- change only `FIXTURE_SCHEMA_VERSION` in `src/main.odin`;
- add generated `fixtures/schema/v0002.fixture-schema`;
- update the production integration expectations in
  `tests/fixture_schema_test.odin`;
- update the production integration expectations in
  `tests/fixture_schema_diff_test.odin`;
- update this plan.

Do not touch version-1 manifest/history, generated history tooling or package,
semantic diff/scaffold/install code, migration runtime or script, fixture
codec/container, portable `hs`, serializable structs, Editor state, Makefile,
or toolchain lock. Do not generate a v2 historical Odin package; the immutable
v2 manifest is sufficient input for later milestone 6 generalization.

Before editing, record SHA-256 for:

- `fixtures/schema/v0001.fixture-schema`;
- `packages/fixture_history/v0001/schema.generated.odin`;
- `src/fixture_migration_v0001_to_v0002.odin`;
- the current in-memory candidate produced by the schema walker.

The expected pre-activation values are:

- frozen v1 manifest:
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- generated v1 history:
  `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- production 1→2 migration:
  `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`;
- version-1-header candidate:
  `eab829c2335fb7d61ceb5322b05c1f7b74f986aed30fead4d7837e975823a336`.

Change the source-owned immutable declaration from
`FIXTURE_SCHEMA_VERSION :: 1` to `FIXTURE_SCHEMA_VERSION :: 2`. Do not change
any fixture-reachable field, type, tag, constant, or enum value in this
milestone.

Run `make fixture-schema-generate` to create the v2 manifest. Never hand-edit
the generated file. Run generation again and prove byte-identical output and
an unchanged SHA. The generated manifest must have:

- `format_version=1`;
- `fixture_schema_version=2`;
- the same root ID as v1;
- 1,371 lines, 149 records, and 145 root fields;
- no difference from the audited pre-activation candidate except the schema
  version line.

Run the production semantic diff from v1 to the now-version-2 candidate. It
must still report exactly 21 changes: 16 state-bearing and five supporting,
with the exact IDs and policies frozen by
`fixture_schema_diff_production_is_exact_and_round_trips`. No new, missing, or
reordered semantic change is allowed. Record the new v2 manifest SHA and use
it as the production candidate SHA expectation. Preserve all synthetic parser,
ordering, hostile-input, OOM, and disposal tests unchanged.

Update only production integration expectations:

- `fixture_schema_production_graph_matches_draft` must expect source version `2`
  and compare the current generated bytes with
  `fixtures/schema/v0002.fixture-schema`;
- `fixture_schema_diff_production_is_exact_and_round_trips` must expect
  candidate version `2` and its new SHA;
- line, record, root-field, change-count, ID, classification, and policy
  expectations remain exact and unchanged.

Update the fifth rebased baseline audit in this plan after generation so it no
longer says the current source version is `1`; record the activated v2 SHA
without rewriting the preserved pre-activation evidence.

Because `fixture_codec_encode` and direct decode already use the source
constant, the existing real codec test must demonstrate a version-2 container
and deterministic current-state round trip without codec source edits. Version
1 codec decode remains deliberately unsupported until 3F2; production 1→2
migration remains proven only through `fixture_migration_run`.

### Required proof

Run, in this order:

1. `make fixture-schema-generate` twice;
2. `make fixture-schema-check`;
3. the focused schema and semantic-diff tests, or `make test` if no narrower
   stable target exists;
4. `make fixture-migration-scaffold-check`;
5. `make fixture-history-generate` twice and `make fixture-history-check`;
6. `make fixture-codec-test`;
7. `make fixture-migration-test`;
8. `make check`;
9. `make test`.

After both schema generations, compare v2 SHA values exactly. After both
history generations, confirm the v1 generated-history SHA remains exact.
Confirm the v1 manifest and production migration hashes remain exact. Inspect
the isolated `jj diff --git`: it must contain only the five allowed paths, no
v1 byte changes, and no formatter drift outside edited test lines. Remove
generated binaries and probes.

### Acceptance criteria

- source schema version is exactly `2`;
- immutable v1 bytes and all prior accepted hashes are unchanged;
- one generated immutable v2 manifest exactly matches the current walker;
- v1→v2 semantic report remains exactly 21/16/5 with the accepted IDs and
  policies;
- current codec emits and directly decodes only version 2 without codec edits;
- schema check and full test suite have no former frozen-schema mismatch;
- every required gate passes under the locked compiler with zero leaks;
- no migration-aware codec behavior or editor mutation begins.

### Execution evidence — 3F1R

Schema activation is complete and isolated: source version `2`, generated v2
manifest SHA-256
`0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`, 1,371
lines, 149 records, and 145 root fields. Generation twice is byte-identical;
schema check, exact 21/16/5 semantic diff, history generation/check, codec,
migration, `make check`, and the production schema expectations pass. The v1
manifest, v1 history, and production migration hashes remain unchanged.

The repaired scaffold guard accepts only candidate version 1 or 2 for the
contiguous 1→2 migration and rejects unrelated versions with an actionable
diagnostic. The shared production helper expects candidate version 2. The two
formerly failing scaffold tests pass in 191ms with zero leak diagnostics;
scaffold check and no-overwrite scaffold generation both pass.

The full suite passes all 507 tests in 1.378s. Codec, migration, `make check`,
schema generation/check, history generation/check, and semantic diff gates all
pass under locked `dev-2026-07:a6e9c7f2f`. The v2 manifest SHA is unchanged at
`0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`; v1
manifest, v1 history, and production migration hashes remain exact. No
generated binaries remain.

### Reviewer verification — 3F1 (superseded by 3F1R)

The prior review confirmed schema activation itself was correct. The isolated delta
contains exactly the five allowed paths. `FIXTURE_SCHEMA_VERSION` is `2`; the
generated v2 manifest has 1,371 lines, 149 records, 145 root fields, and SHA-256
`0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`.
The current walker matches it, and the exact semantic report remains 21
changes, 16 state-bearing and five supporting. Frozen v1 manifest, generated
v1 history, and production migration retain their accepted hashes.

3F1R repaired the phase-boundary guard and shared expectation without changing
the semantic report, renderer, parser, ABI validator, installed script,
migration registry, or runtime.

## Milestone 3F1R — Validate scaffold across schema activation

### Next slave handoff

Repair only the migration-scaffold phase guard and its shared production test
fixture.

### Allowed files

- `tools/fixture_schema/main.odin`;
- `tests/fixture_migration_scaffold_test.odin`;
- this plan.

Do not edit `tests/fixture_migration_install_test.odin`; its failing production
test uses the shared helper and must recover without a local exception. Do not
touch package-level schema diff/scaffold/install code, Makefile, source schema
version, either manifest, generated history, fixture codec/container,
migration types/runtime/script/tests, serializable state, Editor code, or
toolchain lock. Do not begin 3F2.

In `migration_scaffold_report`, keep a strict candidate-version guard, but
recognize both valid workflow phases for one contiguous `from_version` →
`to_version` migration:

- before activation, candidate version may equal `from_version`;
- after activation, candidate version may equal `to_version`;
- every other version must still fail before semantic report construction.

Do not delete the check or accept an arbitrary positive version. Keep the
existing contiguous-version and CLI 1→2 restrictions unchanged; later
multi-version generalization belongs to milestone 6. Update the failure
diagnostic to say the candidate must match the migration source or target so
future failure is actionable.

In `migration_scaffold_production_report`, change only the current production
candidate expectation from version `1` to version `2`. Keep:

- frozen manifest path at v1;
- report endpoints at 1→2;
- generated import and `#by_ptr fixture_v0001.Fixture` ABI;
- all 16 exact state IDs and resolution kinds;
- synthetic 1→2 and 2→3 renderer/parser cases;
- hostile metadata, entry, version, encoding, limit, OOM, and ownership tests.

Do not replace other literal `1` values in the scaffold tests. Most describe
the historical source and must remain `1`.

### Required proof

1. Run only the two formerly failing tests using the exact names printed by
   the runner. Both must pass with zero leaks.
2. Run `make fixture-migration-scaffold-check`; it must validate the existing
   scripted 1→2 source against current schema v2.
3. Run `make fixture-migration-scaffold` against the existing target. It must
   report the existing source without rewriting it. Hash the migration before
   and after and retain
   `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`.
4. Run `make fixture-schema-generate` twice and
   `make fixture-schema-check`; v2 must remain
   `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`.
5. Run `make fixture-history-generate` twice and
   `make fixture-history-check`; v1 history must retain
   `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`.
6. Run `make fixture-codec-test`, `make fixture-migration-test`,
   `make check`, and `make test`.

Full suite must pass all 507 tests. Confirm frozen v1 manifest SHA remains
`2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`.
Inspect isolated `jj diff --git`: 3F1R must add only the three allowed paths
on top of accepted 3F1 files. Remove generated binaries and probes.

### Acceptance criteria

- pre-activation source-version candidates and post-activation target-version
  candidates are the only accepted scaffold phases;
- unrelated candidate versions remain rejected by a clear diagnostic;
- existing 1→2 scripted source validates byte-identically after activation;
- both former scaffold test failures and all 507 tests pass;
- every 3F1 gate is green with zero leaks and all four recorded hashes exact;
- no codec migration integration or editor behavior begins.

### Reviewer verification — 3F1R

Accepted. The isolated repair contains exactly the CLI guard, one shared
production test expectation, and this plan. The guard accepts only the
contiguous migration endpoints, preserves the existing source-phase workflow,
admits the activated target phase, and still rejects unrelated versions. The
shared helper remains frozen-v1 to candidate-v2, so both scaffold and installed
script tests validate the original 1→2 ABI and 16 exact obligations.

Independent `make fixture-migration-scaffold-check` passes. Independent
`make test` passes all 507 tests under locked `dev-2026-07:a6e9c7f2f` in
1.457s with zero leak diagnostics, and `make check` passes. Frozen v1,
activated v2, generated v1 history, and production migration hashes are exact:

- `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`.

## Milestone 3F2A — Add the owned migration-aware codec contract

### Next slave handoff

Replace the unsafe caller-mutating decode boundary with one owned result that
delegates both supported container versions to the accepted migration
transaction.

### Allowed files

- `src/fixture_codec.odin`;
- `src/fixture_codec_test.odin`;
- this plan.

Do not touch fixture migration types, result disposal, registry/runtime,
version-specific migration or its tests; container or portable `hs`; schema,
history, diff, scaffold, install, or manifests; serializable structs; Editor
or rehydration code; Makefile; or toolchain lock. Do not begin file I/O,
live-state replacement, OOM sweeps, or editor load.

### Decode ABI and ownership

Replace the current
`fixture_codec_decode(fixture: ^Fixture, data, allocator)` procedure. There are
no production callers and no compatibility wrapper is required.

The canonical procedure must accept only borrowed container bytes and a caller
allocator, and return:

- the existing `Fixture_Migration_Result`;
- one `Fixture_Codec_Error`;
- success boolean.

Do not introduce a second arena/result owner, copy a result `Fixture` into
caller storage, or shallow-copy its dynamic arrays. Successful ownership stays
exactly with `Fixture_Migration_Result` and is released only by the existing
nil-safe, idempotent `fixture_migration_result_dispose`. On every failure,
return an empty disposable result with no fixture or arena.

Keep encode unchanged except for any comment needed to describe the paired
owned decode API. It must continue to accept a borrowed current `^Fixture`,
return caller-owned bytes, and always write schema version `2`.

### Decode flow

Use this exact order:

1. Reject a nil allocator procedure as `.Invalid_Argument` before container or
   migration work.
2. Decode the borrowed `ADRFIX` container. Preserve exact container diagnostics
   for truncation, magic, format, flags, size, checksum, and schema zero.
3. Reject schema versions outside the currently supported inclusive range
   `1 ... FIXTURE_SCHEMA_VERSION` before migration allocation. Use
   `.Schema_Mismatch`; future version `3` must not reach the registry.
4. Call `fixture_migration_run` with the borrowed payload, container source
   version, current target `FIXTURE_SCHEMA_VERSION`, and caller allocator.
5. Schema version `2` therefore uses the proven zero-step current decode.
   Schema version `1` uses the proven production 1→2 step.
6. Return the migration result only when migration succeeds. On failure,
   dispose any defensive nonempty result, preserve the complete migration
   error, and expose no fixture.

The input container and borrowed payload must never be freed or mutated.

### Codec error contract

Add a codec `.Migration` error kind and store the complete
`Fixture_Migration_Error` by value in `Fixture_Codec_Error`. Preserve exact
`kind` and borrowed `change_id`, especially `.Step_Failure` from the scripted
v1 migration. Codec error disposal must delegate to
`fixture_migration_error_dispose`, remain nil-safe/idempotent, then zero the
entire codec error.

Current portable decode errors now arrive through the migration transaction as
`.Tentative_Decode`; remove the old direct `.Portable_Decode` codec branch
rather than fabricating an empty `hs.Portable_Error`. Portable encode remains
owned and unchanged.

Do not collapse container corruption, unsupported schema, tentative portable
decode, historical decode, scripted step failure, and out-of-memory into one
kind. The outer codec kind identifies container/schema/migration; the nested
migration kind and change ID retain migration detail.

### Required success proof

Rewrite the real codec test for the owned API without reducing its current
Fixture coverage.

For a current v2 fixture:

- encode twice and retain exact deterministic container comparison;
- prove container version `2` and all existing inclusion/exclusion checks;
- decode to an owned migration result and assert nonnil fixture/arena;
- retain the existing representative scalar, fixed-array, dynamic-array,
  nested, enum, string, and excluded-field assertions;
- inspect at least one decoded dynamic-array header and prove its allocator
  points at the returned arena;
- encode the owned fixture before mutation and prove the complete container is
  byte-identical to the original v2 container;
- then append after return and verify length and content;
- dispose result and error twice.

For a golden v1 container:

- reuse the accepted generated-v1 payload helper rather than cloning a second
  historical schema builder;
- wrap its payload with schema version `1` using the real container;
- decode only through `fixture_codec_decode`;
- prove representative historical fields survive, fixed arrays shrink to
  their counts, farm defaults are applied, frozen story/tracking state exists,
  and migrated dynamic arrays are arena-owned and appendable;
- prove source container remains version `1` and byte-identical;
- re-encode migrated state and prove the new container is version `2`;
- run the v1 decode/re-encode twice and compare complete v2 containers
  byte-for-byte before either result is mutated for append ownership;
- dispose every result/error twice.

The v1 helper lives under the same `main` test package and is already compiled
by the focused source test target. Do not move it or make production codec
depend on test helpers.

### Required basic failure proof

Every case returns an empty result and supports double disposal:

- nil allocator;
- every truncated container header length;
- checksum corruption;
- valid container carrying future schema version `3`;
- malformed portable payload in a valid schema-v2 container, preserved as
  nested `.Tentative_Decode`;
- one valid schema-v1 payload with an invalid structural count, preserved as
  nested `.Step_Failure` with the exact structural change ID.

Keep container/payload snapshots and prove decode never mutates borrowed input.
Do not add exhaustive allocation-failure sweeps yet; they belong to 3F2B.

Remove obsolete caller-destination sentinels and temporary virtual decode
arenas from the test. The owned migration arena is now the only successful
decode lifetime. Remove imports made dead by that change and format only the
two Odin files.

### Required gates

Run:

1. `make fixture-codec-test`;
2. `make fixture-migration-test`;
3. `make fixture-migration-scaffold-check`;
4. `make fixture-schema-check`;
5. `make fixture-history-check`;
6. `make check`;
7. `make test`.

Confirm all four accepted hashes remain exact. Inspect isolated
`jj diff --git`: only the two codec files and this plan may change. Remove
generated binaries and probes.

### Acceptance criteria

- codec decode has one owned, atomic result and no caller-mutating form;
- schema v2 bypasses steps and schema v1 executes exactly the production 1→2
  step;
- both successful paths own appendable arena-backed state and deterministically
  re-encode only as v2;
- basic container, version, portable, and scripted failures expose empty
  results with exact diagnostics;
- borrowed input is immutable and disposal is nil-safe/idempotent;
- all required gates pass with zero leaks and accepted hashes unchanged;
- no Editor mutation, file I/O, or allocator torture begins.

### Execution evidence — 3F2A

The codec now accepts borrowed container bytes and returns the existing owned
`Fixture_Migration_Result`. It validates the container and supported schema
range before dispatch, routes schema v2 through zero-step current decode, and
routes schema v1 through the accepted production 1→2 migration. No
caller-mutating compatibility procedure remains.

Codec errors now preserve complete nested migration kind and change ID.
Failure returns an empty double-disposable result; success retains the
migration arena until explicit result disposal. The real codec test proves
exact v2 decode/re-encode, v1 migration to deterministic v2 bytes, arena-backed
append ownership, borrowed-input immutability, future-version rejection,
tentative portable failure, and exact scripted structural failure.

Only `src/fixture_codec.odin` and `src/fixture_codec_test.odin` changed.
Focused codec passes with zero leaks. Full suite passes 507/507; `make check`,
schema/history checks, and migration tests pass. No generated binary remains.

### Reviewer verification — 3F2A

Accepted. Static review confirms the decode ABI has one owner, delegates both
versions to the migration transaction, rejects versions outside `1 ... 2`
before dispatch, preserves outer container/schema/migration classification,
and retains nested `.Tentative_Decode` or exact `.Step_Failure` change ID.
No shallow copy, partial destination, production caller, Editor mutation, or
file I/O exists.

Independent focused codec passes under locked `dev-2026-07:a6e9c7f2f` in
17.165s with zero leak diagnostics. Independent migration tests pass 5/5 in
2m55.610s, full suite passes 507/507 in 1.700s, and `make check` passes. All
four accepted hashes remain exact:

- `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`.

## Milestone 3F2B — Harden codec decode allocation and failure ownership

### Next slave handoff

Add a separate test-only allocation and preflight hardening layer around the
accepted owned codec. Production changes are not expected.

### Allowed files

- add `src/fixture_codec_oom_test.odin`;
- update only the existing `fixture-codec-test` test-name list in `Makefile`;
- update this plan.

Do not edit `src/fixture_codec.odin` or the accepted real codec test. If a
reproducible sweep failure exposes a production defect, stop and report the
exact failing allocation index and ownership state instead of widening scope.
Do not touch migration types/runtime/script/tests; container or portable `hs`;
schema/history/diff/scaffold/install tooling or artifacts; serializable state;
Editor code; or toolchain lock.

Add one test named
`fixture_codec_owned_decode_allocation_failures_and_preflight` under the
existing `main` test package. Add it beside the accepted real codec test in
`ODIN_TEST_NAMES`; the focused target must run exactly two codec tests. Reuse
existing codec payload builders, byte comparison, generated-v1 payload helper,
and migration fault allocator. Do not duplicate a Fixture or historical schema
builder.

### Successful-baseline ownership

Build two immutable containers outside the fault allocator:

- a current v2 container from `fixture_codec_test_source` and
  `fixture_codec_encode`;
- a historical v1 container from
  `fixture_migration_test_historical_payload` and the real fixture container.

Snapshot both byte-for-byte.

For each container, first decode successfully with a fresh tracking allocator
whose backing allocator is `runtime.default_allocator()` and whose failure
index is disabled. Assert:

- success, empty codec error, nonempty result, fixture, and arena;
- allocation-attempt count is positive;
- outstanding allocation count is positive while the result is alive;
- input bytes remain identical;
- codec error disposal twice changes no ownership;
- result disposal twice returns outstanding allocation count exactly to zero.

Record each successful path's real allocation-attempt count. Do not hardcode
compiler-specific counts.

### Exhaustive decode OOM sweeps

For every allocation index from zero through one less than the successful
count, use a fresh tracking state and decode the unchanged container again.
Run this independently for v2 zero-step decode and v1 migration decode.

Every injected failure must prove, before and after double disposal:

- `ok == false`;
- exact outer codec kind `.Migration`;
- exact nested migration kind `.Out_Of_Memory`;
- empty result with nil fixture and arena;
- no caller allocation remains outstanding;
- allocation attempts stop at the injected failure;
- borrowed container bytes remain identical to the snapshot.

Do not accept `.Tentative_Decode`, `.Historical_Decode`, `.Step_Failure`, or a
generic schema error for an injected allocation failure. Do not mutate one
fault state and reuse it across iterations; each failure receives fresh
counters and allocator identity.

### Zero-allocation preflight matrix

Use a tracking allocator armed to fail at allocation zero. For each case below,
decode must return the exact non-migration error while
`allocation_calls == 0`, `outstanding == 0`, result is empty, input bytes are
unchanged, and result/error disposal twice is harmless:

- every container length shorter than the 32-byte header;
- invalid magic;
- unsupported container format version;
- unsupported nonzero flags;
- schema version zero;
- forged payload length producing trailing bytes;
- forged payload length producing truncation;
- forged payload length producing host overflow;
- forged payload length exceeding the configured cap;
- payload/checksum corruption;
- one valid checksummed container carrying future fixture schema version `3`.

Use one compact valid envelope with a tiny test payload for this matrix; do not
copy the 28 MiB real fixture container for header-only cases.

Container-envelope failures use outer `.Container_Decode` and exact nested
`fixture_file` kind. Future fixture schema uses outer `.Schema_Mismatch`.
Construct corruptions in test-owned copies; do not weaken or duplicate
production container validation.

### Tracked semantic-failure cleanup

With failure injection disabled but the tracking allocator active, also run:

- a valid schema-v2 container containing malformed portable bytes;
- a valid schema-v1 container containing the accepted out-of-range historical
  structural count.

The first must return nested `.Tentative_Decode`; the second must return nested
`.Step_Failure` with
`FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID`. Both must expose an empty
result, preserve input, clean all allocations before return, and tolerate
double result/error disposal.

Keep helpers narrow: little-endian header writers, one preflight expectation,
and one OOM sweep helper are enough. This test is about the codec boundary, not
a second container or migration suite.

### Required gates

Run the focused codec target at least twice, then:

1. `make fixture-migration-test`;
2. `make fixture-migration-scaffold-check`;
3. `make fixture-schema-check`;
4. `make fixture-history-check`;
5. `make check`;
6. `make test`.

The focused codec target must pass both tests with zero leaks. The repository
suite must remain 507/507: `make test` runs the separate `tests` package and
does not include either source-package codec test. Confirm all four accepted
hashes remain exact. Inspect isolated
`jj diff --git`: only the new test file, one Makefile test-name hunk, and this
plan may change. Remove generated binaries and probes.

### Acceptance criteria

- every real v2 and v1 decode allocation can fail without leak or partial
  result;
- injected OOM preserves exact nested `.Out_Of_Memory`;
- all envelope and future-version failures perform zero migration allocations;
- tracked semantic failures clean both transaction arenas before return;
- successful result lifetime retains and then releases every caller allocation
  exactly once;
- borrowed bytes remain immutable across every success and failure;
- focused two-test codec target, 507-test repository suite, and all project
  gates pass;
- production codec/migration code and all accepted hashes remain unchanged.

### M3F2B execution record — 2026-07-28

The test-only allocation hardening is implemented in
`src/fixture_codec_oom_test.odin`, and the focused `fixture-codec-test` target
now runs exactly two codec tests. Both independent focused runs pass with zero
leak diagnostics. Real v2 zero-step and v1 migration allocation sweeps cover
every successful allocation index; the zero-allocation envelope matrix and
tracked semantic failures also pass with immutable inputs and empty results.

`make fixture-migration-test`, `make fixture-migration-scaffold-check`,
`make fixture-schema-check`, `make fixture-history-check`, and `make check`
pass. The repository `make test` target reports 507/507; its target runs the
separate `tests` package and does not include the two source-focused codec
tests. The handoff's former 508 requirement was a planner arithmetic error, not
an implementation blocker; widening `make test` would have violated the
accepted target boundary. All four accepted hashes remain exact and no
generated binaries remain.

### Reviewer verification — 3F2B

Accepted. The isolated delta from pre-3F2B snapshot
`6b5bb1b15396f43c75e11aabb69e781fbc7ec0ca` contains only:

- the one permitted `fixture-codec-test` name-list hunk;
- `src/fixture_codec_oom_test.odin`;
- this plan.

Static review confirms fresh fault allocator identity for every injected
failure, dynamically measured success allocation counts, complete v2 and v1
sweeps, exact outer `.Migration` plus nested `.Out_Of_Memory`, zero
outstanding allocations before disposal, immutable borrowed bytes, and
idempotent result/error disposal. The compact envelope matrix performs zero
migration allocations and distinguishes exact container failures from future
schema rejection. Tracked malformed-v2 and invalid-v1 payloads preserve exact
`.Tentative_Decode` and structural `.Step_Failure` classification.

Independent verification under locked `dev-2026-07:a6e9c7f2f`:

- focused codec: 2/2 in 17.829s, zero leak diagnostics;
- migration: 5/5 in 3m2.627s, zero leak diagnostics;
- repository: 507/507 in 1.382s;
- scaffold, schema, history, and `make check`: pass.

The accepted hashes remain:

- `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`.

## Milestone 4 — Rehydrate safely into a live `Editor`

The current schema cannot yet reconstruct one material relationship. Pointer
fields correctly carry `fixture:"-"`, but `vehicles.Character.mode` records
only on-foot versus driving. Once `pilot.vehicle` and each vehicle's `driver`
are removed, a decoded driving fixture cannot distinguish the car, Postale,
Libellula, or Libellula Mk2. `aircraft.active` is selection state and remains
meaningful while the pilot drives the car, so it is not an occupancy oracle.

Do not infer this identity from unrelated physics or presentation fields. A
later schema version must persist an explicit stable occupant discriminator,
and old driving states must be resolved by an explicit migration policy. The
existing history emitter, history parser, schema diff boundary, CLI, and
Makefile targets still hardcode schema/history version 1 or transition 1→2.
Generalize that proven workflow before making the required schema-v3 change.

## Milestone 4A — Generalize history and scaffold versions

### Next slave handoff

Remove only the v1/1→2 version hardcoding from the already accepted schema
history, diff, scaffold CLI, and Makefile entry points. Keep fixture schema 2
active. Do not generate schema 3, history v2, or a 2→3 migration yet.

This is a tooling-generalization milestone, not a parser rewrite. Preserve all
accepted validation, ownership, source-position, OOM, formatting, and
no-overwrite behavior.

### Allowed files

- `packages/fixture_schema/history_manifest.odin`;
- `packages/fixture_schema/history_emit.odin`;
- `packages/fixture_schema/schema_diff.odin`;
- `tools/fixture_schema/main.odin`;
- `tests/fixture_history_test.odin`;
- `tests/fixture_schema_diff_test.odin`;
- `tests/fixture_migration_scaffold_test.odin`;
- only the fixture history/scaffold target definitions and their immediately
  adjacent version variables in `Makefile`;
- this plan.

Do not edit `src/main.odin`, any serializable game-state type, either schema
manifest, generated history v1, codec/container/portable code, migration
runtime or 1→2 script, Editor lifecycle, fixture UI/file I/O, toolchain lock,
or `zelda-engine`. If generalization exposes a defect outside the allowed
files, stop with the exact input and diagnostic.

### Version contract

Keep history manifest format version exactly 1. Fixture schema versions are
canonical positive decimal integers in `1 ... 9999`.

`history_parse_manifest` must parse the second header as
`fixture_schema_version=<version>` and retain the actual version. Reject:

- missing or reordered headers;
- zero and negative values;
- a leading plus sign;
- leading zeroes;
- whitespace or trailing characters;
- integer overflow;
- values greater than 9999.

Retain exact source-line behavior and all existing hostile input caps. Do not
weaken the strict first header, root header, record grammar, reachability, type
validation, or allocation cleanup.

Replace the schema-version equality check in `history_emit_package` with the
same supported range. Emit:

- `package fixture_v%04d`;
- `FIXTURE_SCHEMA_VERSION :: <version>`;
- the existing version comment using the parsed version.

Version 1 input must still emit bytes identical to the frozen accepted
`packages/fixture_history/v0001/schema.generated.odin`. Do not special-case its
whole output or copy the existing generated file.

### Diff contract

`schema_diff_parse_frozen_snapshot` must accept every supported history schema
version while retaining format version 1. `schema_diff_build_report` owns the
transition check:

- `from_version` and `to_version` are supported and contiguous;
- frozen manifest schema version equals `from_version`;
- candidate manifest schema version equals either `from_version` or
  `to_version`.

The candidate may equal the source while an existing scaffold is checked
before activation, or the target after activation. Any other crossing fails
`.Invalid_Input` before report allocation, with a useful root path/message.
Keep candidate/frozen inputs borrowed and every error/result double-disposable.

### CLI and Makefile contract

Generalize `history_version` and `migration_version` to the same canonical
range. Accept every contiguous `from to` pair in `migration-diff`,
`migration-scaffold`, and `migration-scaffold-check`; remove diagnostics that
say versions must be exactly `1 2`.

Keep dynamic paths already defined by the tool:

- `fixtures/schema/v%04d.fixture-schema`;
- `packages/fixture_history/v%04d/schema.generated.odin`;
- `src/fixture_migration_v%04d_to_v%04d.odin`.

Parameterize the existing Make targets with defaults that preserve today's
commands:

- history version defaults to `1`;
- migration source defaults to `1`;
- migration target defaults to `2`.

A caller must be able to request history 2 or scaffold 2→3 by overriding only
those version variables. The history check's Odin package path must use the
same selected version; do not leave its compile command pinned to `v0001`.
Keep the default target output and behavior byte-for-byte equivalent.

`migration-scaffold` retains exclusive no-overwrite installation and
`migration-scaffold-check` remains read-only. A zero-change 2→3 report is
valid for this milestone, but do not install its scaffold.

### Required focused proofs

Add exactly these three tests to the normal `tests` package:

1. `fixture_history_supports_later_schema_versions`
   - parse a strict synthetic v2 manifest;
   - emit and assert `fixture_v0002`, constant `2`, and comment `2`;
   - parse/emit v1 and compare its generated bytes to the accepted v1 package;
   - cover every invalid version spelling/range above;
   - preserve nil allocator, ownership, double-dispose, and OOM behavior.
2. `fixture_schema_diff_supports_contiguous_later_versions`
   - build and deterministically render a synthetic v2→3 report;
   - assert the report versions and expected semantic change;
   - reject frozen/header mismatch, candidate version outside `{2,3}`,
     noncontiguous versions, nil allocator, and OOM without leaks.
3. `fixture_migration_scaffold_supports_later_version_names`
   - render and parse the synthetic v2→3 report;
   - assert import alias/path `fixture_v0002`, all v0002→v0003 constant and
     procedure names, exact versions, and `odinfmt`-identical output;
   - validate the parsed scaffold against the same report.

Reuse existing synthetic manifests, fault allocators, render helpers, and
disposal assertions. Do not add a parallel parser or subprocess-heavy unit
test. Extend existing OOM sweeps so new version parsing/rendering paths remain
covered.

### Required gates

Run:

1. the three named tests as one focused Odin invocation;
2. `make fixture-history-check` with default variables;
3. `make fixture-migration-scaffold-check` with default variables;
4. read-only `migration-diff 2 3` against this repository twice and compare
   exact output;
5. `make fixture-schema-check`;
6. `make fixture-codec-test`;
7. `make fixture-migration-test`;
8. `make check`;
9. `make test`.

The full repository suite must report 510/510 because all three additions live
under `tests`. Confirm the four accepted hashes remain exact. The read-only
2→3 diff must report zero changes against unchanged active schema 2. Remove
all generated binaries and probes. Inspect the isolated `jj diff --git`; only
the allowed tooling, tests, Makefile target area, and this plan may change.

### Acceptance criteria

- strict history parsing and emission support every version 1 through 9999;
- v1 generated source remains byte-identical;
- schema diff validates its actual frozen/candidate header versions;
- CLI and Make defaults still execute the accepted 1→2/v1 workflow;
- variable overrides route future history and contiguous migration paths
  without source edits;
- generic 2→3 diff/scaffold naming is proven without creating v3 artifacts;
- all OOM and disposal guarantees remain intact;
- 510 repository tests and all gates pass with accepted hashes unchanged.

### Verification status — 2026-07-28

M4A is complete. The three required tests pass together with zero leak
diagnostics. Default history and scaffold checks pass; read-only migration-diff
2→3 succeeds twice with byte-identical zero-change reports. Schema check,
codec 2/2, migration 5/5, `make check`, and the full 510-test suite all pass.
The v1 schema, v2 schema, generated v1 history, and 1→2 migration hashes remain
exact. M4A changes stay within the tooling/test/Makefile/plan allowlist; no
schema-v3 artifact or migration scaffold was generated.

### Reviewer verification — M4A blocked

The nine-file delta matches the M4A allowlist, canonical version parsing is
strict, v1 emission remains exact, later diff/scaffold naming is generic, and
the reported tests/gates pass. M4A is nevertheless not accepted because its
first real future-history artifact is invalid Odin.

The frozen v2 manifest contains `dynamic<T>` logical type expressions. The
history validator and reachability walk now accept those expressions, but
`history_emit_type_node` writes the logical spelling directly. A temporary,
repository-external `history-generate 2` produced:

```odin
structures: dynamic<History_Type_0087>,
```

Locked Odin rejects it with:

```text
Syntax Error: Expected a type, got 'dynamic'
```

Odin source syntax is `[dynamic]History_Type_0087`. The new history test uses
the scalar-only synthetic manifest, so its v2 emission assertion cannot catch
this. M4B needs a compilable frozen v2 package and must not begin until the
real manifest path is proven.

## Milestone 4AR — Repair real v2 history emission

### Repair slave handoff

Fix only dynamic-array source emission and close the missing real-manifest
proof. Do not revisit generic version parsing, diff/scaffold behavior, Make
variables, or accepted v1 output.

### Allowed files

- `packages/fixture_schema/history_emit.odin`;
- `tests/fixture_history_test.odin`;
- this plan.

Do not edit the history parser, schema diff, CLI, Makefile, scaffold code/tests,
schema manifests, generated v1 history, codec/migration runtime or script,
serializable state, Editor code, or toolchain lock. Do not create committed
history v2 or schema-v3 artifacts.

### Required repair

In `history_emit_type_node`, retain `dynamic<...>` as the strict logical
manifest grammar, but emit Odin source as:

```odin
[dynamic]<emitted element type>
```

For example, logical
`dynamic<adriatic:packages/terrain.Structure>` must become
`[dynamic]History_Type_0087`. Nested fixed/dynamic array combinations must
retain their exact shape. Do not emit `dynamic<`, add an alias, or weaken type
validation.

Extend `fixture_history_supports_later_schema_versions`; do not add another
test count. In addition to its small synthetic v2 case:

- read and strictly parse `fixtures/schema/v0002.fixture-schema`;
- assert schema version 2 and manifest SHA
  `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- emit it through `history_emit_package`;
- assert package `fixture_v0002`, constant 2, at least one `[dynamic]` field,
  and no `dynamic<` spelling in emitted source;
- retain current nil allocator, OOM sweep, double disposal, and v1
  byte-identity proof.

Do not write the emitted real v2 package inside the test.

### Required external artifact proof

After focused tests, create two temporary roots outside the repository. Copy
only frozen `v0002.fixture-schema` into each expected manifest path, run
`history-generate 2` against both, and prove:

- generated source is byte-identical across roots;
- SHA-256 is identical across roots;
- generated comment pins the accepted v2 manifest SHA;
- locked Odin `check -no-entry-point` compiles each generated
  `fixture_v0002` package;
- no temporary or generated v2 file appears in the repository.

Then run default `make fixture-history-check`, read-only `migration-diff 2 3`
twice, the three M4A focused tests, `make fixture-migration-scaffold-check`,
`make fixture-schema-check`, `make fixture-codec-test`, `make
fixture-migration-test`, `make check`, and `make test`.

Repository suite remains 510/510. All four accepted hashes remain exact. The
isolated repair diff may contain only the two allowed source/test files and
this plan.

### Acceptance criteria

- real frozen v2 history emits valid `[dynamic]T` Odin;
- two independent generated v2 packages are byte-identical and compile;
- v1 generated source remains byte-identical;
- parser, emitter OOM, ownership, and disposal proofs still pass;
- no committed v2/v3 artifact exists;
- 510 tests and every accepted gate/hash pass.

### Verification status — 2026-07-28

M4AR repair is complete. Dynamic manifest types now emit canonical Odin
`[dynamic]T` syntax. The later-version test parses and emits the real v2
manifest, verifies its accepted SHA, and rejects `dynamic<` in generated
source. Two temporary `history-generate 2` roots produce byte-identical,
locked-compiler-valid packages with the accepted v2 SHA comment; no v2 file is
written to the repository. The full M4A gate matrix remains green.

### Reviewer verification — M4A and M4AR accepted

Accepted. The M4AR delta contains only `history_emit.odin`, the existing
later-version history test, and this plan. Logical `dynamic<T>` recursively
emits `[dynamic]T` with no trailing logical delimiter. Real frozen v2 parsing,
accepted manifest SHA, canonical dynamic spelling, and rejection of emitted
`dynamic<` are covered in the normal suite.

Independent verification under locked `dev-2026-07:a6e9c7f2f`:

- two external `history-generate 2` roots emitted byte-identical packages;
- both generated packages have SHA-256
  `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`;
- both generated packages compile;
- repository suite passes 510/510 in 1.323s;
- focused codec passes 2/2 in 17.280s;
- migration passes 5/5 in 2m51.570s;
- default history/scaffold, schema, and `make check` pass;
- no v2 history package, v3 manifest, 2→3 script, binary, or probe exists in
  the repository.

The four accepted hashes remain exact:

- `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`.

## Milestone 4B1 — Freeze schema-v2 history

### Next slave handoff

Generate and commit the immutable schema-v2 historical Odin package before any
fixture-reachable source changes. This milestone adds the artifact only. Do
not begin occupancy, schema 3, migration 2→3, registry chaining, or Editor
lifecycle work.

### Allowed files

- add `packages/fixture_history/v0002/schema.generated.odin`;
- update this plan.

Do not edit the v1 history package, either schema manifest, history
parser/emitter/diff/scaffold/CLI, Makefile, tests, codec/migration
runtime/script, serializable state, Editor code, toolchain lock, or
`zelda-engine`.

### Generation contract

Run:

```text
make fixture-history-generate FIXTURE_HISTORY_VERSION=2
```

The generated package must come only from frozen
`fixtures/schema/v0002.fixture-schema`. Do not copy the temporary reviewer
artifact or hand-edit generated source.

Expected immutable facts:

- package: `fixture_v0002`;
- `FIXTURE_SCHEMA_VERSION :: 2`;
- manifest SHA comment:
  `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- generated source SHA-256:
  `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`;
- 1,816 lines;
- 149 `fixture-history-id` records;
- root `Fixture` present;
- dynamic fields use `[dynamic]T`;
- no `dynamic<T>` source spelling.

Run generation twice. The second run must leave exact bytes and SHA unchanged.
Then use:

```text
make fixture-history-check FIXTURE_HISTORY_VERSION=2
```

That target must compile the selected `v0002` package through the generalized
Make path. Also run the default v1 history check to prove its route remains
unchanged.

### Required gates

Run:

1. v2 history generation twice;
2. v2 history check;
3. default v1 history check;
4. read-only `migration-diff 2 3` twice with exact zero-change output;
5. `make fixture-migration-scaffold-check`;
6. `make fixture-schema-check`;
7. `make fixture-codec-test`;
8. `make fixture-migration-test`;
9. `make check`;
10. `make test`.

Repository suite remains 510/510. Confirm the prior four hashes plus the new
v2 history hash exactly. Inspect isolated `jj diff --git`: only the generated
v2 package and this plan may change. Remove binaries and probes.

### Acceptance criteria

- committed v2 history is generator-derived, deterministic, and compiler-valid;
- source hash is exactly
  `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`;
- both v1 and v2 history checks pass through parameterized Make targets;
- active source and schema remain version 2;
- no schema-v3 or migration-2→3 artifact exists;
- 510 tests and every accepted gate/hash pass.

### Verification status — 2026-07-28

M4B1 is complete. Generated schema-v2 history twice through the parameterized
Make target; the artifact is 1,816 lines with 149 records and SHA
`8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`.
Both v2 and default v1 history checks compile successfully. The read-only 2→3
diff is byte-identical and zero-change twice. Scaffold/schema checks, codec 2/2,
migration 5/5, `make check`, and the full 510-test suite pass. No schema-v3 or
2→3 migration artifact was generated.

### Reviewer verification — M4B1 accepted

Accepted. The isolated M4B1 delta from pre-milestone commit
`66c753c23cf474c495c3d4259ef29d00d53b15da` contains only this plan and the
generated `packages/fixture_history/v0002/schema.generated.odin` artifact.
The artifact has package `fixture_v0002`, schema constant 2, the accepted v2
manifest SHA comment, 1,816 lines, 149 history records, root `Fixture`,
canonical `[dynamic]T` source, and no `dynamic<T>` source spelling.

Independent verification under locked `dev-2026-07:a6e9c7f2f`:

- v1 and v2 history packages compile through the parameterized Make target;
- scaffold/schema checks and `make check` pass;
- repository suite passes 510/510 in 1.992s;
- focused codec passes 2/2 in 19.330s;
- migration passes 5/5 in 3m00.880s;
- no schema-v3 or 2→3 migration artifact exists.

The five immutable hashes are now:

- schema v1:
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- schema v2:
  `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- generated history v1:
  `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- generated history v2:
  `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`;
- migration v1→v2:
  `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`.

## Milestone 4B2A — Expose truthful multi-step execution context

### Next slave handoff

Repair only the runtime step boundary before adding a second production
migration. Every wrapper currently receives the original source payload, but
the wrapper ABI does not say that. In a future v1→2→3 run, the second wrapper
would therefore be labeled v2→3 while receiving v1 bytes. Existing fake
two-step tests ignore the payload and cannot catch that mistake.

Make the original source version, final target version, and current step
identity explicit. Do not manufacture intermediate payloads and do not add
occupancy yet. This milestone exposes the truth needed for the next wrapper;
it deliberately does not solve general projection between arbitrary
historical schemas.

### Allowed files

- `src/fixture_migration.odin`;
- `src/fixture_migration_runtime.odin`;
- `src/fixture_migration_test.odin`;
- this plan.

Do not edit either schema manifest, either generated history package,
fixture-reachable state, the 1→2 migration script, codec, schema/history/diff/
scaffold tooling, Makefile, Editor lifecycle code, tests outside the one
allowed migration test file, toolchain lock, or `zelda-engine`. Do not create
schema-v3, migration-2→3, occupancy, generated binary, or probe artifacts.

### Runtime boundary

Add one plain context type beside `Fixture_Migration_Step_Proc`:

```odin
Fixture_Migration_Step_Context :: struct {
    source_payload:       []byte,
    source_version:       int,
    target_version:       int,
    step_from_version:    int,
    step_to_version:      int,
    tentative:            ^Fixture,
    transaction_allocator: mem.Allocator,
}
```

Formatting/alignment may follow `odinfmt`; field meaning may not change.
`source_payload` is the borrowed, unmodified payload supplied to
`fixture_migration_run_with_registry`. `source_version` is its container
schema version. `target_version` is the final requested version, not the
current step target. The two step versions come from the validated registry
entry. `tentative` and `transaction_allocator` retain their current ownership
and lifetime.

Change `Fixture_Migration_Step_Proc` to accept only a pointer to this context
and return the existing error:

```odin
Fixture_Migration_Step_Proc :: #type proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error
```

The context pointer and its borrowed fields are valid only for the call.
Wrappers must not retain the context, payload, fixture pointer, or allocator.
Odin has no deep-const slice here, so enforce non-mutation with tests and keep
the contract explicit. Do not add an ownership flag, intermediate byte
buffer, callback, interface, or second wrapper ABI.

After registry validation and tentative decode, construct one fresh stack
context per selected step. Populate every field from the original call and
the validated step. Call the wrapper with that context. Preserve the existing
error normalization, atomic arena disposal, result ownership, and zero-step
behavior exactly.

Adapt `fixture_migration_step_v0001_to_v0002` to the context ABI. It must
validate:

- non-nil context and tentative fixture;
- original source version equals 1;
- step identity is exactly 1→2;
- final target is at least the step target;
- allocator is the transaction dynamic-arena allocator with a valid backing
  allocator.

It must decode `source_payload` as historical v1 exactly as before and invoke
the immutable 1→2 scripted migration. Do not change migration results,
allocation topology, error categories, or the frozen script.

### Required tests

Extend existing tests; do not add a sixth focused migration test or increase
the 510-test repository count.

In `fixture_migration_transaction_paths_and_ownership`, make typed fake
wrappers assert the full context:

1. direct v1→2 sees source 1, final target 2, step 1→2, the exact borrowed
   source payload, the transaction allocator, and the tentative fixture;
2. fake v1→2→3 sees source 1 and final target 3 in both calls, while step
   identity advances from 1→2 to 2→3;
3. the second fake step sees the first step's tentative mutation but still
   sees the original v1 payload and source version 1;
4. fake direct v2→3 selects only step 2 and sees source 2, final target 3,
   and step 2→3;
5. zero-step current-version decode invokes no wrapper;
6. success and mutate-then-fail paths leave an exact caller-owned payload
   snapshot unchanged.

Keep the existing 64 MiB-per-step transaction-arena reuse proof, ordered
mutation result, atomic failure, result/error double disposal, unsupported
route checks, and zero outstanding allocations.

Adapt the invalid-history wrapper and every other fake wrapper in the allowed
test file to the new ABI. Extend
`fixture_migration_rejects_invalid_registries_before_decode` only as needed to
prove malformed registries still invoke no wrapper. Preserve the complete
caller-allocation OOM sweep; no new allocation may be introduced before
registry validation, and context construction itself must allocate zero
times.

### Required gates

Run:

1. the three runtime-focused tests named by
   `make fixture-migration-test` as one locked-Odin invocation while
   iterating;
2. `make fixture-migration-test` — all five tests pass with zero leaks;
3. `make fixture-codec-test` — 2/2;
4. `make fixture-history-check`;
5. `make fixture-history-check FIXTURE_HISTORY_VERSION=2`;
6. `make fixture-migration-scaffold-check`;
7. `make fixture-schema-check`;
8. `make check`;
9. `make test` — exactly 510/510.

Run the focused migration target three consecutive times because this changes
the production wrapper ABI and arena call boundary. Confirm all five immutable
hashes exactly. Inspect the isolated `jj diff --git`; only the three allowed
Odin files and this plan may change. Remove binaries and probes.

### Acceptance criteria

- wrapper ABI states whether its payload is truly the wrapper's source schema;
- direct and chained wrappers receive exact original/final/step versions;
- the fake second step cannot mistake original v1 bytes for v2 bytes;
- ordered tentative mutation and one-arena transaction semantics remain
  unchanged;
- production v1→2 behavior, errors, allocations, and frozen script stay exact;
- payload bytes remain caller-owned and unchanged on every path;
- registry rejection, OOM, atomicity, disposal, and leak proofs remain green;
- active schema remains 2 with no occupancy or 2→3 artifacts;
- 510/510 and every accepted gate/hash pass.

### Verification status — 2026-07-28

M4B2A is complete. Migration wrappers now receive an explicit stack context
containing the borrowed original payload, original/final versions, step
identity, tentative fixture, and transaction allocator. The production 1→2
wrapper validates that context; typed fakes prove direct v1→2, chained
v1→2→3, and direct v2→3 behavior, including exact payload preservation and
zero-step dispatch. The focused migration tests pass 3/3, and the five-test
migration target passes three consecutive runs with zero leaks. All required
history, scaffold, schema, codec, check, and 510-test gates pass; immutable
hashes remain exact and no schema-v3 or 2→3 artifact exists.

### Reviewer verification — M4B2A accepted

Accepted. The isolated delta from the pre-M4B2A evolution of change
`mwytpkmk` at Jujutsu operation `299faf0163dc` contains exactly the three
allowed Odin files and this plan. Runtime constructs a fresh stack context
per validated step and assigns the original payload slice directly. Wrappers
receive original/final/step versions, the shared tentative fixture, and the
transaction allocator. Production 1→2 rejects forged metadata and preserves
its historical decode and immutable script path.

Typed tests prove direct v1→2, fake v1→2→3, direct v2→3, zero-step dispatch,
ordered shared-tentative mutation, caller-byte preservation, arena reuse,
atomic failure, invalid-registry rejection, and the complete caller-allocation
OOM sweep. Exact slice borrowing is visible in the direct runtime assignment;
input snapshots prove wrappers leave the borrowed bytes unchanged.

Independent verification under locked `dev-2026-07:a6e9c7f2f`:

- runtime-focused trio passes 3/3 in 9.642s;
- full migration matrix passes 5/5 in 3m03.174s with zero leaks;
- v1 and v2 history, scaffold, schema, and `make check` gates pass;
- repository suite passes 510/510 in 1.322s;
- all five immutable hashes remain exact;
- no schema-v3 or migration-2→3 artifact exists.

## Milestone 4B2B1 — Lock occupant identity contract

### Next slave handoff

Define and prove the stable five-state occupant identity before adding it to
`Fixture`. This milestone is deliberately schema-invisible. Do not change the
schema version, root fixture, codec, migrations, or pointer rebinding.

Live state cannot be derived from `pilot.mode` or `aircraft.active` alone.
`Libellula` and `Libellula_Mk2` intentionally share
`editor.libellula.vehicle`; their selected `Aircraft_Kind` disambiguates that
one pointer only while the pilot is driving it. On-foot and car states must
never be guessed from active aircraft selection.

### Allowed files

- `packages/vehicles/occupancy.odin`;
- `tests/vehicle_occupancy_test.odin`;
- this plan.

Do not edit `src/main.odin`, `Fixture`, either schema manifest, either history
package, migration types/runtime/scripts/tests, codec, fleet representation,
Makefile, toolchain lock, Editor lifecycle code, or `zelda-engine`. Do not
create schema-v3, migration-2→3, generated binary, or probe artifacts.

### Stable data contract

Add this explicit product-local enum in `packages/vehicles/occupancy.odin`:

```odin
Fixture_Occupant :: enum u8 {
    On_Foot       = 0,
    Car           = 1,
    Postale       = 2,
    Libellula     = 3,
    Libellula_Mk2 = 4,
}
```

Keep the explicit integer values. Zero must mean `.On_Foot`; there is no
`.Unknown` or `.Invalid` serialized state. Failure is reported separately and
callers must not use the zero result when derivation fails. Do not reuse or
extend `Occupancy_Mode` or `Aircraft_Kind`: neither can represent the required
cross-product.

Add one allocation-free, mutation-free procedure:

```odin
fixture_occupant_derive :: proc(
    character: ^Character,
    car, postale, libellula: ^Vehicle,
    active_aircraft: Aircraft_Kind,
) -> (Fixture_Occupant, bool)
```

Require non-nil character and canonical vehicle pointers. Require `car`,
`postale`, and `libellula` to be pairwise distinct. Inspect only
`Character.mode`, `Character.vehicle`, the three reciprocal `Vehicle.driver`
pointers, and `active_aircraft`. Reject an `active_aircraft` discriminant
outside `.Postale`, `.Libellula`, and `.Libellula_Mk2` before deriving any
state.

Valid graphs:

- `.On_Foot`: character mode is `.On_Foot`, `character.vehicle` is nil, and
  all three drivers are nil;
- `.Car`: character mode is `.Driving`, character vehicle is `car`,
  `car.driver == character`, and both aircraft drivers are nil;
- `.Postale`: driving `postale`, reciprocal driver is exact, other drivers are
  nil, and active aircraft is `.Postale`;
- `.Libellula`: driving the shared Libellula vehicle, reciprocal driver is
  exact, other drivers are nil, and active aircraft is `.Libellula`;
- `.Libellula_Mk2`: same shared vehicle and links, but active aircraft is
  `.Libellula_Mk2`.

Everything else returns `{}` and `false`: forged occupancy mode, nil or
unknown character vehicle, missing or foreign reciprocal driver, extra driver
on another vehicle, on-foot state retaining any link, driving mode without a
vehicle, Postale with mismatched active aircraft, shared Libellula vehicle
with `.Postale` active, or duplicate canonical vehicle addresses.

Do not inspect positions, yaw, lock state, fleet availability, slot names, or
slot pointer wiring here. Those are independent state or later rebind
validation. Do not repair, clear, or normalize invalid links.

### Required test

Add one test to the existing `tests/vehicle_occupancy_test.odin`:

```text
fixture_occupant_derivation_covers_all_kinds_and_rejects_bad_links
```

Keep existing three tests unchanged. In one deterministic table/matrix:

1. prove exact enum integer values 0 through 4;
2. prove valid on-foot, car, Postale, Libellula, and Libellula Mk2 results;
3. prove Libellula and Mk2 use the same vehicle pointer and differ only by
   active aircraft;
4. prove active aircraft selection does not change valid on-foot or car
   results;
5. cover every invalid family listed above, including nil inputs, pairwise
   duplicate canonical pointers, a foreign `Character`, an unknown `Vehicle`,
   forged enum discriminants, and multiple reciprocal drivers;
6. snapshot character and all vehicles around every valid and hostile call
   and assert field-for-field equality afterward.

Reuse stack values. Do not use heap allocation, random inputs, fixtures,
serialization, or a second test. The procedure has no allocator and must not
touch `context`.

### Required gates

Run:

1. the new named test alone under locked Odin;
2. all four tests in `tests/vehicle_occupancy_test.odin` together;
3. `make test` — exactly 511/511;
4. `make check`;
5. `make fixture-schema-check`;
6. read-only `migration-diff 2 3` twice — still byte-identical zero-change;
7. `make fixture-history-check`;
8. `make fixture-history-check FIXTURE_HISTORY_VERSION=2`;
9. `make fixture-migration-scaffold-check`;
10. `make fixture-codec-test`;
11. `make fixture-migration-test`.

Confirm all five immutable hashes exactly. Inspect isolated `jj diff --git`:
only the two allowed Odin files and this plan may change. `FIXTURE_SCHEMA_VERSION`
remains 2, generated current schema remains byte-identical to frozen v2, and
the new enum remains unreachable from the fixture walker. Remove binaries and
probes.

### Acceptance criteria

- five occupant identities have explicit stable u8 values;
- derivation is deterministic, allocation-free, and mutation-free;
- every valid pointer graph maps to exactly one identity;
- shared Libellula/Mk2 pointer is disambiguated only when occupied;
- on-foot and car identity ignore aircraft selection;
- contradictory, aliased, missing, foreign, and forged links fail closed;
- active fixture schema remains byte-identical v2;
- 511/511 and every accepted gate/hash pass.

### Verification status — 2026-07-29

M4B2B1 is complete. `Fixture_Occupant` is an explicit `u8` enum with stable
values 0 through 4, and `fixture_occupant_derive` is allocation-free,
mutation-free, and fail-closed for forged modes, invalid aircraft kinds,
aliased canonical vehicles, foreign/missing/extra reciprocal links, and
ambiguous occupancy. The shared Libellula pointer is disambiguated only by
active aircraft selection while occupied; on-foot and car results ignore that
selection. The new matrix test passes alone and with all four occupancy tests;
the full suite reports 511/511. All schema/history/scaffold/codec/migration/
check gates pass, the 2→3 diff remains byte-identical zero-change, and no
schema-v3 or 2→3 artifact was created.

### Reviewer verification — M4B2B1 proof repair required

Production code and scope are correct. The isolated delta from the
pre-M4B2B1 evolution of change `mwytpkmk` at Jujutsu operation
`f4fb09528eba` contains only `occupancy.odin`, its existing test file, and this
plan. Enum values are exact. Derivation rejects nil/aliased roots, forged enum
values, unknown vehicles, link/mode contradictions, extra or foreign drivers,
and mismatched aircraft identity without allocation or mutation.

Independent locked-Odin proof passes:

- named occupant matrix: 1/1 in 102µs;
- repository suite: 511/511 in 1.505s;
- `make check`, schema, v1/v2 history, and scaffold gates;
- all five immutable hashes.

M4B2B1 is not yet accepted because the promised hostile matrix skips:

1. the third pairwise alias permutation, `car == libellula`;
2. driving a known canonical vehicle with its reciprocal `driver` nil;
3. mutation snapshot coverage for the external `unknown` vehicle used by the
   unknown-pointer case.

The implementation already fails the first two cases correctly. This is a
test-proof repair only. Do not begin B2B2.

## Milestone 4B2B1R — Complete hostile derivation proof

### Repair slave handoff

Change only:

- `tests/vehicle_occupancy_test.odin`;
- this plan.

Do not edit `packages/vehicles/occupancy.odin` or any other production/test
file. Do not change enum values, procedure signature/logic, fixture state,
schema, codec, migrations, Makefile, toolchain, or generated artifacts.

Extend only
`fixture_occupant_derivation_covers_all_kinds_and_rejects_bad_links`:

1. Beside the existing `car == postale` and `postale == libellula` calls, add
   `car == libellula` and require `ok == false`.
2. Build a driving-car graph where `character.vehicle == &car`, all three
   vehicle drivers are nil, and require failure. Keep this distinct from the
   existing driving-with-nil-vehicle and foreign-driver cases.
3. Snapshot `unknown` before the unknown-character-vehicle call and assert it
   remains field-for-field equal afterward. Keep the existing canonical
   character/vehicle snapshots in `fixture_occupancy_test_expect`.

Do not add a test, helper abstraction, allocation, random case generator, or
production workaround. Test count remains 511.

Run the repaired named test alone, all four occupancy tests together,
`make test`, `make check`, schema check, read-only zero-change 2→3 diff twice,
v1/v2 history checks, scaffold check, codec 2/2, and migration 5/5. Confirm
all five hashes and absence of v3/2→3 artifacts. Isolated `jj diff --git` for
the repair may contain only the allowed test file and this plan.

### Acceptance criteria

- all three canonical alias pairs are tested;
- missing reciprocal driver is tested separately from nil/foreign links;
- unknown external vehicle is proven unchanged;
- production derivation remains byte-identical;
- 511/511 and every accepted gate/hash pass;
- schema remains exact v2 with no v3 artifact.

### Verification status — 2026-07-29

M4B2B1R is complete. The hostile matrix now covers `car == libellula`, a
known car with a missing reciprocal driver, and an unknown vehicle snapshot
that remains field-for-field unchanged. The repaired named test passes alone
and with all four occupancy tests. Sequential schema, history v1/v2,
scaffold, codec 2/2, migration 5/5, `make check`, and 511-test gates pass;
the read-only 2→3 diff remains byte-identical zero-change twice. Production
occupancy code, hashes, and schema-v2 artifacts remain unchanged.

### Reviewer verification — M4B2B1 and M4B2B1R accepted

Accepted. The repair delta from the pre-repair evolution of change
`mwytpkmk` at Jujutsu operation `aabd9ea4da3f` contains only the existing
occupancy test and this plan. It adds exactly the third canonical alias,
missing reciprocal driver, and unknown-vehicle snapshot assertions.
`packages/vehicles/occupancy.odin` remains byte-identical with SHA-256
`5a4aaa44103f3a829e61bdfa2c5da9aadd2f11feffd4c06c68f984a51828268a`.

Independent locked-Odin verification:

- occupancy quartet passes 4/4 in 244µs;
- repository suite passes 511/511 in 1.554s;
- `make check`, schema, v1/v2 history, and scaffold gates pass;
- five immutable schema/history/migration hashes remain exact;
- no schema-v3 or migration-2→3 artifact exists.

### Newly exposed phase-boundary requirement

Do not add the occupant field yet. Both `migration-diff` and
`migration_scaffold_report` currently compare the requested frozen source
manifest with the live source candidate. Once a schema-v3 draft field is
added while `FIXTURE_SCHEMA_VERSION` remains 2, an accepted 1→2 check would
wrongly treat that field as part of migration 1→2 and invalidate the frozen
script.

Accepted transitions must compare immutable source and target manifests when
the target manifest exists. Only a not-yet-frozen target may use the live
candidate. Fix and prove this routing before B2B2B.

## Milestone 4B2B2A — Pin accepted migration target manifests

### Next slave handoff

Change migration report input selection only. Preserve every diff, scaffold,
schema, codec, and migration semantic result. Source schema stays exact v2,
and the 2→3 report stays zero-change.

### Allowed files

- `tools/fixture_schema/main.odin`;
- add `tools/fixture_schema/main_test.odin`;
- `tests/fixture_schema_diff_test.odin`;
- `tests/fixture_migration_scaffold_test.odin`;
- this plan.

Do not edit `packages/fixture_schema`, Makefile, `src/main.odin`, Fixture or
occupancy production code, either schema manifest, either history package,
migration runtime/scripts/tests, codec, toolchain, or `zelda-engine`. Do not
create a v3 manifest, 2→3 scaffold, binary, or repository probe.

### Shared candidate routing

In the CLI tool, add one small owned-data helper used by both
`migration-diff` and `migration_scaffold_report`. Keep naming simple; suggested
contract:

```odin
migration_candidate_data :: proc(
    repo_root, collection_root: string,
    from_version, to_version: int,
) -> ([]byte, bool)
```

Returned successful bytes are caller-owned through `context.allocator`; both
callers must delete them exactly once. Failure returns nil/false.

Routing:

1. Resolve `fixtures/schema/vNNNN.fixture-schema` for `to_version`.
2. If that target manifest exists, read and return its exact bytes. Do not
   walk live source. If it exists but is unreadable, fail; never fall back.
3. If the target manifest does not exist, build the live candidate through
   `build_manifest_report`.
4. A live candidate version must equal `from_version` or `to_version`, using
   the existing strict endpoint diagnostic. Any other version fails.
5. Leave strict manifest parsing, endpoint/header validation, semantic diff,
   report ownership, and error disposal in
   `schema_diff_build_report`; do not add another parser.

Use the helper in both command paths. Remove the duplicated live-walk code and
keep existing user-facing operation prefixes. Do not cache bytes, mutate a
manifest, infer paths by directory scan, or add a fallback candidate.

This yields:

- 1→2: frozen v1 versus frozen v2, immune to later live drafts;
- 2→3 before v3 exists: frozen v2 versus live source;
- 2→3 after v3 exists: frozen v2 versus frozen v3.

### Focused tool regression

Add one `when ODIN_TEST` test in the tool package:

```text
migration_candidate_prefers_frozen_target_and_live_draft
```

Build a minimal temporary repository outside the working tree:

1. generate/store a valid schema-v1 manifest from a tiny Fixture;
2. generate/store schema v2 after one target field addition;
3. leave no v3 manifest;
4. change live source, still version 2, by adding a distinct draft field;
5. prove 1→2 candidate bytes are exact stored v2 bytes and its report contains
   only the target field;
6. prove 2→3 candidate bytes come from live source and its report contains
   only the draft field.

Use the production helper and strict report builder. Assert exact endpoints,
one state change per report, expected stable field-add IDs, correct
script-required policy, deterministic render, and disposal. Clean the exact
temporary root on every exit. First probe uncertain Odin temp-directory/file
APIs in a minimal external scratch program, then remove the probe.

Also prove an existing but malformed/unreadable target does not silently use
live source. If portable permission denial is unreliable, malformed readable
bytes are sufficient because strict report construction must fail without a
live fallback.

Do not spawn the CLI, copy full repository manifests, add random cases, or
write inside the repository.

### Freeze existing production tests

In `fixture_schema_diff_production_is_exact_and_round_trips`, read frozen v1
and frozen v2 manifests. Stop using the live walker as the 1→2 candidate.
Keep exact 21/16/5 changes, render bytes, metrics, policies, and both accepted
SHAs unchanged.

In `migration_scaffold_production_report`, likewise read frozen v1 and frozen
v2. Keep the exact 16 obligations, import/ABI, parser/renderer/validator,
OOM/disposal, and installed 1→2 script expectations unchanged. Do not alter
the synthetic later-version test yet.

### Required gates

Run:

1. the new tool-package test alone under locked Odin;
2. full tool-package tests if more than one is discovered;
3. read-only `migration-diff 1 2` twice — byte-identical accepted report,
   exactly 21/16/5 and 6,873 bytes;
4. read-only `migration-diff 2 3` twice — byte-identical zero-change;
5. default `make fixture-migration-scaffold-check`;
6. `make fixture-migration-scaffold` — report existing 1→2 source without
   rewriting its hash;
7. `make fixture-schema-check`;
8. v1 and v2 history checks;
9. `make fixture-codec-test`;
10. `make fixture-migration-test`;
11. `make check`;
12. `make test` — exactly 511/511.

Confirm all five immutable hashes plus occupant production SHA exactly.
Inspect isolated `jj diff --git`: only the four allowed Odin paths (including
the added tool test) and this plan may change. Remove temp roots, binaries,
and probes.

### Acceptance criteria

- existing target manifest always wins over live source;
- missing target manifest uses only a valid live endpoint candidate;
- unreadable/malformed existing target never falls back;
- accepted 1→2 diff/scaffold bytes and hashes stay exact;
- pre-v3 2→3 path still observes live source;
- ownership, parse failure, determinism, and disposal remain clean;
- schema remains byte-identical v2 with no 2→3 artifact;
- 511/511 and every accepted gate/hash pass.

### Verification status — 2026-07-29

M4B2B2A is complete. The CLI and scaffold report now use an owned candidate
router: an existing target manifest is read verbatim, while a missing target
uses only a live candidate at an accepted endpoint. Malformed existing target
bytes are returned to strict report validation and never fall back to live
source. Production 1→2 tests read frozen v1/v2 manifests.

The focused tool regression and full tool package each pass 1/1 with zero leak
diagnostics. Repeated read-only diffs are deterministic: 1→2 is exactly 6,873
bytes with 21 changes (16 state, 5 supporting), and 2→3 is exactly 373 bytes
with zero changes. Scaffold check and no-overwrite generation pass with the
accepted migration SHA unchanged. Schema, v1/v2 history checks, codec 2/2,
migration 5/5, `make check`, and the full suite 511/511 pass with zero leak
diagnostics. Immutable hashes remain exact:

- v1 manifest `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- v2 manifest `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- v1 history `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- v2 history `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`;
- 1→2 migration `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`;
- occupancy production `5a4aaa44103f3a829e61bdfa2c5da9aadd2f11feffd4c06c68f984a51828268a`.

No v3 manifest or 2→3 migration artifact exists. The isolated change scope
contains only the four allowed Odin paths and this plan.

### Reviewer verification — M4B2B2A accepted

Accepted. The isolated delta from change `mwytpkmk` evolution `d3989b79`
contains only the four allowed Odin paths and this plan. Both CLI paths call
the same owned candidate router. `os.exists` selects exact target-manifest
bytes; a read failure returns failure, and only an absent path invokes the live
walker. The focused malformed-manifest case proves strict parsing fails on the
frozen bytes rather than silently substituting the valid live source.

Independent locked-Odin verification:

- tool package passes 1/1 in 6.821ms with memory tracking clean;
- `make check test` passes, including exactly 511/511 tests in 1.613s;
- repeated 1→2 reports are byte-identical at 6,873 bytes and retain exact
  21/16/5 counters and accepted hashes;
- repeated 2→3 reports are byte-identical at 373 bytes with zero changes;
- schema, scaffold, and both history checks pass;
- five immutable hashes and occupancy production SHA remain exact;
- no v3 manifest or 2→3 migration source exists.

## Milestone 4B2B2B — Draft schema-v3 occupancy change

### Next slave handoff

Add one serialized relationship discriminator to the live Fixture graph and
generate its unresolved 2→3 scaffold. This is a draft boundary only: source
still declares schema version 2, frozen v2 stays immutable, and no migration
step is executable or registered yet.

### Allowed files

- `src/main.odin`;
- add generated `src/fixture_migration_v0002_to_v0003.odin`;
- `tests/fixture_schema_diff_test.odin`;
- `tests/fixture_migration_scaffold_test.odin`;
- this plan.

Do not edit `packages/vehicles`: the accepted enum and derivation stay
byte-identical. Do not edit the schema tool, schema package, Makefile, codec,
migration runtime/registry, existing 1→2 migration or tests, either frozen
manifest, either history package, fixture-file container, editor lifecycle,
hot reload, or `zelda-engine`. Do not create a v3 manifest/history package.

### Fixture draft

In `Fixture` in `src/main.odin`, immediately before `pilot`, add exactly:

```odin
occupant: vehicles.Fixture_Occupant,
```

No `fixture:"-"` tag, default initializer, shadow field, pointer, conversion,
or runtime assignment. Keep `FIXTURE_SCHEMA_VERSION :: 2`. The zero value is
already the stable `.On_Foot = 0` wire value, but B2B2B must not claim or
execute migration policy.

Do not call `vehicles.fixture_occupant_derive` from save, load, update, or hot
reload yet. That derivation becomes save-side policy only after schema 3 is
activated and lifecycle binding has a shared contract.

### Exact draft report

After adding the field, run read-only `migration-diff 1 2` twice. Frozen target
routing must preserve byte-identical accepted output: 6,873 bytes, 21 changes,
16 state, 5 supporting, and the existing v1/v2 hashes.

Run read-only `migration-diff 2 3` twice. It must use frozen v2 as source and
live schema-version-2 source as the missing-v3 candidate. Output must be
byte-identical and contain exactly two changes:

- `field-add:adriatic:src.Fixture.occupant` —
  `state/script_required`;
- `type-add:adriatic:packages/vehicles.Fixture_Occupant` —
  `supporting/automatic`.

Assert report endpoints 2→3, candidate root field count increases by one, and
candidate record count increases by one. Record exact rendered byte count,
candidate line/root/record metrics, and draft candidate SHA in verification
evidence. This candidate SHA is diagnostic only; do not freeze it as schema v3
yet.

No other field/type/order/enum change is allowed. `Fixture_Occupant` must
retain base `u8` and exact values `.On_Foot=0`, `.Car=1`, `.Postale=2`,
`.Libellula=3`, `.Libellula_Mk2=4`.

### Generate unresolved scaffold

Generate only through the production CLI:

```text
make FIXTURE_MIGRATION_FROM_VERSION=2 FIXTURE_MIGRATION_TO_VERSION=3 fixture-migration-scaffold
```

Do not hand-author or hand-format the new source. Run the same command again;
it must validate the existing file and leave its SHA byte-identical. Then run
the matching explicit scaffold-check target.

Generated source must:

- be package `main`;
- import immutable `fixture_history/v0002` as `fixture_v0002`;
- declare exact endpoints 2 and 3;
- contain one resolution, for the occupant field-add ID;
- mark that resolution `.Unresolved`;
- contain no entry for the automatic supporting enum type-add;
- expose the generated `#by_ptr fixture_v0002.Fixture` ABI;
- return `.Unresolved` without mutating `tentative`;
- compile and be `odinfmt`-identical.

Do not resolve the obligation, add vehicle imports, add `.On_Foot` policy, or
register a wrapper. Those belong to B2B3/B2B4. Record unresolved scaffold SHA
as B2B3 input evidence.

### Focused schema-diff proof

Add one test:

```text
fixture_schema_diff_v0002_to_live_occupancy_draft_is_exact
```

Use the real repository. Read frozen v2 bytes, build the live candidate through
`build_manifest_report`, and require the live source version remains 2 with
empty diagnostics. Build a strict report with requested endpoints 2→3.

Assert:

- exact two IDs, no missing or extra entry;
- one state/script-required and one supporting/automatic change;
- exact field type is
  `adriatic:packages/vehicles.Fixture_Occupant`;
- enum detail pins `u8` and all five names/values;
- frozen SHA remains the accepted v2 SHA;
- candidate root/record counts each increase by exactly one;
- render twice is byte-identical;
- parse/render round-trip is byte-identical;
- every report/error/buffer is disposed with zero leaks.

Keep the accepted frozen v1→v2 production test unchanged. Do not weaken it to
use live source.

### Focused scaffold proof

Add one test:

```text
fixture_migration_scaffold_v0002_to_v0003_draft_is_exact
```

Build the same real frozen-v2/live report, read the generated 2→3 source,
parse it, validate it against the report, and render the report again. Pin:

- endpoint constants 2→3;
- exact `fixture_v0002` import and `#by_ptr` historical ABI;
- exactly one resolution with occupant field-add ID and `.Unresolved`;
- no supporting-type resolution;
- generated source equals renderer output byte-for-byte;
- parse and validation diagnostics are empty;
- idempotent disposal and zero leaks.

Do not spawn the CLI from tests, duplicate renderer logic, copy manifests, add
random cases, or add another OOM sweep. Existing generalized parser/renderer
hardening already owns those concerns.

### Expected draft failure

`fixtures/schema/v0002.fixture-schema` must not be regenerated. Therefore
`make fixture-schema-check` and existing
`fixture_schema_production_graph_matches_draft` must report the one intentional
frozen-v2 mismatch. This is the only accepted red gate.

With two new focused tests, full suite expectation is exactly 512/513: both new
tests pass, only `fixture_schema_production_graph_matches_draft` fails, and
memory tracking reports zero leaks. Any second failure blocks handoff.

Never run `fixture-schema-generate` during B2B2B. A generated v2 manifest here
would destroy historical truth. Dramatic little foot-gun.

### Required gates

Run in this order:

1. new schema-diff test alone under locked Odin;
2. new scaffold test alone under locked Odin;
3. both focused tests together twice;
4. read-only 1→2 diff twice — exact 6,873 bytes and 21/16/5;
5. read-only 2→3 diff twice — exact two changes and stable bytes;
6. explicit 2→3 scaffold generation twice, then scaffold check;
7. default 1→2 scaffold check and no-overwrite generation;
8. v1 and v2 history checks;
9. `make fixture-codec-test` — 2/2;
10. `make fixture-migration-test` — 5/5;
11. `make check`;
12. `make test` — exactly 512/513, only known schema-draft mismatch;
13. `make fixture-schema-check` — fail only on same expected mismatch.

Confirm existing five immutable hashes plus occupancy production SHA exactly:

- v1 manifest `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- v2 manifest `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- v1 history `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- v2 history `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`;
- 1→2 migration `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`;
- occupancy production `5a4aaa44103f3a829e61bdfa2c5da9aadd2f11feffd4c06c68f984a51828268a`.

Inspect isolated `jj diff --git`: only four allowed Odin paths and this plan.
Remove binaries/probes/temp roots. Only new repository artifact may be the
generated unresolved 2→3 migration source.

### Acceptance criteria

- Fixture has exactly one serialized occupant discriminator;
- source version stays 2 and frozen v2 remains byte-identical;
- 1→2 report/scaffold remains immutable;
- 2→3 report contains exact state field-add plus supporting enum type-add;
- generated 2→3 scaffold contains exactly one unresolved obligation;
- no migration policy, wrapper, registry, codec, or lifecycle behavior changes;
- both focused proofs pass deterministically with zero leaks;
- all unrelated gates remain green;
- exactly one known schema-draft mismatch remains;
- existing hashes stay exact and no v3 manifest/history artifact exists.

### Verification status — 2026-07-29

M4B2B2B is complete. `Fixture` now has exactly one serialized
`vehicles.Fixture_Occupant` field immediately before `pilot`; source schema
version remains 2, no derivation or migration policy was added, and frozen v2
was not regenerated.

The frozen 1→2 report remains deterministic at 6,873 bytes with 21 changes
(16 state, 5 supporting). The live 2→3 draft report is deterministic at 1,236
bytes with exactly two changes: occupant field-add/state/script-required and
`Fixture_Occupant` type-add/supporting/automatic. Candidate metrics are 1,378
lines, 150 records, and 146 root fields; candidate SHA is
`339574b5e063bbf127c05ec5418117cade82e941587ffd5551d342e32641bb3e`.

The generated unresolved 2→3 scaffold is byte-stable across repeated CLI
generation and explicit scaffold-check, with SHA
`2953cd64cba6e7c5675ac0cf3336c5f895ef17ee5955fa9b87741d138ab5e5a0`. It has
one unresolved occupant resolution, no supporting enum resolution, the
`fixture_v0002` `#by_ptr` ABI, and is compile- and `odinfmt`-identical.

Both focused tests pass alone and together in two runs with zero leak
diagnostics. History v1/v2, codec 2/2, migration 5/5, `make check`, scaffold,
and all no-overwrite gates pass. The full suite executes 513 tests with exactly
one expected failure, `fixture_schema_production_graph_matches_draft`; schema
check reports the same single frozen-v2 mismatch and no other error.

The six accepted hashes remain exact:

- v1 manifest `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- v2 manifest `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- v1 history `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- v2 history `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`;
- 1→2 migration `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`;
- occupancy production `5a4aaa44103f3a829e61bdfa2c5da9aadd2f11feffd4c06c68f984a51828268a`.

The isolated scope contains only `src/main.odin`, the generated 2→3 source,
the two focused test files, and this plan. No binaries, probes, temporary
roots, v3 manifest, or v3 history package remain.

### Reviewer verification — repair required

Schema behavior is correct, but M4B2B2B is not accepted yet. Independent
locked-Odin verification confirms:

- both focused tests pass together with zero leak diagnostics;
- `make check` passes;
- full suite executes exactly 513 tests with only the expected
  `fixture_schema_production_graph_matches_draft` failure;
- 1→2 output is byte-identical twice at 6,873 bytes and exact 21/16/5;
- 2→3 output is byte-identical twice at 1,236 bytes and exact 2/1/1;
- all six accepted hashes and unresolved scaffold SHA are exact;
- no v3 manifest/history artifact or binary exists.

Isolated `jj diff --git` from pre-draft evolution `b99d58bc` exposes five
unrelated formatter hunks in `src/main.odin` in addition to the intended
occupant line. They rewrite existing flight interpolation, dialogue opening,
projected-face append, car physics creation, and Libellula stepping. No
behavior changes are apparent, but they violate narrow scope and cannot ride
with the schema draft.

## Milestone 4B2B2BR — Remove formatter spill

### Repair handoff

Change only `src/main.odin` and this plan. Restore the five existing-code hunks
byte-for-byte from pre-draft evolution `b99d58bc`; preserve the one intended
addition:

```odin
occupant: vehicles.Fixture_Occupant,
```

The repaired `src/main.odin` delta against `b99d58bc` must contain exactly one
hunk and one added line immediately before `pilot`.

Restore these five formatter-only regions:

1. `aircraft_render_body` — keep the prior multiline
   `flight.orthonormalize` call;
2. story resident dialogue opening — keep the prior multiline
   `dialogue.open` call;
3. Libellula projected faces — keep the prior multiline `append` call;
4. car physics setup — keep the prior multiline `physics.create_vehicle`
   call and existing field spacing;
5. fixed-step Libellula update — keep the prior multiline
   `libellula_game.step` call.

Do not use whole-file `jj restore`: that would remove the occupant field. Do
not rerun whole-file `odinfmt` on `src/main.odin`; current formatter drift would
recreate these unrelated hunks. Do not edit either focused test, generated
scaffold, schema artifacts, migration runtime, codec, vehicle code, Makefile,
or tooling.

Run:

1. isolated `jj diff --git --from b99d58bc --to @ -- src/main.odin` — exactly
   one occupant-line addition;
2. both focused B2B2B tests together twice, sequentially;
3. read-only 1→2 and 2→3 reports twice;
4. explicit 2→3 scaffold check;
5. `make check`;
6. `make test` — exactly 512/513, only expected frozen-schema mismatch;
7. all hash and no-artifact checks from B2B2B.

The unresolved scaffold SHA must remain
`2953cd64cba6e7c5675ac0cf3336c5f895ef17ee5955fa9b87741d138ab5e5a0`.
No generated source or test byte may change.

### Acceptance criteria

- `src/main.odin` has only the occupant addition against `b99d58bc`;
- five formatter-only hunks are gone;
- B2B2B report, scaffold, tests, hashes, and expected single red gate remain
  exact;
- repair changes no production behavior beyond adding serialized occupant
  state.

### Verification status — 2026-07-29

M4B2B2BR is complete. The isolated `jj diff --git --from b99d58bc --to @ --
src/main.odin` now contains exactly one added line immediately before `pilot`:
`occupant: vehicles.Fixture_Occupant,`. The five unrelated formatter regions
were restored byte-for-byte: aircraft orthonormalization, story dialogue
opening, Libellula projected-face append, car physics setup, and fixed-step
Libellula stepping.

Both focused B2B2B tests pass twice with zero leak diagnostics. Read-only
reports remain deterministic and exact: 1→2 is 6,873 bytes with 21 changes
(16 state, 5 supporting), and 2→3 is 1,236 bytes with two changes (1 state,
1 supporting). Explicit 2→3 scaffold-check and `make check` pass. The full
suite executes 513 tests with exactly one expected frozen-schema mismatch.

All accepted hashes remain exact, including unresolved scaffold SHA
`2953cd64cba6e7c5675ac0cf3336c5f895ef17ee5955fa9b87741d138ab5e5a0`. No v3
manifest/history artifact or generated runner binary remains.

### Reviewer verification — M4B2B2B and M4B2B2BR accepted

Accepted. Isolated `src/main.odin` diff from pre-draft evolution `b99d58bc`
contains one hunk and one added occupant line. All five unrelated formatter
hunks are gone.

Independent locked-Odin verification:

- both focused draft tests pass sequentially twice, 2/2, with zero leaks;
- `make check` and explicit 2→3 scaffold-check pass;
- full suite executes 513 tests with only the expected frozen-v2 mismatch;
- accepted schema/history/1→2 migration/occupancy hashes remain exact;
- unresolved 2→3 scaffold SHA remains
  `2953cd64cba6e7c5675ac0cf3336c5f895ef17ee5955fa9b87741d138ab5e5a0`;
- no v3 manifest/history artifact or generated binary exists.

## Milestone 4B2B3 — Resolve and freeze migration 2→3

### Next slave handoff

Resolve the one occupant obligation with explicit `.On_Foot` legacy policy.
Build and prove the real 2→3 wrapper, but do not place it in the production
registry and do not activate schema version 3.

### Allowed files

- `src/fixture_migration_v0002_to_v0003.odin`;
- add `src/fixture_migration_v0002_to_v0003_runtime.odin`;
- add `src/fixture_migration_v0002_to_v0003_test.odin`;
- `tests/fixture_migration_scaffold_test.odin`;
- `Makefile`;
- this plan.

Do not edit `src/main.odin`, `src/fixture_migration_runtime.odin`, production
registry arrays, v1→2 migration or tests, codec, fixture container, schema
tool/packages, schema-diff test, either frozen manifest, either historical
package, vehicle code, editor lifecycle, or `zelda-engine`. Do not create a v3
manifest/history package or install a production 2→3 step.

### Resolve migration source

In `src/fixture_migration_v0002_to_v0003.odin`:

1. retain exact generated endpoints, import, and `#by_ptr
   fixture_v0002.Fixture` ABI;
2. change the sole occupant resolution from `.Unresolved` to `.Scripted`;
3. retain the exact literal occupant change ID in the resolution table; the
   strict scaffold parser deliberately rejects identifier indirection there;
4. add one small shared resolver that accepts `^Fixture`, rejects nil with
   `.Invalid_Argument`, sets only `tentative.occupant = .On_Foot`, and returns
   success;
5. make `fixture_migrate_v0002_to_v0003` call that shared resolver.

The historical value and allocator remain ABI inputs. This migration has no
automatic data dependency and allocates nothing; mark those inputs used
without inventing fake validation or scratch allocation. Do not inspect
historical `pilot.mode`, `aircraft.active`, vehicle fields, pointers, or any
current tentative relationship. Legacy policy is unconditional `.On_Foot`.

Do not mutate any other tentative field. Calling the resolver repeatedly must
be idempotent.

### Add unregistered real wrapper

Add `src/fixture_migration_v0002_to_v0003_runtime.odin` so accepted
`src/fixture_migration_runtime.odin` and its production registry stay
byte-identical.

Implement:

```text
fixture_migration_step_v0002_to_v0003
```

Validate before mutation:

- non-nil context and tentative state;
- step endpoints exactly 2→3;
- target version at least 3;
- original source version exactly 1 or 2;
- transaction allocator is a live dynamic-arena allocator with a live block
  allocator.

For direct source version 2:

1. prepare a disjoint temporary historical arena backed by the transaction
   arena's block allocator, matching the accepted 1→2 wrapper ownership
   pattern;
2. allocate `fixture_v0002.Fixture` there;
3. decode original source payload into that immutable v2 history type with
   `hs.portable_decode` and exact fixture codec config;
4. map allocation-limit failures to `.Out_Of_Memory` and all other decode
   failures to `.Historical_Decode`;
5. dispose portable errors and historical arena on every exit;
6. call `fixture_migrate_v0002_to_v0003` only after successful historical
   decode.

For chained original source version 1, do not decode `source_payload` as v2.
The 1→2 wrapper has already validated and migrated source into tentative state.
Call the same shared occupant resolver directly on that tentative state.

This branch distinction is required. Original payload remains v1 for every
step in a chain; pretending it became v2 is the classic migration-chain trap.

Do not add the wrapper to `fixture_migration_production_steps` or change
`fixture_migration_production_registry`. B2B4 owns installation.

### Resolve scaffold proof

Update the existing v2→v3 scaffold test rather than adding another test:

- rename it from draft/unresolved wording to resolved wording;
- build the same exact frozen-v2/live report;
- read and parse the real migration source;
- require one occupant resolution with `.Scripted`;
- validate source against the two-change report;
- require no resolution for the automatic enum type-add;
- pin exact endpoints, v2 history import, and `#by_ptr` ABI;
- require the shared resolver sets only `.On_Foot`;
- keep idempotent disposal and zero-leak checks.

Do not require resolved source to equal the unresolved renderer output. The
renderer is supposed to produce a failing scaffold; human scripting now
supplies policy on top. Keep exact 2→3 semantic diff proof unchanged.

### Real migration proof

Add one comprehensive named test:

```text
fixture_migration_v0002_to_v0003_direct_chained_and_failures
```

Use real portable payloads and production procedures.

Direct v2 case:

1. create/encode immutable `fixture_v0002.Fixture`;
2. deliberately set historical `pilot.mode = .Driving` and
   `aircraft.active = .Libellula_Mk2`;
3. run a local one-step 2→3 registry containing the new real wrapper;
4. require success and exact `.On_Foot`;
5. require legacy pilot mode, active aircraft, and unrelated sentinel state
   remain preserved rather than normalized or used for inference;
6. dispose result/error twice and prove zero outstanding allocations.

Chained v1 case:

1. use a valid real v1 golden payload accepted by the production 1→2 step;
2. set its historical pilot/aircraft state to the same driving/Mk2
   contradiction, using a temporary decoded v1 historical value if needed;
3. run a local registry with real production 1→2 wrapper followed by new real
   2→3 wrapper;
4. require `.On_Foot`, exact 1→2 story/structural preservation, and unchanged
   unrelated sentinels;
5. prove the chain succeeds even though original v1 payload is not decodable
   as `fixture_v0002.Fixture`.

Policy/unit cases:

- resolution table contains exactly one `.Scripted` occupant ID;
- shared resolver rejects nil without mutation;
- resolver overwrites each nonzero occupant enum value with `.On_Foot`;
- resolver is idempotent and performs zero allocations;
- direct migration leaves historical v2 bytes/state unchanged;
- production registry remains exactly one installed 1→2 step.

Hostile/atomic cases:

- nil/forged contexts and wrong endpoints/source versions fail before mutation;
- truncated, corrupt, wrong-schema, and invalid-enum direct v2 payloads return
  historical-decode failure and do not resolve occupant;
- every direct-wrapper historical-arena allocation failure returns
  `.Out_Of_Memory`, leaves tentative occupant and sentinels unchanged, and
  leaks nothing;
- chained source-version-1 branch performs no historical decode/allocation in
  the 2→3 step;
- failed transactions return no owned result and remain double-disposable.

Reuse existing migration fault allocator and v1 golden helpers where practical.
Do not duplicate the 1→2 story matrix or create a second migration engine.

### Make target

Append only the new named test to `fixture-migration-test`. Existing five names
and order remain unchanged. Focused migration target must run exactly 6 tests.
The new proof lives under `src`, so repository `make test` remains 513 tests.

### Required gates

Run:

1. new migration test alone three consecutive times;
2. resolved scaffold test alone;
3. `make fixture-migration-test` — exactly 6/6, zero leaks;
4. `make fixture-codec-test` — 2/2;
5. read-only 1→2 report twice — exact 6,873 bytes and 21/16/5;
6. read-only 2→3 report twice — exact 1,236 bytes and 2/1/1;
7. explicit 2→3 scaffold-check and no-overwrite generation;
8. default 1→2 scaffold-check and no-overwrite generation;
9. v1/v2 history checks;
10. `make check`;
11. `make test` — exactly 512/513, only expected
    `fixture_schema_production_graph_matches_draft` failure;
12. `make fixture-schema-check` — same single expected mismatch.

Confirm six accepted hashes remain exact. Compute and record the new resolved
2→3 migration SHA; repeat every gate/no-overwrite command and prove that SHA
does not change. Remove binaries, probes, and temporary roots.

### Acceptance criteria

- sole occupant obligation is `.Scripted`;
- shared policy is unconditional, idempotent, zero-allocation `.On_Foot`;
- direct v2 path decodes immutable v2 history before mutation;
- chained v1 path never decodes original payload as v2;
- direct and chained paths use the same resolver;
- hostile/OOM paths are atomic and memory-clean;
- production registry still exposes only accepted 1→2 step;
- schema source/version and frozen v2 remain in deliberate draft mismatch;
- 1→2 and 2→3 report bytes remain exact;
- resolved 2→3 source has a frozen, reproducible SHA;
- focused gates pass and full suite has exactly one known schema mismatch.

### Verification status — 2026-07-29

M4B2B3 is complete. The generated v2→v3 source now has one `.Scripted`
occupant resolution and shared unconditional `.On_Foot` policy. The new
unregistered runtime wrapper decodes direct v2 history in a disjoint arena,
while chained source-v1 execution calls the same resolver without decoding the
original bytes as v2. The production registry remains the accepted single
1→2 step.

Locked-Odin proof is green:

- the focused direct/chained/hostile test passes three consecutive runs with
  zero leak diagnostics;
- the resolved scaffold test passes alone, and `make test` executes 513 tests
  with exactly one expected frozen-schema mismatch;
- `make fixture-migration-test` passes exactly 6/6 with zero leaks;
- codec passes 2/2, `make check` passes, and v1/v2 history checks pass;
- default 1→2 and explicit 2→3 scaffold checks pass repeatedly without
  overwriting source;
- accepted report output remains deterministic: 1→2 is 6,873 bytes with
  21 changes (16 state, 5 supporting), and 2→3 is 1,236 bytes with two
  changes (1 state, 1 supporting);
- resolved migration source SHA is
  `03548ce6ee56db59c54086756d37a1b48d120ebfc22298c8cb00be67287c720d`;
- all six accepted schema/history/1→2 hashes remain exact; schema-check still
  reports only the deliberate frozen-v2 versus live occupancy mismatch;
- generated `tests.bin` was removed and no v3 manifest/history artifact exists.

### Reviewer verification — B3R required

B3 production behavior and ownership are sound, but proof is not yet strong
enough for activation.

Independent locked-Odin verification confirms:

- focused B3 test passes three consecutive runs with zero leaks;
- `make check` and resolved 2→3 scaffold-check pass;
- `make test` correctly remains 513 tests because the new proof is in `src`,
  with only the expected frozen-schema mismatch;
- production registry remains exactly the single 1→2 step;
- resolved migration SHA is exactly
  `03548ce6ee56db59c54086756d37a1b48d120ebfc22298c8cb00be67287c720d`;
- all earlier accepted hashes remain exact and no binary/v3 artifact exists.

Three assertions can currently pass for the wrong reason:

1. Chained v1 result sets historical Driving/Mk2 but never asserts those two
   values survive alongside `.On_Foot`.
2. The alleged wrong-schema case truncates the v1 payload first, so it proves
   truncation rejection again rather than rejection of a complete v1 payload
   presented as v2.
3. Four wrong-endpoint/source contexts have a nil transaction allocator, so
   allocator validation alone makes every case pass even if endpoint checks
   were deleted.

## Milestone 4B2B3R — Close B3 proof gaps

### Repair handoff

Change only:

- `src/fixture_migration_v0002_to_v0003_test.odin`;
- this plan.

Do not edit migration source, runtime wrapper, Makefile, scaffold/schema tests,
registry, codec, manifests/history, `src/main.odin`, vehicle code, or tooling.

Add exact chained assertions:

```odin
testing.expect(t, chained_result.fixture.pilot.mode == .Driving)
testing.expect(t, chained_result.fixture.aircraft.active == .Libellula_Mk2)
```

Keep existing `.On_Foot`, story, structural, and sentinel assertions. This
pins policy as a new serialized default without silently normalizing legacy
driving state.

Replace the wrong-schema hostile call with the complete valid `v1_payload`;
do not slice, truncate, corrupt, or mutate it. Present that full byte slice to
the direct wrapper as `source_version = 2`. Require `.Historical_Decode` and
unchanged `.Car`/sentinel tentative state. The separate truncated-v2 case
already owns truncation coverage.

Add a live-allocator endpoint matrix. Allocate one valid transaction arena and
tentative Fixture, then call the wrapper with exactly one invalid field per
case while all other fields and allocator are valid:

- original source version 0 or 3;
- target version 2;
- step-from version 1;
- step-to version 4;
- nil tentative with otherwise valid context.

Reset occupant/sentinel before every case. Require `.Invalid_Argument`, zero
mutation, zero wrapper allocation, disposed error, and final zero outstanding
allocations. Keep existing nil/dead-allocator cases; they test a different
boundary.

Add one transaction-level hostile proof using the local real 2→3 registry and
malformed direct-v2 payload. Require failure, empty owned result, double-safe
error/result disposal, and zero outstanding allocations. Accept the precise
pre-step error kind produced by the transaction boundary only if pinned
explicitly; do not weaken to “any error”.

Run:

1. named B3 test alone three consecutive times;
2. `make fixture-migration-test` — exactly 6/6;
3. resolved 2→3 scaffold test alone;
4. `make fixture-codec-test` — 2/2;
5. `make check`;
6. `make test` — exactly 512/513, only expected schema mismatch;
7. both semantic reports twice and all accepted hash checks.

Production files and resolved migration SHA must remain byte-identical. Remove
generated binaries after every direct Odin test command.

### Acceptance criteria

- chained v1 proof pins Driving/Mk2 preservation and `.On_Foot`;
- complete valid v1 payload is rejected when presented as direct v2 history;
- each context field is rejected independently under a live allocator;
- failed real transaction returns no ownership and is double-disposable;
- B3 production bytes and all hashes remain exact;
- focused gates pass with zero leaks and only deliberate schema mismatch stays
  red.

## Milestone 4B2B3R2 — Exact historical portable schema provenance

### Blocker evidence

The B3R full-payload proof fails for a real production reason. `hs` portable
decode intentionally walks only saved struct fields, skips saved fields absent
from the destination, leaves destination-only fields zeroed, and permits
fixed/dynamic array crossing. Consequently, the complete valid frozen-v1
payload decodes into `fixture_v0002.Fixture`, the wrapper succeeds, and the
tentative fixture mutates.

`HSPORT1` carries a complete portable type table but no source type identity.
`ADRFIX` stores the schema version separately and checksums only the payload, so
the version label alone does not bind the bytes to a schema. Checking only
required fields is insufficient: array shape, enum declarations, field order,
and supporting-type changes can still masquerade as another version.

### Implementation handoff

Change only:

- `packages/hs/portable.odin`;
- `tests/hs_portable_test.odin`;
- `src/fixture_codec.odin`;
- `src/fixture_migration_runtime.odin`;
- `src/fixture_migration_v0002_to_v0003_runtime.odin`;
- `src/fixture_migration_v0002_to_v0003_test.odin`;
- this plan.

Do not change the portable or fixture-container wire format, manifests,
generated history, migration source/scaffold, registry, Makefile, schema
version, or `src/main.odin`.

Add an opt-in exact-schema flag to `hs.Portable_Config`; default must remain
false. In `hs.portable_decode`, after header/table parse and graph validation
but before body decode or destination mutation:

1. discover the destination runtime type graph with the existing discovery
   code, allocator, limits, and exclusion tag;
2. emit its canonical type table with the existing table emitter;
3. require exact root handle, type count, table byte length, and table bytes;
4. return `.Type_Mismatch` at the table/root path on mismatch;
5. preserve existing allocation-style `.Limit_Exceeded` behavior on OOM;
6. release discovery types, handle map, writer storage, error paths, and all
   partial ownership on every exit.

Canonical equality must cover scalar kind/width/sign, type sharing/handles,
array kind/count, struct field names/order/handles, and enum names/values.
Do not re-encode the value body: fixtures are large and the type table already
contains the required structural identity.

Keep ordinary portable decode schema-tolerant. Extend existing `hs` tests
without adding a new top-level test procedure:

- same-schema exact preflight and decode succeed;
- the existing additive/default-compatible case still succeeds;
- exact mode rejects additive/missing fields before destination mutation;
- exact mode rejects fixed/dynamic array and enum-definition drift;
- malformed header/table, nil allocator, OOM sweep, error double-disposal, and
  zero outstanding allocations are pinned.

Expose one product helper/config for exact historical decode. Use it for:

- frozen v1 decode in `fixture_migration_step_v0001_to_v0002`;
- frozen v2 decode in the source-v2 branch of
  `fixture_migration_step_v0002_to_v0003`.

Keep tentative transaction decode permissive while live source version remains
2 and already contains the draft occupant field. Keep the source-v1 branch of
the 2→3 wrapper allocation-free: step 1 has already authenticated and decoded
v1 history. Product-level source-version dispatch for current v3 belongs in
B4 activation, after the source version bump.

Retain every B3R proof. The complete valid v1 payload presented as source v2
must return `.Historical_Decode`, leave `.Car` and sentinels unchanged, dispose
twice safely, and leak nothing.

### Verification

Run:

1. the extended `hs` portable test alone, including its complete OOM sweep;
2. named B3 test three consecutive times;
3. `make fixture-migration-test` — exactly 6/6;
4. resolved 2→3 scaffold test;
5. `make fixture-codec-test` — exactly 2/2;
6. `make check`;
7. `make test` — exactly 512/513, only the deliberate frozen-v2/live-schema
   mismatch;
8. schema/history/scaffold checks and both semantic reports twice.

All accepted hashes, including resolved v2→3 migration
`03548ce6ee56db59c54086756d37a1b48d120ebfc22298c8cb00be67287c720d`,
must remain exact. Remove direct Odin test binaries and probes.

### Acceptance criteria

- exact mode authenticates the whole canonical portable type graph before body
  mutation;
- default mode preserves the intended migration-compatible decode behavior;
- both historical production wrappers use exact mode;
- the full v1-as-v2 hostile proof fails closed and atomically;
- OOM and disposal contracts remain leak-free;
- no wire, schema, history, scaffold, migration-source, or accepted-hash bytes
  change.

### Verification status — 2026-07-29

M4B2B3R2 implementation and locked-Odin verification are complete.

`hs.Portable_Config` now has an opt-in `exact_schema` policy. After strict
header/table parsing and graph validation, exact decode discovers the runtime
destination graph with the same exclusion policy and limits, emits the same
canonical table representation used by encode, and compares root handle, type
count, byte length, and every table byte before body mutation. Ordinary decode
still defaults to the migration-compatible additive and fixed/dynamic crossing
behavior.

Exact discovery and exact body struct traversal reuse the static parent path
instead of allocating diagnostic field paths. This keeps the new provenance
mode exhaustively OOM-testable; default decode retains its existing detailed
field paths and behavior. Allocation-return handling is now explicit for
portable writers, discovery metadata, parsed type records/names, and graph
state.

The existing additive portable test now also proves:

- exact same-schema decode succeeds and restores both fields;
- default additive decode still succeeds;
- exact additive and missing-field graphs fail `.Type_Mismatch` before
  sentinel mutation;
- fixed/dynamic array and enum-definition drift fail before destination
  mutation;
- malformed header/table and nil allocator fail with their precise kinds;
- all nine successful exact-decode allocation points fail individually as
  `.Limit_Exceeded`, dispose twice safely, preserve sentinels, and leave zero
  outstanding allocations.

Product code exposes one exact historical portable config. The real 1→2
wrapper uses it for frozen v1 history, and the source-v2 branch of the 2→3
wrapper uses it for frozen v2 history. Tentative transaction decode remains
permissive. The source-v1 branch of the 2→3 wrapper still calls only the shared
resolver and its zero-allocation proof remains green. Production registry
dispatch remains the single accepted 1→2 step.

Locked gates:

- the extended portable test passes alone with zero leak diagnostics;
- the named B3 test passes three consecutive runs in 11.180s, 12.732s, and
  11.977s with zero leaks;
- `make fixture-migration-test` passes exactly 6/6 in 3m37.744s;
- resolved 2→3 scaffold-check and codec 2/2 pass;
- v1/v2 history checks, both 1→2 and 2→3 scaffold checks, and no-overwrite
  generation pass;
- `make check` passes;
- `make test` is exactly 512/513, with only the deliberate
  `fixture_schema_production_graph_matches_draft` mismatch and zero leak
  diagnostics;
- `make fixture-schema-check` reports only the same frozen-v2/live-occupant
  mismatch;
- repeated semantic reports are byte-identical: 1→2 is 6,873 bytes with
  21/16/5 changes, and 2→3 is 1,236 bytes with 2/1/1 changes.

All immutable hashes remain exact:

- v1 manifest `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- v2 manifest `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- v1 history `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- v2 history `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`;
- 1→2 migration `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`;
- occupancy production `5a4aaa44103f3a829e61bdfa2c5da9aadd2f11feffd4c06c68f984a51828268a`;
- resolved 2→3 migration
  `03548ce6ee56db59c54086756d37a1b48d120ebfc22298c8cb00be67287c720d`.

### Reviewer acceptance — 2026-07-29

M4B2B3, B3R, and B3R2 are accepted.

Independent review confirms:

- the change from the pre-B3R baseline is limited to the six allowed source/test
  files and this plan;
- canonical table comparison occurs after hostile table parse/graph validation
  and before body mutation;
- exact mode is opt-in, and default additive/fixed-dynamic behavior is
  unchanged;
- exact discovery owns and releases every type, handle, table, graph-state, and
  error allocation;
- exact body traversal uses static paths only in exact mode; default detailed
  field paths remain unchanged;
- frozen v1 and direct frozen v2 wrappers use exact mode, while source-v1 2→3
  dispatch remains allocation-free;
- the strengthened B3 proof presents the complete v1 payload as v2, validates
  every endpoint under a live allocator, and pins transaction failure
  ownership.

Reviewer reruns pass:

- `tests.hs_portable_additive_structs_are_safe` — 1/1, zero leaks;
- `main.fixture_migration_v0002_to_v0003_direct_chained_and_failures` — 1/1
  in 10.594s, zero leaks;
- `make check`;
- all seven accepted SHA-256 values exactly match the locked values above;
- no generated binary or probe remains.

The deliberate frozen-v2/live-occupant mismatch remains the only red gate.

## Milestone 4B2B4A — Activate and freeze schema 3

### Handoff

Change only:

- `src/main.odin`;
- new `fixtures/schema/v0003.fixture-schema`;
- new `packages/fixture_history/v0003/schema.generated.odin`;
- `tests/fixture_schema_test.odin`;
- `tests/fixture_schema_diff_test.odin`;
- `tests/fixture_history_test.odin`;
- this plan.

Do not edit runtime migration/codec code or tests, v1/v2 manifests/history,
resolved migration sources, scaffold tooling/tests, Makefile, occupancy
production, or other `src/main.odin` hunks.

Implementation order:

1. Change only `FIXTURE_SCHEMA_VERSION :: 2` to `3` in `src/main.odin`.
2. Generate the source manifest twice. Commit the byte-identical result as
   immutable `fixtures/schema/v0003.fixture-schema`.
3. Generate version-3 history twice. Commit the byte-identical result as
   `packages/fixture_history/v0003/schema.generated.odin`.
4. Update the production schema test to require source version 3 and exact
   equality with frozen v3.
5. Replace the live-draft 2→3 diff helper/proof with frozen v2 versus frozen v3.
   After activation, migration semantics must never depend on mutable live
   source.
6. Extend the existing history version proof to import/compile v3, parse the
   frozen v3 manifest, re-emit v3 history byte-for-byte, and pin both new
   SHA-256 values.
7. Pin occupant metadata in frozen artifacts: five declared `u8` values and
   the root `Fixture.occupant` field.

Expected frozen v3 manifest facts from the accepted draft:

- 1,378 lines;
- 150 records;
- 146 root fields;
- exact v2→v3 report: 1,236 bytes, two changes, one state and one supporting;
- `field-add:adriatic:src.Fixture.occupant` remains scripted;
- the five-value occupant enum remains automatic.

Do not hand-edit generated artifacts except through their existing generator.
Do not regenerate or alter frozen v1/v2.

### Verification

Run:

1. source schema generation twice and byte comparison;
2. `make fixture-schema-check`;
3. frozen v2→v3 semantic report twice with exact 1,236-byte/2/1/1 result;
4. v3 history generation twice and byte comparison;
5. `make FIXTURE_HISTORY_VERSION=1 fixture-history-check`;
6. the same for versions 2 and 3;
7. focused schema/diff/history tests;
8. default 1→2 and explicit 2→3 scaffold checks;
9. `make check`;
10. all seven accepted hash checks plus the two new pinned hashes.

B4A is an intermediate activation step. Historical production codec/migration
tests may remain red until B4B installs the 2→3 registry step. Record exact
failures; do not weaken tests or runtime code in this milestone. Remove
generated binaries and temporary v3 copies.

### Acceptance criteria

- source version is exactly 3;
- committed v3 manifest and history are generator-owned and deterministic;
- schema check is green;
- frozen v2→v3 diff remains exact and no longer reads live source;
- v1/v2 artifacts and every accepted hash remain unchanged;
- `src/main.odin` diff for this milestone is only the version constant;
- no runtime chain or codec behavior changes yet.

### Verification status — 2026-07-29

M4B2B4A implementation and locked-Odin verification are complete. Reviewer
acceptance is pending.

`FIXTURE_SCHEMA_VERSION` is now 3. The existing source generator produced the
immutable v3 manifest twice with byte-identical output:

- 1,378 lines;
- 150 records;
- 146 root fields;
- SHA-256
  `210c2d82c27ac668bcdae75f18c5735726f7d88ca48609a8795bdaec56225b9f`.

The manifest contains exactly one root
`adriatic:src.Fixture.occupant` field and the supporting
`adriatic:packages/vehicles.Fixture_Occupant` enum with `u8` base and the
ordered values `On_Foot = 0`, `Car = 1`, `Postale = 2`, `Libellula = 3`, and
`Libellula_Mk2 = 4`.

The existing history generator produced the immutable v3 package twice with
byte-identical output:

- 1,826 lines;
- SHA-256
  `508e0c043c8886ff637132081f8fb27ec9b02a10a49142ec6dad1e0f20ba99bd`.

The history test imports the generated package, compiles the v3 root and
occupant ABI, parses the frozen v3 manifest, pins the 150/146 record and root
field counts plus exact occupant metadata, re-emits the package byte-for-byte,
and pins both new SHA-256 values.

The shared 2→3 report helper now reads only immutable v2 and v3 manifests; it
does not build or inspect mutable live source. Two CLI reports are
byte-identical at exactly 1,236 bytes with two changes, one state and one
supporting. The root occupant field remains scripted and the five-value
supporting enum remains automatic.

Locked gates:

- source manifest generation twice and byte comparison pass;
- v3 history generation twice and byte comparison pass;
- focused schema, frozen-diff, and history tests pass 3/3 in 184.081ms with
  zero leak diagnostics;
- `make fixture-schema-check` passes;
- v1, v2, and v3 history checks and package compilation pass;
- default 1→2 and explicit 2→3 scaffold checks pass;
- `make check` passes;
- `make test` passes 513/513 with zero leak diagnostics;
- `make fixture-migration-test` passes 6/6 in 3m33.570s with zero leak
  diagnostics.

The expected intermediate runtime gap is isolated to
`make fixture-codec-test`: exactly 0/2 tests pass. Both
`main.fixture_codec_owned_decode_allocation_failures_and_preflight` and
`main.fixture_codec_real_fixture_round_trip_and_failures` fail because the
production registry still ends at schema 2. The first no longer obtains a
successful owned decode/allocation baseline. The second cannot decode the
current v3 or historical v1 fixture and consequently observes different
malformed/invalid migration error details. There are zero leak diagnostics.
No codec or migration runtime source or test was changed.

All seven accepted hashes remain exact:

- v1 manifest `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`;
- v2 manifest `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`;
- v1 history `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`;
- v2 history `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`;
- 1→2 migration `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`;
- occupancy production `5a4aaa44103f3a829e61bdfa2c5da9aadd2f11feffd4c06c68f984a51828268a`;
- resolved 2→3 migration
  `03548ce6ee56db59c54086756d37a1b48d120ebfc22298c8cb00be67287c720d`.

The isolated milestone diff contains only the seven allowed paths. The
`src/main.odin` delta is exactly the schema-version constant. No generated
binary, probe, or temporary comparison file remains.

### Reviewer verification — B4AR required

Generated artifacts, hashes, counts, frozen report behavior, test coverage,
and `src/main.odin` scope are correct. Independent checks confirm:

- v3 manifest SHA
  `210c2d82c27ac668bcdae75f18c5735726f7d88ca48609a8795bdaec56225b9f`,
  1,378 lines, 150 records, and 146 root fields;
- v3 history SHA
  `508e0c043c8886ff637132081f8fb27ec9b02a10a49142ec6dad1e0f20ba99bd`
  and 1,826 lines;
- no binary or probe artifact;
- only the version constant changed in `src/main.odin`.

One naming defect remains. The shared report helper now reads immutable v2 and
v3 manifests, but is still named
`fixture_schema_diff_live_occupancy_report`. Its scaffold caller preserves the
stale live-draft vocabulary. This is misleading after activation and violates
the frozen-source contract at the API boundary.

## Milestone 4B2B4AR — Rename the frozen report helper

Change only:

- `tests/fixture_schema_diff_test.odin`;
- `tests/fixture_migration_scaffold_test.odin`;
- this plan.

Rename `fixture_schema_diff_live_occupancy_report` to
`fixture_schema_diff_v0002_to_v0003_frozen_report` and update both callers.
Change no behavior, expectations, generated bytes, or other names.

Run the frozen diff test and resolved 2→3 scaffold test twice, then
`make test`, `make check`, both report commands, and all nine hash checks.
The v3 artifacts and `src/main.odin` must remain byte-identical. Remove test
binaries.

### Milestone 4B2B4AR implementation evidence — 2026-07-29

The shared helper is now named
`fixture_schema_diff_v0002_to_v0003_frozen_report`; the frozen-diff and
resolved-scaffold callers use the same name. No behavior or expectation
changed.

Locked verification:

- the two named tests pass together twice, 2/2 each run, with zero leak
  diagnostics;
- `make test` passes 513/513 with zero leak diagnostics;
- `make check` passes;
- read-only 1→2 and 2→3 reports remain exactly 6,873 and 1,236 bytes;
- v1/v2/v3 manifest hashes remain
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`,
  `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`,
  and `210c2d82c27ac668bcdae75f18c5735726f7d88ca48609a8795bdaec56225b9f`;
- v1/v2/v3 history hashes remain
  `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`,
  `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`,
  and `508e0c043c8886ff637132081f8fb27ec9b02a10a49142ec6dad1e0f20ba99bd`;
- the 1→2 migration, occupancy production, and resolved 2→3 migration hashes
  remain
  `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`,
  `5a4aaa44103f3a829e61bdfa2c5da9aadd2f11feffd4c06c68f984a51828268a`,
  and `03548ce6ee56db59c54086756d37a1b48d120ebfc22298c8cb00be67287c720d`;
- v3 artifacts and `src/main.odin` remain byte-identical;
- no generated binary, probe, or comparison artifact remains.

### Reviewer acceptance — 2026-07-29

M4B2B4A and B4AR are accepted. Independent review confirms the isolated B4A
diff contains exactly the seven authorized paths, the `src/main.odin` change is
only version 2→3, the generated counts and both new hashes are exact, and the
diff/scaffold helper now has one frozen-source name at all call sites.
`make check` passes and no artifact remains.

## Milestone 4B2B4B — Install the production chain

Change only:

- `src/fixture_migration_runtime.odin`;
- `src/fixture_migration_test.odin`;
- `src/fixture_migration_story_test.odin`;
- `src/fixture_migration_structural_test.odin`;
- `src/fixture_migration_v0002_to_v0003_test.odin`;
- this plan.

Do not edit codec production/tests, schema/history artifacts or tests,
scaffold/tooling, Makefile, migration source/resolution files, occupancy,
`src/main.odin`, or any other file.

Implementation:

1. Change `fixture_migration_production_steps` from one step to two.
2. Preserve the accepted 1→2 entry byte-for-byte.
3. Append the real resolved 2→3 entry:

```odin
{
    from_version = FIXTURE_MIGRATION_V0002_TO_V0003_FROM_VERSION,
    to_version   = FIXTURE_MIGRATION_V0002_TO_V0003_TO_VERSION,
    wrapper      = fixture_migration_step_v0002_to_v0003,
    change_id    = "field-add:adriatic:src.Fixture.occupant",
},
```

4. For `source_version == target_version == FIXTURE_SCHEMA_VERSION`, decode
   the current fixture with exact-schema config. Migrating v1/v2 tentative
   decode stays tolerant; the corresponding production wrapper authenticates
   its frozen source graph before mutation.
5. Keep registry validation strict and ordered. Do not add shortcuts, inferred
   occupant policy, or direct 1→3 step.
6. Update production calls and assertions from current 2 to current 3.
   Local one-step 1→2 registries remain 1→2.
7. Pin the real registry as exactly 1→2 then 2→3.
8. Every successful historical chain resolves occupant to `.On_Foot` while
   preserving historical `.Driving`, `.Libellula_Mk2`, story, structural, and
   sentinel state.
9. Update invalid endpoint and OOM matrices for current 3 and future 4.
10. Add a complete-payload hostile proof for current provenance: present a
    valid frozen-v2 payload as source/target version 3 through the real
    production registry. Require `.Tentative_Decode`, empty result, unchanged
    source bytes, double-safe error/result disposal, and zero outstanding
    allocations. Do not truncate or corrupt the payload.

Keep local synthetic registry tests honest:

- current-source tests use 3→3;
- local historical one-step tests remain 1→2;
- local chained tests may remain 1→2→3;
- true future version 4 remains unsupported;
- no test may pass because an otherwise-invalid context has a nil allocator.

`make fixture-migration-test` must remain exactly 6/6. The existing production
OOM sweep must traverse the real two-step chain. Direct v2 and chained v1
proofs remain atomic, double-disposable, source-immutable, and leak-free.

Run the B3 test alone three times, migration 6/6, all schema/history and
scaffold gates, both reports twice, `make check`, and `make test` 513/513.
All nine hashes must remain exact and no binary/probe may remain.

Do not edit codec files in B4B. Both current and historical production decode
paths must execute successfully. The focused codec target may remain exactly
1/2 only because `src/fixture_codec_test.odin` still hardcodes the re-encoded
historical container version as 2. Pin that single stale assertion and no other
failure. B4C owns changing it to current version 3 and extending both codec
tests for all five occupant values and all three source versions.

### Milestone 4B2B4B implementation evidence — 2026-07-29

The production registry now contains exactly the accepted 1→2 step followed
by the resolved 2→3 occupant step. The first entry remains byte-for-byte
unchanged. Current 3→3 decode uses exact portable-schema validation; migrating
v1/v2 tentative decode remains additive and each historical wrapper
authenticates its frozen source graph.

Production proofs now use current target 3 while local one-step 1→2 registries
remain 1→2. Direct v2→3 and chained v1→2→3 preserve `.Driving`,
`.Libellula_Mk2`, story, structural, and sentinel state and resolve occupant
only to `.On_Foot`. The production OOM sweep traverses the real two-step chain.
A complete valid frozen-v2 payload relabeled as current v3 fails during exact
tentative decode with `.Tentative_Decode`, empty ownership, unchanged source
bytes, double-safe disposal, and zero outstanding allocations.

Locked verification:

- the B3 production-chain proof passes three consecutive runs in 11.017s,
  11.502s, and 10.899s, with zero leak diagnostics;
- `make fixture-migration-test` passes 6/6 in 3m33.422s with zero leak
  diagnostics;
- `make test` passes 513/513 with zero leak diagnostics;
- `make check`, source schema check, v1/v2/v3 history checks, and default 1→2
  plus explicit 2→3 scaffold checks pass;
- two read-only 1→2 reports are byte-identical at exactly 6,873 bytes and
  21/16/5 changes;
- two read-only 2→3 reports are byte-identical at exactly 1,236 bytes and
  2/1/1 changes;
- all nine locked hashes remain exact:
  - v1/v2/v3 manifests:
    `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`,
    `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`,
    and
    `210c2d82c27ac668bcdae75f18c5735726f7d88ca48609a8795bdaec56225b9f`;
  - v1/v2/v3 history:
    `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`,
    `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`,
    and
    `508e0c043c8886ff637132081f8fb27ec9b02a10a49142ec6dad1e0f20ba99bd`;
  - resolved 1→2 migration, occupancy production, and resolved 2→3 migration:
    `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`,
    `5a4aaa44103f3a829e61bdfa2c5da9aadd2f11feffd4c06c68f984a51828268a`,
    and
    `03548ce6ee56db59c54086756d37a1b48d120ebfc22298c8cb00be67287c720d`.

The focused codec target reaches both owned decode paths and passes 1/2. Its
sole failure is the B4C assertion in `src/fixture_codec_test.odin:524`, which
still requires migrated v1 re-encode container version 2 even though current
encoding correctly emits version 3. Per B4B scope, codec files remain
untouched. No generated binary, probe, or comparison artifact remains.

### Reviewer acceptance — 2026-07-29

M4B2B4B is accepted. Independent review confirms:

- production registry order and exact change IDs are pinned;
- current exact mode is limited to source/target/current version 3;
- v1/v2 migrations retain tolerant tentative decode plus exact frozen wrapper
  authentication;
- the complete valid v2-as-v3 proof fails before ownership escapes;
- direct v2 and chained v1 tests use the real production registry;
- story/structural success paths assert `.On_Foot`;
- production current and historical OOM sweeps target version 3.

Reviewer reruns pass the B3 proof in 10.516s with zero leaks and `make check`.
The focused codec target independently reproduces exactly 1/2 with the sole
stale line-524 `schema_version == 2` assertion after both decode paths
succeed. The generated `src.bin` was removed.

## Milestone 4B2B4C — Prove current and historical codec paths

Change only:

- `src/fixture_codec_test.odin`;
- `src/fixture_codec_oom_test.odin`;
- this plan.

Add no top-level test procedure and edit no production file.

Current v3 proof:

- encode container version 3;
- round-trip each exact occupant value: `.On_Foot`, `.Car`, `.Postale`,
  `.Libellula`, `.Libellula_Mk2`;
- preserve the serialized discriminator without deriving it from pointer or
  vehicle state;
- deterministic re-encode is byte-identical;
- result storage belongs to its arena, remains appendable, and disposes twice.

Direct v2→3 proof:

- encode a true `fixture_v0002.Fixture` with dynamic-array and sentinel state;
- set historical pilot `.Driving` and active aircraft `.Libellula_Mk2`;
- decode through the production codec;
- require occupant `.On_Foot` while Driving/Mk2 and sentinels survive;
- re-encode as schema 3 and prove arena ownership.

Chained v1→2→3 proof:

- use the accepted historical helper and real production registry;
- require `.On_Foot`, Driving/Mk2 preservation, all story/structural results,
  and deterministic schema-3 re-encode.

The existing codec OOM test must sweep current v3, true v2, and v1 containers
independently. Every failed allocation returns empty ownership, exact error
class, unchanged source bytes, double-safe disposal, and zero outstanding
allocations.

Final B4 gate:

- v1/v2/v3 schema and history checks;
- 1→2 report 6,873 bytes/21/16/5 twice;
- 2→3 report 1,236 bytes/2/1/1 twice;
- both scaffold checks and no-overwrite generation;
- migration 6/6;
- codec 2/2;
- `make check`;
- `make test` exactly 513/513, zero leaks;
- all seven old hashes and two new v3 hashes exact;
- no binaries, probes, or unplanned v3 artifacts.

Do not commit intermediate B4A/B states. Commit only after B4C restores every
gate to green.

### Verification status — 2026-07-29

M4B2B4C implementation and locked-Odin verification are complete.

The existing two focused codec tests now prove all three production source
versions without adding another top-level test. Current-schema encoding emits
version 3 and round-trips each exact occupant value: `.On_Foot`, `.Car`,
`.Postale`, `.Libellula`, and `.Libellula_Mk2`. Pilot mode, active aircraft,
and pointer state remain deliberately unchanged across that matrix, so each
decoded occupant is proven to come from the serialized discriminator rather
than inference. Every value re-encodes byte-identically, owns dynamic storage
through the result arena, remains appendable, preserves source state and
container bytes, and disposes twice safely.

The direct historical proof constructs a real frozen
`fixture_v0002.Fixture`, including one dynamic city-lamp marker,
`.Driving`, active `.Libellula_Mk2`, selection and string sentinels. Production
codec migration resolves only occupant to `.On_Foot`; all historical values
survive. Two independent decoded results re-encode as deterministic current
schema 3, the source container remains immutable, the dynamic marker is
arena-owned and appendable, and both results are double-disposable.

The chained proof uses the accepted B3 v1 payload helper containing
`.Driving` and active `.Libellula_Mk2`. The real production 1→2→3 registry
preserves those values plus project, city-plan, farm, story, quest-tracking,
and string sentinels; resolves occupant to `.On_Foot`; and deterministically
re-encodes as schema 3 with arena-owned appendable storage.

The OOM proof independently builds and sweeps current v3, true frozen v2, and
frozen v1 containers. Every injected allocation failure returns codec
`.Migration` with migration `.Out_Of_Memory`, empty result ownership,
unchanged source bytes, idempotent error/result disposal, and zero outstanding
allocations. The former misleading `v2` name for current data is now
`current`.

Locked gates:

- `make fixture-codec-test` passes exactly 2/2 twice in 51.544s and 52.946s,
  with zero leak diagnostics;
- the B3 named production-chain test passes 1/1 in 11.259s, with zero leak
  diagnostics;
- `make fixture-migration-test` passes exactly 6/6 in 3m28.609s, with zero
  leak diagnostics;
- `make test` passes exactly 513/513, with zero leak diagnostics;
- `make check` and `make fixture-schema-check` pass;
- v1, v2, and v3 history checks and package compilation pass;
- default 1→2 and explicit 2→3 scaffold checks plus no-overwrite generation
  pass;
- two read-only 1→2 reports are byte-identical at exactly 6,873 bytes with
  21/16/5 changes;
- two read-only 2→3 reports are byte-identical at exactly 1,236 bytes with
  2/1/1 changes;
- no generated binary, probe, report, or unplanned v3 artifact remains.

All nine locked hashes remain exact:

- v1/v2/v3 manifests:
  `2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12`,
  `0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2`,
  and
  `210c2d82c27ac668bcdae75f18c5735726f7d88ca48609a8795bdaec56225b9f`;
- v1/v2/v3 history:
  `e80c15bddcbd83a645ffa73ce40c28097604786cbb98e6292cd6c06529eab93c`,
  `8c0abae7cada8f7523d0c506d9ea35ce4041e661edbe775430b2243913f4ac91`,
  and
  `508e0c043c8886ff637132081f8fb27ec9b02a10a49142ec6dad1e0f20ba99bd`;
- resolved 1→2 migration, occupancy production, and resolved 2→3 migration:
  `82ff1c0702ee72090aa9e355a14a537ced817361c9e66a08a60eabf0a6f5cd76`,
  `5a4aaa44103f3a829e61bdfa2c5da9aadd2f11feffd4c06c68f984a51828268a`,
  and
  `03548ce6ee56db59c54086756d37a1b48d120ebfc22298c8cb00be67287c720d`.

### Reviewer acceptance — 2026-07-29

M4B2B4C and the complete B4 activation chain are accepted. Independent review
confirms the isolated B4C diff changes only the two authorized codec tests and
this plan, retains exactly two top-level codec tests, constructs true frozen
v2 and v1 inputs, and edits no production code. Reviewer
`make fixture-codec-test` passes 2/2 in 50.893s with zero leak diagnostics.
No generated binary remains.

The fixture change is ready to commit and rebase onto current main before any
milestone 4C work starts.

## Milestone 4R — Activate rebased schema version 4

Current main changes the live fixture graph while frozen schema version 3 must
remain immutable. Complete every 4R slice in one Jujutsu change and commit only
after the final registry/codec gates are green. Never commit a source-under-v3,
version-bump-only, manifest-only, history-only, unresolved-scaffold, or
partially registered state.

### Milestone 4R1 — Support enum-indexed portable arrays

Teach the generic portable codec to encode, decode, describe, and validate
Odin `[Enum]T` arrays with the same contiguous element bytes as fixed arrays
while preserving their distinct reflected type identity.

Acceptance:

- `[story.Resident]u64` round-trips deterministically;
- reflected enum index metadata, element type, count, width, and bounds are
  validated before reading or writing elements;
- malformed, gapped, duplicate, forged, width-mismatched, and truncated inputs
  fail with exact paths and no destination mutation;
- encoding and decoding allocate a constant number of times independent of
  element count;
- nil allocator, every allocation failure, error ownership, double disposal,
  cycle/depth behavior, and zero leaks remain proven;
- the existing 34-byte owned error-path leak is fixed;
- existing portable fixed/dynamic array wire behavior remains byte-identical.

Change only `packages/hs/portable.odin`, `tests/hs_portable_test.odin`, and this
plan.

#### M4R1 acceptance — 2026-07-29

M4R1 is accepted. `Portable_Kind` values 0–10 remain exact and the new
enum-indexed-array kind is appended at 11. The portable type table records both
element and enum-index handles; discovery, graph validation, exact decode,
tolerant decode, skip, and encode all validate the reflected enum range.

Hostile proofs cover reordered and negative-minimum indices, sparse/duplicate
metadata, forged base kind, signedness and width, truncation, nil allocators,
sticky and one-shot OOM, error double disposal, and unchanged destinations.
Independent review found no remaining correctness, ownership, or wire
compatibility blocker after repairs.

- focused portable tests pass 3/3 with zero leaks;
- `make fixture-codec-test` passes 2/2 with zero leaks;
- `make check` passes;
- `make test` passes Rondine 19/19 and the main suite 617/618; the sole failure
  is the expected frozen-v3 schema sentinel;
- no generated binary remains.

### Milestone 4R1H — Preserve enum-indexed history identity

The live schema walker must not collapse Odin `[Enum]T` into `[N]T`. M4R1
intentionally gives these reflected types distinct portable wire identities,
so a collapsed v4 history package would make every future v4→v5 historical
decode fail before its migration script runs.

Add the backward-compatible manifest form
`enumerated_array[N;logical-id]<element>`. The count keeps storage-size changes
state-bearing; the logical enum ID lets history generation emit
`[History_Type_NNNN]Element` and reproduce the original reflected type.

Acceptance:

- the source walker retains the validated dense enum count and logical ID;
- the strict history parser validates syntax, caps, index existence, enum kind,
  uniqueness, contiguity, and count before accepting a manifest;
- history emission reproduces an Odin enum-indexed array;
- schema diff validation and reachability traverse both index and element;
- malformed, missing, non-enum, count-mismatched, duplicate, and gapped index
  metadata fail closed with correct ownership and paths;
- ordinary `array[N]<T>` and all frozen v1/v2/v3 manifests/history packages
  remain byte-identical;
- the corrected missing-target 3→4 report remains exactly 119/100/19 and
  1,611 lines, 167 records, and 154 root fields.

#### M4R1H acceptance — 2026-07-29

M4R1H is accepted. The source manifest now records
`enumerated_array[count;logical-id]<element>`, and the history emitter restores
the enum index type instead of a numeric fixed array. Independent review found
no grammar, caps, overflow, reachability, ownership, diagnostic, or wire
identity defect.

- focused walker/history/diff proofs pass 3/3 with zero leaks;
- v1/v2/v3 history checks pass twice and their generated-source hashes remain
  exact;
- `make check` passes;
- `make test` passes Rondine 19/19 and the main suite 619/620; the sole failure
  is the expected frozen-v3 schema sentinel;
- corrected 3→4 reports are byte-identical at 43,600 bytes with report SHA-256
  `952f230dc3402e8429a23dd8940fca05eb7bd35a507c0f2b8c24005b3503509c`;
- corrected candidate SHA-256 is
  `52e66006f47b8e01db1201356959e9d8bd6871e4584d589117a8959323be5d99`;
- report shape remains exactly 119/100/19 and 1,611 lines, 167 records, and 154
  root fields;
- no v4 artifact or generated binary remains.

### Milestone 4R2 — Finalize the v4 source graph and report

Append stable `vehicles.Fixture_Occupant.Rondine = 5`; keep values 0–4 exact.
Derive `.Rondine` only from a distinct, internally consistent Rondine driver
graph with active aircraft `.Rondine`. All aliases, nils, foreign drivers,
wrong active kinds, and stray links fail without mutation.

Extend schema retention/exclusion sentinels for all rebased root fields. Run
the missing-target 3→4 report twice before bumping the source version.

Acceptance:

- report is byte-identical twice;
- exactly one change is added to the audited baseline:
  `Fixture_Occupant.Rondine`;
- final pre-freeze report is 119 changes: 100 state and 19 supporting;
- candidate has 1,611 lines, 167 records, and 154 root fields;
- no manifest, history package, scaffold, or source-version bump exists yet.

#### M4R2 acceptance — 2026-07-29

M4R2 is accepted on the corrected enum-array schema grammar.
`Fixture_Occupant.Rondine = 5` is appended without changing values 0–4.
Derivation accepts only the exact reciprocal, distinct Rondine graph with no
stray driver and active aircraft `.Rondine`. Independent review found the
production branch and all rebase retention/exclusion sentinels clean; two
missing negative proofs were added and pass.

- occupancy focused proof passes 1/1 with zero leaks;
- product fixture codec passes 2/2 across all six occupant values;
- final production occupancy SHA-256 is
  `4b7663518510eef90a78d8d0c766fe4b15af343073a4397d5d2420d39c12fde5`;
- the only report delta from the audited 118-change baseline is
  `Fixture_Occupant.Rondine`;
- the final provisional v4 candidate and report hashes/counts are those
  accepted in M4R1H;
- source schema version remains 3 and no v4 manifest, history, scaffold, or
  migration exists.

### Milestone 4R3 — Freeze v4 schema, history, and scaffold

Bump `FIXTURE_SCHEMA_VERSION` from 3 to 4 only after 4R2 is accepted. Generate
and freeze `v0004.fixture-schema`, then generate and freeze the v4 historical
package. Generate the 3→4 scaffold only after both v3 and v4 are immutable.

Acceptance:

- v4 manifest and history package generate twice byte-identically and compile;
- v1/v2/v3 hashes and both resolved old migration hashes remain exact;
- frozen-target tooling prefers v4 and never falls back from malformed v4;
- 3→4 report stays exactly 119/100/19;
- scaffold imports frozen v3, contains exactly 100 sorted unresolved
  obligations, excludes 19 supporting changes, is odinfmt-clean, and refuses
  overwrite;
- schema, diff, history, and scaffold tests pin new counts and hashes.

#### M4R3 acceptance — 2026-07-29

M4R3 is accepted. Source schema version 4 is active. The manifest, historical
package, and unresolved scaffold were generated in the required order,
regenerated byte-identically, and independently reviewed against the frozen
report.

- v4 manifest SHA-256 is
  `fad52f4e0a38b35fffdf29ae3ffb3f91251780fe0ce2dc5990beba76f1e518fa`;
  it has 1,611 lines, 167 records, and 154 root fields;
- v4 history SHA-256 is
  `bc483f9afa929fd697868627ad8b0a7b46e03be61edb88670bc46825ec0a1076`;
  it has 2,110 lines and 167 history IDs, compiles, and reflects
  `resident_action_seen` as an enum-indexed array;
- unresolved 3→4 scaffold SHA-256 is
  `95d4d1b6e1b1d5b095f88e76ace11a8ee8fee0073a82c6be30d06218029ebf90`;
  it contains exactly 100 sorted state obligations and no supporting change;
- frozen 3→4 report remains 43,600 bytes and 119/100/19 with activated report
  SHA-256
  `563bd70951b04b72935f861866db973f8f2642debd016235192c6d637afc0f76`;
- v1/v2/v3 manifest and history hashes, both old migration hashes, and the
  occupancy hash remain exact;
- four focused production tests and the tool matrix pass with zero leaks;
- `make check`, schema, histories v1–v4, scaffold, and full tests pass;
  the full suite is 622/622 plus Rondine 19/19;
- diagnostic codec and migration targets fail only at the deliberately
  unresolved and unregistered 3→4 boundary;
- independent artifact review is clean and no generated binary remains.

### Milestone 4R4 — Resolve the 3→4 scripted migration

Implement one zero-allocation common transformation with exact frozen-source
adapters. Split proofs into independently reviewable slices:

1. enum mappings: preserve appended enums, remap shifted shoreline/tool/
   settlement-failure values by name, reject forged discriminants;
2. structural defaults: city alleys, terrain entrances, brush-radius
   replacement, flight/Postale replacements, story expansion, and derived tail
   discard;
3. root defaults: farm yaw, authored wreck state, deterministic locked Rondine
   runtime/visibility, and stable occupant preservation;
4. settlement compatibility: validate all counts, widen routes 48→320,
   preserve old state, zero new ownership/program/activity/diagnostic fields,
   and never rerun mutable generation;
5. exact v1/v2/v3 adapters, direct and chained execution, hostile atomic
   failures, and allocation-failure sweeps.

Ambiguous policies are scripted and pinned:

- old settlement brush radius maps to `.Circle` plus `.Small` below 45,
  `.Medium` below 85, otherwise `.Large`; non-finite or negative input fails;
- new Postale aerodynamic fields use frozen product defaults, not future
  constructors;
- old valid settlement plans stay valid with unavailable new diagnostics;
- `Settlement_Request.density` initializes to zero, never from network density;
- derived mouse-tail state is discarded;
- new wreck authoring state is `paint=false`, brush size `330`, yaw `0`, an
  empty zeroed array, and count `0`;
- migration requires exactly three old fleet slots, one each Postale,
  Libellula, and Libellula Mk2, with a present active kind, then appends exact
  slot `{kind=.Rondine, name="Rondine", available=false,
  vehicle=nil}`; new Rondine runtime data is frozen literal zero state with its
  vehicle locked and visibility false, while the old active kind and occupant
  are preserved and Rondine is never inferred as occupant.

Common apply allocates zero times. Preparation owns all allocations, validates
before mutation, preserves source bytes, and is double-disposable and
leak-free under every OOM point.

#### M4R4 obligation audit — 2026-07-29

The frozen scaffold partitions exactly as follows:

- 34 enum obligations: appended building, landmark, resident, aircraft,
  occupant, and mouse-accessory values preserve the old numeric domain;
  shoreline `0..4` maps to `1..5`; authoring-tool `0..9` stays and `10..12`
  maps to `11..13`; settlement-failure `0..4` stays and `5..16` maps to
  `6..17`;
- 26 structural obligations: all city alleys get zero controls/demand,
  `.None` terminals, and `curve_ready=false`; airframes get literal
  `parasitic_drag_area=1.33`; new Postale runtime fields are zero; story
  additions are zero; every terrain structure entrance is `.Front`; removed
  flight/Postale/tail fields are discarded; the old brush radius performs the
  locked shape/preset conversion;
- eight root obligations: farm yaw, literal locked/hidden Rondine state, and
  the five frozen wreck-authoring defaults;
- 32 settlement obligations: 31 additions initialize to zero and routes widen
  from 48 to 320 while preserving every old slot and zeroing the tail.

Migration validates all serialized carriers, including inactive fixed-array
slots. Settlement preflight bounds are neighborhoods 96, macro sites 192,
routes 48, blocks 128, sites 256, rejected sites 32, decorative foliage 32,
terrain edits 192, purposes 256, route geometry points 12, and block corners
8. Relevant scalar counts and statistics must be nonnegative.

The implementation order is enum validation/remap, structural conversion,
root defaults, settlement conversion, then exact v1/v2/v3 adapters. Each
partial slice may leave later resolution entries `.Unresolved`, but it must
mark only obligations it implements and return the first remaining exact
change ID. No partial slice is registered.

#### M4R4.1 acceptance — 2026-07-29

The enum slice is accepted. Exactly 34 enum obligations are `.Scripted`; 66
remain `.Unresolved`, and the first remaining ID is
`field-add:adriatic:packages/architecture.City_Alley.curve_control_from`.

The script validates all frozen v3 carriers before mutation, including both
dynamic structure arrays, every inactive settlement structure slot, all eight
aircraft slots, and every root enum carrier. Shifted enums are overwritten
from the historical value; appended enums preserve the old numeric domain.
The apply step allocates zero times and returns the first unresolved structural
ID only after the enum mutation completes.

- production script SHA-256 is
  `0229fc88d3431b788a36344fc2c3aa82b07748314c2aed14c43668784c2be3ab`;
- direct focused proof passes twice with zero leaks;
- hostile proofs cover high and signed forged values for all nine domains,
  both building enums in all five carrier families, full validation order,
  atomic root and dynamic-backing snapshots, and destination length mismatch;
- scaffold validation passes at exactly 34/66/0;
- `make check`, schema, histories v1–v4, report, scaffold, and full tests pass;
  the full suite remains 622/622 plus Rondine 19/19;
- independent re-review is clean and no binary remains.

#### M4R4.2 acceptance — 2026-07-29

The structural slice is accepted. Exactly 26 more obligations are scripted,
leaving the scaffold at 60 Scripted / 40 Unresolved / 0 Automatic. The first
remaining ID is `field-add:adriatic:src.Fixture.farm_brush_yaw`.

All enum and structural preflights complete before either apply step. The
composition preserves the accepted R4.1 diagnostic contract: project/city
destination length mismatches return the archetype ID, while alley length and
brush-radius failures return structural IDs. An independent review caught and
repaired a temporary ordering regression before acceptance.

- production script SHA-256 is
  `90c8b90e7698d35b6b5a42f55856fa4498700c52171b405edea8421d3200b5b9`;
- both airframes receive literal drag area `1.33`; all new Postale, story,
  alley, and entrance fields receive their locked defaults; removed runtime,
  tuning, brush-radius, and tail state is consumed or discarded;
- radius boundary, NaN/Inf/negative, dynamic-length, full composed enum
  failure, inactive carrier, unrelated-field preservation, and zero-allocation
  proofs pass;
- enum and structural focused tests pass 2/2 twice with zero leaks;
- scaffold validation passes at 60/40/0;
- `make check`, schema, history, report, scaffold, and full tests pass; the
  full suite remains 622/622 plus Rondine 19/19;
- final graph re-review is clean and no binary remains.

#### M4R4.3 acceptance — 2026-07-29

The root-default slice is accepted. Exactly eight more obligations are
scripted, leaving the scaffold at 68 Scripted / 32 Unresolved / 0 Automatic.
The first remaining ID is
`field-add:adriatic:src.Settlement_Metrics.dead_end_frontage`.

All enum, structural, and root preflights complete before any apply step.
Historical fleet state must contain exactly three active-range slots, one each
of Postale, Libellula, and Libellula Mk2, with the active kind present. The
apply step preserves those slots and the old active kind and occupant, appends
the exact unavailable Rondine slot, installs the literal locked and hidden
Rondine runtime, and initializes farm yaw and authored wreck state to their
frozen defaults.

- production script SHA-256 is
  `f1a8cb1a052faad6d41b73d5b7da8fa7f171a2ffbcd6022858b96b7cd12897e2`;
- all six historical fleet permutations, every old occupant, active variants,
  exact preserved slot bytes/string headers, untouched tail slots, and frozen
  Rondine/wreck byte oracles are pinned;
- hostile proofs cover counts, destination mismatch, duplicate/missing kinds,
  absent active kind, nil input, and simultaneous earlier/root failures with
  exact diagnostic precedence and atomic snapshots;
- enum, structural, and root focused tests pass 3/3 twice with zero leaks and
  the composed apply step allocates zero times;
- scaffold validation passes at 68/32/0;
- `make check`, schema, histories v1–v4, report, scaffold, and full tests pass;
  the report remains 43,600 bytes and 119/100/19, while the full suite remains
  622/622 plus Rondine 19/19;
- independent production and proof review is clean and no binary remains.

#### M4R4.4 acceptance — 2026-07-29

The settlement slice is accepted. All remaining 32 obligations are scripted,
leaving the scaffold at 100 Scripted / 0 Unresolved / 0 Automatic. The full
common v3→v4 transformation now succeeds after completing enum, structural,
root, and settlement preflights before any mutation and applying those slices
in the same order.

The frozen v3 plan is the route oracle. All 48 route slots are converted
field-by-field with validated enum casts, including inactive slots, and the
new 272-slot tail is zeroed. The 31 new settlement fields receive exact
literal-zero defaults; request density is never derived from network density.
All old plan state remains untouched except the scripted delta, and generation
is never rerun.

- production script SHA-256 is
  `abb7ba79049fd12096a7779eaa1281189913acc0a78e9afe567b3cb4d24b4e3d`;
- preflight validates all nine bounded source counts and matching destination
  counts, every fixed route and block nested count, all 30 historical scalar
  statistic counts, metric counters, and every settlement enum carrier;
- hostile proofs cover both bounds of every count family, inactive last-slot
  corruption, all nine destination mismatches, nil input, and simultaneous
  earlier-phase failures with exact diagnostic precedence and atomic
  snapshots;
- independent assertions pin all 31 defaults, every field of all 48 converted
  routes, the full zero tail, and untouched old settlement state;
- the focused enum, structural, root, and settlement suite passes 4/4 twice
  with zero leaks, and the complete apply step allocates zero times;
- scaffold validation passes at 100/0/0 and the resolved migration returns
  success;
- `make check`, schema, v4 history, scaffold, report, and full tests pass; the
  report remains 43,600 bytes with SHA-256
  `563bd70951b04b72935f861866db973f8f2642debd016235192c6d637afc0f76`,
  while the full suite remains 622/622 plus Rondine 19/19;
- codec and registered migration targets still stop at the expected
  unregistered 3→4 boundary owned by M4R4.5;
- independent production and repaired-proof review is clean, and no generated
  binary remains.

#### M4R4.5 acceptance — 2026-07-29

The exact source adapter is accepted without activating the production
registry. Direct version 3 sources exact-decode their frozen graph. Chained
version 1 and 2 sources exact-authenticate the original payload, encode the
already-migrated tentative state, tolerant-decode that projection into a fresh
frozen-v3 oracle, restore the removed brush radius from the authenticated
source, and call the single common v3→v4 transformation.

The projection scratch arena is disjoint from the transaction arena. No
scratch pointer escapes, no business rule is duplicated, and the original
payload remains immutable. The wrapper accepts a later target so it remains a
valid interior step in future chains, while production registry length stays
two until M4R5.

- runtime wrapper SHA-256 is
  `37c7c4dbcbba26b124f697a4e8e8313d9e1942393423e5f4d0cc0f62eef9f6c9`;
- portable writer OOM classification now distinguishes table, body, payload,
  and exact-schema re-emission allocation failures from genuine payload limits
  and schema mismatches; production portable SHA-256 is
  `50fd898be7ce6966c4676ad778bf606f770dd9a01cdc0493ae81b0d5d772133a`;
- direct v3, chained v2→3→4, and chained v1→2→3→4 preserve prior migrated
  farm, story, occupant, dynamic-array, string, and settlement state before
  applying all v4 defaults and remaps;
- hostile proofs cover invalid contexts and arenas, exact-source truncation and
  mismatch, original-radius recovery, settlement and fleet failures, earlier
  step precedence, payload immutability, and atomic whole-state snapshots;
- wrapper-only and full-runner OOM sweeps pass for original source versions 1,
  2, and 3 with empty failures, double disposal, and zero leaks;
- returned dynamics remain transaction-owned after scratch destruction and
  accept an append;
- adapter-focused tests pass 3/3 twice and portable writer tests pass 2/2
  twice, all with zero leaks;
- `make check`, schema, histories v1–v4, scaffold, report, and full tests pass;
  the full suite is 623/623 plus Rondine 19/19;
- the common transform hash remains
  `abb7ba79049fd12096a7779eaa1281189913acc0a78e9afe567b3cb4d24b4e3d`;
- codec and registered migration targets still stop only at the intentionally
  unregistered 3→4 boundary;
- independent adapter and writer re-review is clean, and no generated binary
  remains.

### Milestone 4R5 — Activate registry and codec through v4

Append exact registry step 3→4 without changing frozen 1→2 or 2→3 sources.
Current 4→4 decode uses exact schema validation. Historical v1/v2/v3 paths
authenticate their own frozen source graphs and execute strict ordered chains.

Acceptance:

- direct v3, chained v2 and v1, and current v4 paths pass;
- current codec round-trips all six occupant values, including Rondine 5;
- story enum-indexed array state survives exact deterministic round-trip;
- per-source OOM, immutable input, append ownership, error disposal, and atomic
  failure proofs pass with zero leaks;
- fixture schema/history/scaffold/report/check gates pass;
- full project tests pass;
- all old hashes and new v4 hashes are exact;
- no generated binaries, probes, or unplanned artifacts remain.

#### M4R5 acceptance — 2026-07-29

Schema version 4 is fully active. The production registry is the exact
contiguous chain `1→2→3→4`; the first two entries remain unchanged and the
third uses the accepted frozen-v3 adapter and resolved common transformation.
No fixture codec or container production change was needed.

- production migration runtime SHA-256 is
  `fc8d362ffd11d3e8b57bff21eb21088eada753ad07a97046adc9305c3fe5ede1`;
- current 4→4 decode exact-validates and invokes no migration wrapper;
- direct v3, chained v2 and v1, and current v4 production paths all pass and
  match the independent custom-registry oracle;
- current fixture round-trip covers all six occupant values and preserves two
  distinct entries in the enum-indexed resident action array;
- codec OOM sweeps cover source versions 1, 2, 3, and 4 with immutable inputs,
  empty failures, double disposal, and zero leaks;
- production migration tests pass 9/9 twice and codec tests pass 2/2 twice,
  all with zero leak output;
- `make check`, schema, histories v1–v4, scaffolds, deterministic reports, and
  full tests pass; the full suite is 623/623 plus Rondine 19/19;
- the 3→4 report remains 43,600 bytes with SHA-256
  `563bd70951b04b72935f861866db973f8f2642debd016235192c6d637afc0f76`;
- all frozen manifest, history, old migration, common 3→4, adapter runtime,
  portable, codec, and occupancy hashes remain exact;
- independent activation review is clean, and no binary or probe remains.

## Milestone 4C — Share detach and pointer rebind lifecycle

Extract one product-local lifecycle contract used by hot reload and fixture
load:

1. derive/validate stable serializable relationship identity;
2. detach pointer-only links on a copied fixture;
3. bind decoded identity to addresses inside the live `Editor`;
4. reset invalid active sessions rather than preserving borrowed pointers.

Rebind aircraft slots by kind to live Postale/Libellula/Rondine vehicles, then
restore pilot/driver links from the schema-4 occupant discriminator. Reject duplicate,
missing, out-of-range, locked, or internally contradictory fleet/occupancy
state before live mutation. Hot save must stop maintaining a separate pointer
nil list, and hot load must call the same binder as fixture load.

### M4C locked relationship policy — 2026-07-29

Implement one product-local, allocation-free lifecycle boundary:

1. validate the exact live four-kind fleet and derive occupant identity from
   the reciprocal live pointer graph;
2. shallow-copy the source fixture into caller-owned scratch, write the
   derived identity, and detach all relationship pointers from the copy without
   mutating the source;
3. preflight a decoded fixture with no mutation, requiring exact unique
   Postale, Libellula, Libellula Mk2, and Rondine slots, a present valid active
   kind, nil borrowed pointers, a valid occupant, and an unlocked occupied
   physical vehicle;
4. bind only destination-owned addresses, preserving slot order, names,
   availability, active kind, and all other serialized state.

Libellula and Libellula Mk2 intentionally share the one Libellula vehicle;
active kind disambiguates their occupant identity. Other physical vehicles
must be distinct.

For detached state, the stable occupant discriminator is authoritative and the
binder canonicalizes `pilot.mode`. This is required because accepted v1/v2
migrations produce `.On_Foot` identity while preserving an old `.Driving`
mode. A fully live graph is validated by deriving its identity; stale
`Fixture.occupant` never invalidates save because production did not previously
maintain it.

Availability remains durable authored state but is not a bind policy. Only the
occupied physical vehicle's `locked` flag rejects restoration. This avoids
inventing an invariant not guaranteed by frozen histories.

Malformed, missing, duplicate, out-of-range, hybrid, foreign, locked, or
contradictory relationship state fails before the first mutation. Hot load
returns `.Invalid`, and its existing caller restarts cleanly. Fixture load will
reject before install. Broad physics, audio, dialogue, cinematic, input, and
resource rebuilding remains M4D.

M4C does not add fixture file/editor actions. It replaces only the duplicated
hot-save pointer nil list and fleet-only hot-load repair with the shared
derive/detach/bind contract.

### M4C acceptance — 2026-07-29

M4C is accepted on the seventh rebased baseline.

- one allocation-free lifecycle derives live occupant identity, detaches a
  copied fixture, prepares a pointer-free bind plan, and applies it using only
  destination-owned addresses;
- strict preflight rejects invalid counts, forged kinds and discriminants,
  duplicate or missing fleet kinds, borrowed or foreign pointers, partial
  reciprocal graphs, active-kind mismatches, and locked occupied vehicles
  before relation mutation;
- Libellula and Libellula Mk2 retain their intentional shared physical vehicle,
  slot order/name/availability remain durable, and historical
  `On_Foot`/`Driving` disagreement canonicalizes from the occupant identity;
- hot save uses the shared detach boundary, hot load uses the shared bind
  boundary, the permissive three-slot repair path is removed, and the old
  relation-specific pointer nil list no longer exists;
- focused lifecycle tests pass 4/4 twice with one test thread and zero leak
  diagnostics, covering all six identities, hostile atomic failures,
  destination ownership, authored availability, and valid plus malformed hot
  files;
- `make check`, histories v1–v4, scaffold checks 1→2/2→3/3→4, deterministic
  historical reports, and Rondine 19/19 pass;
- independent lifecycle review is clean, `src/main.odin` contains only the
  four intended integration hunks, and no generated binary or probe remains.

The seventh rebase moved fixture change `mwytpkmk` from main parent
`vxzsozzw` (`Add settlement brush planning tools`) to `vxzsuvoltqks`
(`chore: ignore local imgui settings`), bringing in the ACE flight/story
rewrite. This is a separate schema boundary: frozen v4 first differs at
manifest line 196, where live discovery introduces `flight.Ace_Edge_State`
before the expected `flight.Airframe`. Consequently schema check fails,
codec tests stop 0/2 at current-schema validation, migration tests pass only
the registry-rejection case 1/9, and the full repository suite is 743/744
with only the frozen-schema assertion failing; Rondine remains 19/19. M4C
does not alter or regenerate schema, history, codec, or migration artifacts.

## Milestone 4R6 — Reconcile seventh-rebase fixture schema

Before M4D, audit the complete frozen-v4-to-live candidate diff introduced by
the ACE flight/story rewrite. Classify every new reachable field as durable,
derived, or session-owned. Then activate the next schema version and migration
using the existing manifest, history, diff, scaffold, registry, and codec
workflow. Frozen versions 1–4 and migrations 1→2, 2→3, and 3→4 remain
immutable.

Do not begin M4D until current-schema encode/decode, every historical chain,
schema/history/scaffold checks, and the full test suite are green again.

### M4R6A read-only audit — 2026-07-29

The current source candidate is 1,658 lines, 172 records, and 154 root fields,
with SHA-256
`7d0ec2be99a2cbdf53ec6ee3caa7c7ea86cda5d9a287d8e194106d29ba34762b`.
Frozen v4 remains 1,611 lines, 167 records, and 154 root fields, with SHA-256
`fad52f4e0a38b35fffdf29ae3ffb3f91251780fe0ce2dc5990beba76f1e518fa`.

The production `migration-diff 4 5` command cannot yet produce the semantic
report. It deterministically fails at manifest line 279, path
`adriatic:packages/flight.Body_State.orientation`, because the extractor emits
`builtin:quaternion128` while the strict history/diff scalar grammar does not
recognize quaternion builtins. Scaffold generation fails at the same boundary.
This field is durable simulation state and must not be excluded to bypass the
tooling gap. `hs.portable` independently lacks runtime quaternion support, so
manifest recognition alone will not restore fixture codec gates.

A disposable parser-recognition probe, removed after the audit, exposes the
pre-policy 4→live report:

- 9,098 bytes, SHA-256
  `edf30613795c0711c39efd3f82d7da68bd21589336f722cb367d8d8861f8336b`;
- 19 changes: 14 state changes and five supporting type additions;
- the temporary unresolved scaffold is 76 lines and 2,405 bytes, SHA-256
  `378cc8036c9af1a44175d1833752e645c01c3b7e9830cdbebbb1a798fb3a48fd`.

The 14 state obligations are:

1. add `flight.Body_State.angular_velocity_world`;
2. add `flight.Body_State.orientation`;
3. add `libellula.Runtime.spawn_orientation`;
4. add `postale.Runtime.ace_runtime`;
5. add `postale.Runtime.ace_telemetry`;
6. add `postale.Runtime.ace_tuning`;
7. add `postale.Runtime.flight_model`;
8. add `postale.Runtime.spawn_orientation`;
9. change `flight.Body_State` field order/shape;
10. replace the Libellula spawn field at its existing position;
11. remove `flight.Body_State.angular_velocity`;
12. remove `flight.Body_State.basis`;
13. remove `libellula.Runtime.spawn_basis`;
14. remove `postale.Runtime.spawn_basis`.

The five supporting additions are `flight.Ace_Edge_State`,
`flight.Ace_Runtime`, `flight.Ace_Telemetry`, `flight.Ace_Tuning`, and
`postale.Flight_Model`.

State policy is locked before v5 generation:

- keep body pose, velocity, world angular velocity, and orientation for all
  aircraft;
- migrate old body basis with `flight.orientation_from_basis` and copy old
  angular velocity directly to `angular_velocity_world`;
- migrate Postale and Libellula spawn basis to spawn orientation;
- keep Postale `flight_model`, all 22 `ace_tuning` controls, and
  `ace_runtime.energy`, `edge_state`, and `edge_seconds`;
- historical Postale defaults are `.Current_Aero`, the exact
  `postale.ace_tuning_preset()`, and zero/`.Free`/zero ACE runtime state;
- exclude `Ace_Runtime.local_rate`, which is recomputed from orientation and
  world angular velocity before use;
- exclude Postale ACE telemetry plus existing Postale and Libellula telemetry;
- retain Rondine telemetry for now because its prior-frame forward speed and
  drift intensity affect the next step;
- exclude the pre-existing `camera_target_lock` capture-session flag;
- keep existing durable story fields; the story additions were already
  resolved and frozen in v4.

### M4R6A1 — Add quaternion manifest/history support

This is the next implementation slice. It changes only the strict schema
manifest/history/diff/scaffold layer and its focused tests.

1. Prove supported Odin spellings with a disposable compile probe before
   editing.
2. Extend the shared strict scalar grammar with exactly the quaternion builtins
   accepted by the source extractor (`quaternion64` and `quaternion128`).
   Preserve their exact widths and keep them invalid as enum bases.
3. Ensure validation, reachability, semantic diff, history emission, and
   scaffold rendering accept these builtins in fields and nested fixed/dynamic
   arrays without relaxing logical-ID or malformed-type checks.
4. Add hostile spelling/width/nesting tests, exact source-line/path errors,
   nil allocator and OOM/error-disposal coverage, and generated-history compile
   proof.
5. Make the real `migration-diff 4 5` command produce the deterministic
   pre-policy 9,098-byte, 19/14/5 report and make temporary 4→5 scaffold
   generation/check deterministic. Do not retain the scaffold or any v5
   manifest/history package.
6. Keep `Portable_Kind` and `hs.portable` unchanged; runtime quaternion wire
   support is M4R6A2.

Acceptance requires the focused history, diff, and scaffold tests, their
existing OOM sweeps, `make check`, histories v1–v4, old scaffolds/reports, and
all frozen hashes. Current schema, codec, migration, and full-suite failures
remain expected until later M4R6 slices.

#### M4R6A1 acceptance — 2026-07-29

M4R6A1 is accepted. The only production change adds a distinct quaternion
scalar classification with exact `quaternion64` width 8 and `quaternion128`
width 16. Quaternion fields still require the canonical `builtin:` prefix,
unknown widths and raw spellings fail at exact source paths, and quaternion
remains invalid as an enum base. Existing history emission, semantic diff, and
scaffold code require no special cases beyond the shared scalar grammar.

- disposable syntax and generated-history compile proofs pass under the locked
  Odin compiler and leave no artifact;
- four new focused tests pass 4/4 twice, the full history/diff/scaffold set
  passes 37/37, and all report zero leaks;
- parser fault injection covers every allocation, nil allocator, double
  disposal, exact error paths, nested arrays, reachability, and exact emitter
  spelling;
- the production 4→5 report now succeeds twice at 9,098 bytes, SHA-256
  `edf30613795c0711c39efd3f82d7da68bd21589336f722cb367d8d8861f8336b`,
  with exactly 19 changes split 14 state and five supporting;
- the temporary unresolved scaffold generates/checks at 76 lines and 2,405
  bytes, SHA-256
  `378cc8036c9af1a44175d1833752e645c01c3b7e9830cdbebbb1a798fb3a48fd`,
  with exactly 14 unresolved IDs and byte-identical `odinfmt` output;
- `make check`, histories v1–v4, all legacy scaffolds/reports, and their frozen
  hashes pass unchanged;
- the full suite is 747/748 plus Rondine 19/19; the sole failure remains the
  expected frozen-v4/live-schema mismatch;
- independent review is clean, and no binary, probe, v5 manifest/history
  package, or scaffold remains.

### M4R6A2 — Add portable quaternion wire support

Append quaternion support to the portable `hs` wire format without changing
any existing `Portable_Kind` numeric value or old encoded byte stream.

1. Probe Odin runtime type information for `quaternion64` and
   `quaternion128` before editing; record component type, size, alignment,
   component offsets/order, and the exact `rt.Type_Info_Quaternion` shape.
   Locked Odin exposes no quaternion count query or variant payload, so the
   exact built-in type ID, element type, total size, alignment, and four raw
   component offsets form the supported shape proof.
2. Append one `Portable_Kind.Quaternion` value. Encode its exact total width
   and require four homogeneous floating-point components. Support only
   quaternion64 and quaternion128; reject unsupported widths or malformed
   runtime/type-table combinations.
3. Write and read the four components in canonical component order using the
   existing little-endian float-bit policy. Never raw-copy host padding or
   depend on host endianness. Preserve every float bit pattern exactly.
4. Treat quaternion as a leaf in shared graph discovery, cycle validation,
   encode/decode, skip/unknown-field handling, schema validation, limits, and
   fixed/enumerated/dynamic array traversal.
5. Add exact byte fixtures for both widths, nested struct and all array forms,
   additive/removed-field compatibility, source/destination type or width
   mismatch, forged kind/width/signed/reserved metadata, trailing table bytes,
   truncation/trailing body data, nil allocator, OOM/error ownership, double
   disposal, deterministic re-encode, and constant allocation count across one
   versus many array elements. Quaternion leaf records contain no serialized
   count or child metadata.
6. Keep schema manifests/history/migrations, fixture policy tags, and current
   schema version untouched. Current fixture codec remains blocked by the
   frozen-v4 mismatch until the policy/freeze slices.

Acceptance requires focused portable tests twice with zero leaks,
`make check`, the M4R6A1 4→5 report/scaffold hashes, histories v1–v4, and all
old portable/schema/migration hashes unchanged except the intentionally edited
portable source and tests.

#### M4R6A2 acceptance — 2026-07-29

M4R6A2 is accepted. `Portable_Kind.Quaternion` is appended at value 12, leaving
all prior kind values and old wire bytes stable. Runtime discovery accepts only
the exact built-in `quaternion64` and `quaternion128` types, with f16/f32
elements, widths 8/16, alignments 2/4, and the raw component order
`imag`, `jmag`, `kmag`, `real`.

- encoding writes every component bit pattern explicitly in little-endian
  order; decoding reads the full 8- or 16-byte leaf before mutating any
  destination component;
- shared discovery, graph validation, exact table emission/parsing, skip,
  compatibility, fixed/enumerated/dynamic array, and mismatch paths all treat
  quaternion as a leaf;
- four focused tests pass 4/4 twice after formatting with zero leaks, covering
  exact q64/q128 bytes, NaN/sign/infinity bit preservation, nested and all array
  forms, added/removed fields, q64/q128/array/scalar mismatches, unsupported
  q256, every truncated leaf length, trailing body/table bytes, forged
  kind/width/signed/reserved metadata, nil allocators, double disposal, input
  immutability, dynamic ownership, full encode/decode allocation-failure
  sweeps, and equal allocation counts for one versus 128 fixed elements;
- independent review found every portable switch and ownership path complete;
- `make check`, package checks, histories v1–v4, and all legacy frozen hashes
  pass unchanged;
- the production 4→5 report remains exactly 9,098 bytes with SHA-256
  `edf30613795c0711c39efd3f82d7da68bd21589336f722cb367d8d8861f8336b`;
- the unresolved scaffold remains exactly 76 lines and 2,405 bytes with
  SHA-256
  `378cc8036c9af1a44175d1833752e645c01c3b7e9830cdbebbb1a798fb3a48fd`,
  and its locked scaffold check passes. The ambient standalone `odinfmt`
  currently rewrites that unchanged generated file to a different byte form;
  this is inherited A1 formatter drift and not caused by A2;
- the full suite is 751/752 plus Rondine 19/19; the sole failure is the expected
  frozen-v4/live-schema mismatch;
- the new portable source SHA-256 is
  `accfe53cdafc735f14139f3170f935f066d335a7c2a4cbeba87f79855d0ce27c`;
  no binary, probe, temporary scaffold, or v5 artifact remains.

### M4R6A3 — Apply the audited fixture policy tags

Make only the exclusion changes already resolved by the M4R6A audit. Do not
freeze v5, alter schema version, generate history/migrations, or change runtime
behavior.

1. Add `fixture:"-"` to `flight.Ace_Runtime.local_rate`; it is derived from
   body orientation and `angular_velocity_world` before use.
2. Add `fixture:"-"` to `postale.Runtime.telemetry` and
   `postale.Runtime.ace_telemetry`, and to `libellula.Runtime.telemetry`. These
   are per-step observations. Keep both vehicles' body state, flight model,
   designer tuning, persistent ACE energy/edge state/edge seconds, controls,
   and spawn orientation serialized.
3. Add `fixture:"-"` to root `Editor.camera_target_lock`; it is capture/session
   state. Keep the actual camera/editor viewpoint fields serialized.
4. Do not exclude Rondine telemetry or wake state. Its prior drift intensity
   and forward speed feed the next step and remain fixture-relevant until a
   separate derivation proof exists.
5. Add production sentinels proving every new exclusion and every nearby
   required retention. Re-run schema generation twice into disposable output.
   The post-policy 4→5 report must remove only the audited telemetry,
   `local_rate`, and camera-lock records/fields; all 14 pre-policy structural
   obligations must otherwise retain their intended meaning.

Acceptance requires focused sentinels, `make check`, deterministic post-policy
candidate/report/scaffold hashes, histories v1–v4 and every frozen hash
unchanged, no committed v5 artifact, and a full suite whose only failure
remains the expected frozen-v4/live-schema mismatch.

#### M4R6A3 acceptance — 2026-07-29

M4R6A3 is accepted. The production diff is exactly five tag additions:
`flight.Ace_Runtime.local_rate`, both Postale telemetry fields, Libellula
telemetry, and root `camera_target_lock`. No runtime behavior or schema version
changed.

- a separate live-manifest policy test proves all five exclusions and 22
  fully-qualified neighboring retentions, including ACE persistent state,
  both vehicles' body/tuning/spawn state, editor camera state, and all Rondine
  telemetry/wake fields;
- independent review confirms each excluded value is recomputed or
  session-only, while Rondine's prior telemetry and wake feed the next step;
- the deterministic post-policy candidate is 1,637 lines, 151,533 bytes, 169
  records, and 153 root fields, SHA-256
  `9c608e6ceed237e0398b362817521c1cb10d55056b4f17a462a4bbdf52b4b25b`;
- the exact 4→5 report is 9,664 bytes, SHA-256
  `32d69b16b5f8fcb7d5767a2a4f2e503982d1c3f68636200f1421b5eb6accd872`,
  with 21 changes split 17 state and four supporting;
- the exact unresolved scaffold is 88 lines and 2,797 bytes, SHA-256
  `1c0cb64086b2408303850f8fe76feef592adbdc8af5155a2c7167a962a92a05e`,
  with 17 ordered unresolved IDs. Its check and two deterministic renders
  pass;
- the v4→live diff/scaffold goldens were updated only for this audited policy
  change. All earlier-version and synthetic goldens remain untouched;
- focused policy/diff/scaffold tests pass 3/3 twice after formatting with zero
  leaks; `make check` and histories v1–v4 pass;
- the full suite is 752/753 plus Rondine 19/19; the sole failure remains the
  expected frozen-v4/live-schema mismatch;
- every frozen schema/history/migration hash remains exact, and no binary,
  probe, temporary scaffold, or v5 artifact remains.

### M4R6B1 — Install the exact unresolved 4→5 scaffold

Use the production CLI installer to create the migration source boundary before
writing any migration logic.

1. Install only `src/fixture_migration_v0004_to_v0005.odin` through
   `migration-scaffold 4 5`. Do not hand-author, overwrite, or reformat the
   generated source.
2. Lock the generated file at 88 lines, 2,797 bytes, and SHA-256
   `1c0cb64086b2408303850f8fe76feef592adbdc8af5155a2c7167a962a92a05e`.
   It must contain exactly the 17 sorted state IDs already pinned by the
   scaffold golden, all `.Unresolved`.
3. Run the official scaffold check against the live candidate twice and prove
   exclusive-install/no-overwrite behavior. Do not add a runtime wrapper,
   registry dispatch, v5 manifest/history package, schema-version bump, or
   migration implementation in this slice.

Acceptance requires the focused diff/scaffold/policy tests, `make check`,
histories v1–v4, exact candidate/report/scaffold hashes, all frozen hashes
unchanged, no generated binary or other v5 artifact, and the full suite with
only the expected frozen-v4/live-schema mismatch.

#### M4R6B1 acceptance — 2026-07-29

M4R6B1 is accepted. The official exclusive installer created only
`src/fixture_migration_v0004_to_v0005.odin`.

- the source is exactly 88 lines and 2,797 bytes with SHA-256
  `1c0cb64086b2408303850f8fe76feef592adbdc8af5155a2c7167a962a92a05e`;
- all 17 state change IDs exactly match the sorted post-policy golden and remain
  `.Unresolved`;
- a second official install fails with `already exists` and leaves the source
  hash unchanged; the official scaffold check passes twice;
- focused policy/diff/scaffold tests pass 3/3 twice with zero leaks;
- `make check`, histories v1–v4, and all candidate/report/frozen hashes pass;
- the full suite remains 752/753 plus Rondine 19/19, with only the expected
  frozen-v4/live-schema mismatch;
- independent review confirms the generated imports, constants, `#by_ptr`
  source ABI, target pointer, allocator, and unresolved return are exact;
- no formatter touched the generated file, and no runtime wrapper, registry
  change, v5 manifest/history package, binary, or temporary artifact exists.

## Milestone 4D — Install owned state and rebuild runtime resources

Decode into temporary owned state, validate it, preserve root runtime
resources, atomically replace `editor.fixture`, transfer the migration arena
owner, release the prior fixture owner, and rebuild derived/runtime state.

Required rebuilds include physics world/terrain bodies, generated meshes and
projected faces, paint scratch/history and texture invalidation, story
catalogs, audio/dialogue/input reset, active gesture reset, circulation
storage, and terrain/renderer cache invalidation. Failed loads must leave the
live editor and its owner unchanged. Successful loads must survive multiple
simulation/render frames and final destruction with no invalid handles or
allocator mismatch.

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

## Milestone 6 — Harden later complex migration generation

Milestone 4A generalizes the version routing, and 4B proves the first later
transition. Extend that workflow for more complex historical roots and
generated automatic mappings. Before accepting a historical root containing
`[dynamic]`, map, pointer, or other pointer-backed mutable data, replace or
strengthen the `#by_ptr` historical-view contract; it is not deep const for
those fields.

Acceptance criteria:

- Additions and other unambiguous changes receive generated mappings.
- Removed, renamed, split, merged, or semantically changed fields produce a
  failing Odin script stub with useful context.
- Missing, duplicate, or skipped migration steps fail validation.
- Historical input cannot mutate caller-visible or later-consumed migration
  state through pointer-backed fields.

## Milestone 7 — Run migration chains during editor load

Move the memory-only chain proven in 3F behind editor load, running every
migration in memory before rehydration.

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
- audit fields inserted near the `Fixture`/`Editor` boundary after rebases;
- audit nested reachable structs, imported constants, enum values, and container
  shapes rather than checking only direct `Fixture` fields;
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

## Milestone 10 — Integration and polish

Run full fixture, migration, build, test, and representative playground checks.
Remove debug paths and temporary compatibility code.

Acceptance criteria:

- Existing tests pass.
- Golden fixtures migrate successfully.
- Representative playgrounds reproduce expected state.
- No known runtime handles or transient pointers enter fixture payloads.

## Explicitly separate work

Barrier schema, runtime behavior, and authoring are outside this feature. They
need an independent plan after fixture rework is accepted.
