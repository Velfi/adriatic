# SDF Obstacle Tool Plan

## Feature

Build an editor tool for placing and manipulating fixture-backed SDF obstacles.
This pass supports torus obstacles only.

## Problem

Level designers need a fast way to create testing barriers in fixture scenes,
select already-placed barriers, and reshape or reposition them without rebuilding
the playground in code.

## Current phase

Phase 5 — Milestones 1 through 4 are accepted. Milestone 5 rotation gizmo is
the active slice. Non-uniform scale remains Milestone 6.

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

## Corrected fixture baseline

The initial v6→v7 proposal predates repeated rebases and is no longer a valid
account of repository history. Obstacles actually entered the frozen graph as
part of the broader v18→v19 fixture transition; Dunes and map-source work
shared that boundary. The obstacle data is therefore an identifiable subset,
not the whole semantic report.

```text
v18 manifest: 9a62a0356849d0731ceb6714cac7e618bd89276b94c3aa629b98b6f0f9a3e00a (2,032 lines)
v18 history:  3af32bc608b8dc6780ea2ee2b1388bf54f08cdf6ef6d51665950d455b7067615 (2,666 lines)
v19 manifest: 3d05aba642569c56a01b3476cc9745f701076dcf92cf97c8c459aad2d23121ca (1,273 lines)
v19 history:  2c15a7846875ef1b135b1630a4e3ffc2f90604d412822829e85a3f461a0e10a2 (1,659 lines)
v20 manifest: 06cb941a8912fcc7337689760d503e0b90864644d5a16282824dfeb4c7a0e6bb (1,293 lines)
v20 history:  ffb5714d4f7f7fdbd94f020502bfbd08191845c2daa849b9154f42c489df6683 (1,688 lines)
```

`FIXTURE_SCHEMA_VERSION` is 21. The frozen v18→v19 semantic report contains
122 changes (115 state and seven supporting). The obstacle subset is exactly:

- appended `Authoring_Tool.Obstacles = 14`;
- `Fixture.sdf_obstacles`, `sdf_obstacle_count`, and `sdf_obstacle_selected`;
- supporting `SDF_Torus_Obstacle`.

The production v18→v19 migration and wrapper are frozen at
`6d428086328d14a8d490bbe702fe706d29e14d0fafe852aa391457aa132ca5e1` and
`6bc89145cf7d514bfdf280845898147d53e1a636102d3419a38e38b50d002c8c`.
The following v19→v20 transition is a six-change car-racer migration; it does
not alter obstacle state. The independent v20→v21 ACE transition adds only
`Tweak_State.postale_ace_tuning`; its frozen manifest and history are
`6608496024394758b33bbf4d7de14f94eaffc87e9212c40f7deba89cf9720a9e` and
`f690c80ee90a7d632a2df5d01ac8f02c0858eb2c67cc122440dc75aff10efcf2`.

## Milestone 1 — Fixture v19 and torus data foundation

### Completed build

- `SDF_Torus_Obstacle`, its capacity, the durable Fixture fields, and excluded
  interaction fields are present.
- `.Obstacles` is appended to `Authoring_Tool`; earlier numeric values remain
  unchanged.
- The v18→v19 history, semantic report, resolved migration, runtime wrapper,
  and contiguous production registry are frozen.
- Fixture load validation rejects malformed counts, selections, transforms,
  radii, and interaction state is reset after load.

### Migration decisions

- v1–v18 fixtures receive an empty obstacle array;
- count defaults to `0`;
- selection defaults to `-1`;
- existing `Authoring_Tool` values retain their old numeric meaning;
- `.Obstacles` is appended.

### Acceptance

- frozen v1–v21 artifacts remain unchanged;
- v18→v19 migration preserves old `Authoring_Tool` values and gives all older
  fixtures the intentional empty obstacle defaults;
- direct v18→v19 and chained historical paths preserve the same defaults;
- current Fixture codec, load, store, and upgrade paths retain obstacle state;
- malformed obstacle counts, selected indices, transforms, and radii are
  rejected before Editor mutation;
- schema, history, migration, codec, load/store, `make check`, and full tests
  pass without leaks.

Testing stays practical. Cover the real migration decisions and boundary
validation, but do not add a combinatorial hostile/OOM campaign.

### Reconciliation evidence

- The frozen v18→v19 report confirms the exact obstacle subset above; the
  remaining report obligations belong to map/lab and removed authored-state
  work, not this feature.
- Frozen v19 and v20 manifests both preserve the obstacle enum value, all
  three Fixture fields, and the exact six-field torus structure.
- ACE's independent v20→v21 migration is frozen, and
  `make fixture-schema-check` passes again. It does not alter obstacle state.

### Sis validation

Run the focused fixture gates and normal build. Confirm that existing fixture
playgrounds still load and that an older fixture gets an empty obstacle
collection. This data-only milestone has no visual editor workflow to approve
yet.

### Verification

- `make fixture-schema-check` passes at frozen v21.
- `make fixture-codec-test` exits cleanly for both current-fixture codec
  checks, with no leak report.
- The direct v18→v19 fixture migration-chain proof exits cleanly; it reaches
  the obstacle-defaulting production step as part of the current v1→v21 chain.

## Milestone 2 — Visible CRUD tool

Milestone 2 adds no persisted fields and must not bump the schema. Start only
after Milestone 1 validation.

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

### Implementation evidence

Sis accepted the running-editor CRUD pass. Default-color cycling is usable for
now; manual color edits are intentionally Milestone 3.

- `src/sdf_obstacles.odin` provides fixed-array creation, selection, compact
  deletion, paged flat-list state, conservative torus SDF ray selection, and
  16×8 smooth-lit world tessellation. Creation uses the terrain cursor or the
  current editor focus and cycles opaque default colors.
- The existing Obstacles enum is now present in the live tool palette. Its
  inspector exposes ADD, DELETE, a five-entry paged torus list, and selection.
  A viewport click chooses the nearest torus or creates one on terrain.
- Obstacles render in the editor and gameplay world; a selected editor torus
  uses a brighter color. M2 adds no serialized field and
  `make fixture-schema-check` confirms frozen fixture state is unchanged.
- `make sdf-obstacle-test` passes 2/2 in 3.758 ms with no leak report:
  compact-array CRUD/defaults and canonical SDF nearest-hit selection.
- `make check` and `make build` pass.

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

### Implementation evidence

M3 is accepted after focused sis validation of the property inspector and its
compact layout.

- `src/sdf_obstacles.odin` now owns selected-index-guarded setters. Position
  clamps to the terrain world half extent, scale to `0.05..32`, and each radius
  to `0.05..64`; non-finite inputs leave durable state unchanged. RGB writes
  always set alpha to 255.
- Rotation uses core `linalg` Euler `.XYZ` order in UI degrees, converts to the
  existing `quaternion128`, validates and normalizes it, then preserves the
  exact edited degrees in the transient inspector cache. Selection and compact
  deletion refresh or clear that cache.
- The custom inspector adds five compact rows below the five-entry list:
  position XYZ, rotation XYZ, scale XYZ, ring/tube radii, and RGB. They remain
  above the shared bottom actions at 1280×720 and call the selected setters, so
  current render and pick paths observe edits immediately.
- `make sdf-obstacle-test` passes 3/3 in 3.919 ms with no leak report. The new
  direct test covers selected-only mutation, position/size/radius bounds,
  opaque RGB, identity and near-singular compound Euler paths, and invalid
  Euler preservation.
- `make fixture-schema-check`, `make check`, and `make build` pass. M3 changes
  no fixture-reachable type, version, manifest, history, or migration.
- M3 layout repair suppresses the unrelated generic WORLD summary only while
  valid selected-torus property controls occupy the compact panel. It remains
  available for every other tool and Obstacles with no selected torus, while
  the shared bottom actions remain visible at 1280×720.

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

### Implementation evidence

- Global X/Y/Z shafts with endpoint handles and a free-move center render only
  for a valid selected torus while the Obstacles tool is active. Their world
  size scales with camera distance and remains clamped to a usable range.
- Screen-space hit testing distinguishes each projected axis from the center.
  Axis movement solves the closest point against the selected world axis and
  preserves the two untouched snapshot coordinates; free movement intersects a
  camera-facing plane through the snapshot position.
- Translation snapshots once at modal start. Direct handle clicks and `G`
  start it; `X`, `Y`, and `Z` constrain it. Release commits, while Escape,
  right-click, disabled UI, invalid ray, tool switch, and map transition cancel
  and restore the exact snapshot.
- Plain `G` stays reserved for a valid Obstacles selection instead of switching
  to Greek Assets. Modal/start input also blocks editor-camera input.
- Modal ownership keeps the original selected slot transiently. Editor UI and
  generic authoring shortcuts are bypassed during a live modal; a defensive
  selection mismatch cancels without touching the new selection. `G` also
  requires a valid initial ray before creating modal state. A failed first
  direct-handle solve cancels immediately rather than leaving a modal active.
- Both direct handles and `G` anchor to their first solved ray contact, so
  start leaves position unchanged and later motion applies only contact delta.
  Constraint switching re-solves and re-anchors before writing, preventing an
  X/Y/Z snap.
- Gizmo world scale now derives from camera-forward depth, focal length, and
  viewport height for a fixed 48-pixel perpendicular axis. Rendering and hit
  testing use the same helper; no world-size clamp remains. Near/far projection
  coverage verifies the fixed pixel length, including the vehicle showcase's
  2.0 focal length.
- `make sdf-obstacle-test` passes 4/4 in 3.95 ms. `make
  fixture-schema-check`, `make check`, and `make build` pass. No
  fixture-reachable state, schema, manifest, history, or migration changed.
- Sis accepted the completed translation workflow by advancing the tool to
  rotation and scale gizmos.

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
- confirm unrelated user files and frozen v1–v21 artifacts are untouched.

The feature is complete only when sis confirms the full editor workflow feels
usable in context.
