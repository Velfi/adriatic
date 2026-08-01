# SDF Obstacle Tool Plan

## Feature

Build an editor tool for placing and manipulating fixture-backed SDF obstacles.
This pass supports torus obstacles only.

## Problem

Level designers need a fast way to create testing barriers in fixture scenes,
select already-placed barriers, and reshape or reposition them without rebuilding
the playground in code.

## Current phase

Phase 3 — Milestone 1 ready for sis validation.

The feature is split into seven ordered milestones. A subagent implements one
milestone at a time in the current workspace. The primary agent reviews the
complete `jj` diff and automated gates, then asks sis to validate the milestone
in the running editor. The primary agent commits only after that validation.

Do not use worktrees. Do not start a later milestone before the current one is
accepted.

## Scope

In scope:

- one SDF shape: a torus;
- fixed-capacity fixture-backed obstacle storage;
- create, select, delete, and viewport picking;
- a flat inspector list and property controls;
- position;
- quaternion-backed rotation with Euler XYZ degree controls;
- positive non-uniform XYZ scale;
- major radius and tube radius;
- per-obstacle color;
- visible translation, rotation, and scale gizmos;
- Blender-style `G`, `R`, and `S` modal hotkeys with axis constraints;
- rendering in editor and fixture gameplay;
- collision for every aircraft kind;
- fixture save, load, migration, and offline upgrade support.

Out of scope:

- SDF shapes other than a torus;
- final-game level or terrain-project persistence;
- player, car, or boat collision;
- terrain deformation, navigation, or AI avoidance;
- presentation polish beyond clear solid rendering, selection feedback, and
  readable gizmos;
- a new generalized editor undo system;
- exhaustive visual-regression, hostile-input, or per-allocation OOM matrices.

Modal transform cancellation is still required: Escape or right-click restores
the exact transform captured when the interaction began.

## Locked design decisions

### Durable state

Durable obstacle state belongs directly in the promoted `Fixture`. Do not park
it temporarily on root `Editor`, and do not hide it with `fixture:"-"`.

Use a fixed-capacity collection so fixture lifecycle code does not gain another
allocator-owned container. The initial capacity is 64.

The source contract is:

```odin
SDF_OBSTACLE_CAPACITY :: 64

SDF_Torus_Obstacle :: struct {
    position:     flight.Vec3,
    rotation:     quaternion128,
    scale:        flight.Vec3,
    major_radius: f32,
    tube_radius:  f32,
    color:        [4]u8,
}
```

`Fixture` owns:

```odin
sdf_obstacles:         [SDF_OBSTACLE_CAPACITY]SDF_Torus_Obstacle,
sdf_obstacle_count:    int,
sdf_obstacle_selected: int,
```

Selection is persisted, matching existing fixture-backed authoring selections.
Hover state, active gizmo mode, constrained axis, drag anchors, transform
snapshots, and cached inspector Euler angles belong structurally beside the
tool but use `fixture:"-"`.

Active obstacle validation requires:

- count within capacity;
- selected index equal to `-1` or within the active range;
- finite position, quaternion, scale, and radii;
- a usable normalized quaternion;
- strictly positive scale components;
- strictly positive radii;
- an opaque color on creation.

### SDF and non-uniform scale

The canonical local torus is aligned to the Y axis:

```text
length((length(local.xz) - major_radius, local.y)) - tube_radius
```

A world query:

1. subtracts position;
2. applies inverse quaternion rotation;
3. divides by positive XYZ scale;
4. evaluates the canonical local torus;
5. multiplies distance by the smallest scale component.

This preserves the exact zero surface and sign. Distance magnitude is
conservative under non-uniform scale, which is acceptable for this pass.
Normals use the local analytic gradient, inverse scale, quaternion rotation,
and final normalization.

Broadphase radius is:

```text
(major_radius + tube_radius) * max(scale)
```

### Rendering

Use a small product-local CPU torus tessellation based on the existing
Libellula mesh helper. A 16 by 8 surface is sufficient.

Transform vertices with quaternion and XYZ scale. Transform normals with
inverse scale and quaternion before normalization. Submit ordinary smooth-lit
world triangles with the obstacle color.

Do not add a raymarch shader or widen the Vulkan instance ABI. The existing
instance normal transform is unsuitable for non-uniform scale.

### Inspector and interaction

Use the existing custom editor rail and inspector, not an always-open ImGui
window. The custom panel avoids keyboard-capture conflicts with modal hotkeys.

The obstacle list is flat. Entries may use stable display labels such as
`TORUS 01`; authored names are not part of this pass.

The single orientation convention is:

- translation gizmo: world axes;
- rotation gizmo: local axes;
- scale gizmo: local axes.

Hotkey axis constraints match the currently visible gizmo axes. An orientation
mode toggle and Blender's double-axis-key behavior are not required.

All modal operations:

- snapshot once at begin;
- update the live obstacle during interaction;
- commit with left-click or Enter;
- cancel and restore the exact snapshot with right-click or Escape;
- consume conflicting authoring and camera input while active.

Use world-render mouse coordinates for viewport picking and gizmos. Continue
using screen coordinates for the editor panels. Mixing the two breaks picking
in scaled or HiDPI windows.

### Aircraft collision

Use one practical sphere proxy per aircraft kind. Resolve it after each active
aircraft fixed step and before the shared crash transition check.

On contact:

1. push the body outside along the SDF normal;
2. remove inward normal velocity;
3. mark the appropriate aircraft runtime crashed;
4. synchronize its presentation vehicle;
5. let the existing crash recovery and audio path observe the transition.

The torus hole remains passable when the aircraft proxy fits.

## Fixture-v7 rebase baseline

New main independently froze schema v6 before the SDF work landed:

```text
manifest SHA-256: 6285a9a9004efb848f46863801bb934f6251f3b0aeef9c87a0dab82ab25d57f0
history SHA-256:  7979165b6e44f5f7ac2c610a1d46f6bf6cd937799b395512252b947c5baa59e7
lines:           1,941
records:         202
root fields:     155
```

The old feature branch also called its combined schema v6. Comparing that
candidate against main's frozen v6 isolates the SDF delta exactly:

```text
candidate SHA-256:    adb3ca76b334cba6fbd631ec59b28428dd4b1a629ac38ae5a5ee3400a6b05c3c
lines:                1,952
records:              203
root fields:          158
changes:              5
state changes:        4
supporting changes:   1
```

The four state obligations are the appended `.Obstacles` enum value and the
three durable Fixture fields. `SDF_Torus_Obstacle` is the sole supporting type.
Main's frozen v6 manifest, history package, and 5→6 migration remain
byte-identical; the torus contract moves to the adjacent 6→7 boundary.

## Milestone 1 — Fixture v7 and torus data foundation

### Build

- Add `SDF_Torus_Obstacle`, capacity, durable Fixture fields, and excluded
  interaction fields.
- Append `.Obstacles` to `Authoring_Tool` without changing earlier enum values.
- Bump `FIXTURE_SCHEMA_VERSION` from 6 to 7 exactly once.
- Generate and freeze the v7 manifest and v7 history package.
- Generate the exact 6→7 semantic report and migration scaffold.
- Resolve the three field additions with explicit obstacle defaults; the
  appended enum value is automatic because all earlier values are unchanged.
- Add the 6→7 migration core and runtime wrapper.
- Register only the adjacent 6→7 step after main's 5→6 step.
- Extend Fixture load validation and runtime interaction reset.

### Migration decisions

- v1–v6 fixtures receive an empty obstacle array;
- count defaults to `0`;
- selection defaults to `-1`;
- existing `Authoring_Tool` values retain their old numeric meaning;
- `.Obstacles` is appended.

### Acceptance

- frozen v1–v6 hashes are unchanged;
- v7 manifest, history, scaffold, and migration are deterministic;
- direct v6→7 migration passes;
- every supported chain from v1 through v7 passes;
- current Fixture codec, load, store, and upgrade paths accept v7;
- malformed obstacle counts, selected indices, transforms, and radii are
  rejected before Editor mutation;
- schema, history, migration, codec, load/store, `make check`, and full tests
  pass without leaks.

Testing stays practical. Cover the real migration decisions and boundary
validation, but do not add a combinatorial hostile/OOM campaign.

### Progress / Evidence

Rebase resolution is complete.

- Main's frozen v6 manifest and history hashes above are restored exactly.
- Main's 5→6 migration source and runtime remain byte-identical at
  `c213621d52a0aaacf6b315337ecd91be52f96aa75b6080e971d41db04fc19bea`
  and `89a6b9f7c8041a5927034aacbc64622a091ca197e0f678eefc9fedcd848724b4`.
- The generated v7 manifest has SHA-256
  `adb3ca76b334cba6fbd631ec59b28428dd4b1a629ac38ae5a5ee3400a6b05c3c`,
  1,952 lines, 203 records, and 158 root fields.
- The generated v7 history package has SHA-256
  `d59d3d0d103ba139c4a38ddb3fc55ac45a993cc42300704d5e4f6748e2ede8ef`
  and 2,559 lines.
- The exact 6→7 semantic report is 5 changes: 4 state changes and 1
  supporting change.
- The 6→7 migration defaults the obstacle array and count to empty/zero and
  selection to `-1`; it preserves every old `Authoring_Tool` value. Its
  SHA-256 is
  `7cf71e12617b28e8ee8b3d76f5595356af9333e55d480edbf5d8d18cecc95029`.
- The production registry is contiguous across six steps from v1 through v7.
- Schema check, v6 and v7 history checks, 6→7 scaffold check, and `make check`
  pass.
- The direct v6→7 plus chained v5→7 test passes 1/1 with no leak report.
- The aggregate migration target ran all 17 tests in 7 minutes 41 seconds.
  Sixteen passed; the only failure was two stale future-version expectations
  in the old registry test. Those expectations now use
  `FIXTURE_SCHEMA_VERSION + 1`, and that focused test passes 1/1.
- Codec round-trip and practical allocation/preflight tests pass 2/2 in
  1 minute 19 seconds with no leak report.

### Sis validation

Run the focused fixture gates and normal build. Confirm that existing fixture
playgrounds still load before this milestone is committed.

## Milestone 2 — Visible CRUD tool

### Build

- Add the Obstacles authoring-tool entry and reset behavior.
- Add a flat, scrollable torus list.
- Create a sensible default torus at the cursor or current editor focus.
- Select from the inspector or by nearest viewport SDF ray hit.
- Delete by compacting the active fixed array and repairing selection.
- Render every active torus with its stored color.
- Render an obvious selected-object highlight.

Refactor shared editor view-ray construction from the terrain cursor code.
Do not use terrain XZ footprint picking for floating or rotated obstacles.

### Acceptance

- create stops cleanly at capacity;
- inspector and viewport selection agree;
- viewport picking chooses the nearest hit;
- delete preserves remaining obstacles and leaves a valid selection;
- torus rendering works in editor and fixture gameplay;
- practical CRUD and canonical SDF tests pass;
- `make check` and full tests pass.

### Sis validation

Create several tori, select each by list and viewport, delete middle and end
entries, save the fixture, change the scene, then reload and confirm exact
restoration.

## Milestone 3 — Property inspector

### Build

- Add compact controls for position XYZ.
- Display and edit Euler XYZ degrees while storing only a quaternion.
- Add non-uniform scale XYZ controls.
- Add major-radius and tube-radius controls.
- Add RGB controls; keep alpha opaque for this pass.
- Keep a per-selection Euler display cache so equivalent quaternion
  representations do not visibly jump near singularities.
- Normalize and validate every quaternion update.

### Acceptance

- each property changes only the selected torus;
- inspector edits update rendering and picking immediately;
- identity, compound rotations, and near-singular rotations stay finite;
- scale and radii cannot cross their positive lower bounds;
- separately colored tori remain visually distinct;
- focused math/UI-state tests, `make check`, and full tests pass.

### Sis validation

Build at least three visibly different tori. Edit every field, exercise awkward
Euler orientations, save, reload, and confirm the same transforms and colors.

## Milestone 4 — Translation gizmo

### Build

- Draw world-axis translation shafts, arrowheads, and a free-move handle.
- Add screen-space handle hit testing using existing 3D projection.
- Support direct gizmo dragging.
- Support `G` free movement and `G` followed by `X`, `Y`, or `Z`.
- Suppress conflicting camera/tool keys while the modal operation is active.
- Implement exact commit and cancellation behavior.

### Acceptance

- each handle moves only along its advertised world axis;
- free movement follows the editor view plane;
- gizmo size stays usable across camera distance;
- list selection and viewport selection place the gizmo on the same obstacle;
- Escape/right-click restores the bitwise starting transform;
- focused interaction tests, `make check`, and full tests pass.

### Sis validation

Move tori by each handle and by every `G` mode from near and far camera
distances. Confirm commit, cancel, selection switching, and camera-key
suppression.

### Midpoint sunk-cost check

Stop after sis validates Milestone 4. The tool must already be useful for
creating, selecting, inspecting, saving, loading, and positioning obstacles.
If not, fix the interaction model before rotation, scale, or collision work.

## Milestone 5 — Rotation gizmo

### Build

- Draw local-axis rotation rings.
- Add stable screen-space ring picking and dragging.
- Support `R` free/view rotation and `R` followed by `X`, `Y`, or `Z`.
- Compose and normalize quaternion updates.
- Keep inspector Euler output stable through repeated edits.
- Reuse the shared modal snapshot, commit, cancel, and input-consumption path.

### Acceptance

- each colored ring rotates around its displayed local axis;
- free rotation is usable from ordinary editor camera angles;
- repeated rotations preserve a finite unit quaternion;
- cancel restores the exact starting quaternion;
- rendering, picking, and translation axes follow the committed orientation;
- focused quaternion/interaction tests, `make check`, and full tests pass.

### Sis validation

Rotate a non-uniformly scaled torus around every axis, combine rotations,
cancel several interactions, and verify inspector values remain usable.

## Milestone 6 — Non-uniform scale gizmo

### Build

- Draw local XYZ scale handles and a uniform center handle.
- Support direct handle dragging.
- Support `S` uniform scaling and `S` followed by `X`, `Y`, or `Z`.
- Enforce a positive scale floor.
- Update mesh normals, ray picking, gizmo axes, and SDF queries from the same
  committed transform.

### Acceptance

- each axis handle changes only its local scale component;
- uniform scaling preserves component ratios;
- no path produces zero, negative, NaN, or infinite scale;
- transformed rendering and the SDF zero surface continue to agree;
- cancel restores the exact starting scale;
- focused non-uniform-transform tests, `make check`, and full tests pass.

### Sis validation

Exercise uniform and every single-axis scale path, including thin and stretched
but sane shapes. Check selection, rotation, rendering, and cancellation after
each transformation.

## Milestone 7 — Aircraft collision

### Build

- Add broadphase culling for active obstacles.
- Add one tuned collision-sphere radius per aircraft kind.
- Resolve the active aircraft after each fixed simulation step.
- Push penetrations out along the transformed SDF normal.
- Remove inward normal velocity.
- Mark Postale, Libellula, Libellula Mk2, or Rondine crashed through the
  appropriate runtime path.
- Synchronize the presentation vehicle after correction.
- Reuse the existing shared crash transition, recovery, and audio handling.

### Acceptance

- a fitting aircraft can pass through the torus hole;
- striking the tube from outside or inside triggers collision;
- rotated and non-uniformly scaled tori collide in the same place they render;
- collision response leaves the body outside with no inward normal velocity;
- all four aircraft kinds enter the existing crash/recovery flow;
- practical hole, tube, transformed-contact, and velocity tests pass;
- fixture gates, `make check`, and full tests pass.

### Sis validation

Fly Postale, Libellula, Libellula Mk2, and Rondine through a large hole and
into the tube. Repeat against a rotated, stretched torus and confirm collision,
recovery, rendering, and saved fixture behavior.

## Final integration gate

After all milestones:

- run every fixture schema/history/migration/codec/load/store/upgrade gate;
- run `make check` and the full test suite;
- build and launch the real editor;
- upgrade committed fixture files only if any exist below the owning fixture
  directories;
- confirm no generated binaries, probes, or debug logging remain;
- inspect `rtk jj status` and `rtk jj diff --git`;
- confirm unrelated user files and frozen v1–v5 artifacts are untouched.

The feature is complete only when sis confirms the full editor workflow feels
usable in context.
