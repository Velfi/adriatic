# Adriatic

An Odin game project built on [Zelda Engine](../zelda-engine).

## Layout

```text
parent-directory/
├── adriatic/
└── zelda-engine/
```

`src/` contains the executable and presentation layer. Put game-specific rules
in `packages/` as the project grows. Zelda Engine remains a reusable sibling
dependency and is imported through the `zelda_engine` collection.

## Flight model

`packages/flight` contains the deterministic fixed-wing and Libellula tri-rotor
models. It owns vector and orientation math, aerodynamic forces, propeller and
rotor thrust, stall behavior, control authority, and passive stability.
`packages/postale` and `packages/libellula` add the product-facing terrain
contact, occupancy synchronization, control smoothing, and presentation state.
The calling game still owns input, audio, visuals, damage, and AI policy.
Libellula's assisted collective maps Shift to climb and Ctrl to descend; releasing
both holds a hover while its cyclic assist levels the airframe and damps drift.

## Third-person controller

`packages/third_person` provides a compact, camera-relative character-motion
controller. Give `step` the collision system's grounded result each frame, then
apply its position and velocity to the game's physics body. `camera_pose`
supplies a basic orbit-camera position; collision avoidance and input binding
remain presentation policy in `src/`.

## Vehicle occupancy

`packages/vehicles` includes a small GTA-style driver interaction layer. Use
`try_enter_nearest` for the interact action, route input to the returned
vehicle while the character is seated, call `sync_driver` after vehicle physics,
and use `try_exit` with the result of a door-side collision query.

## Machine simulation

`packages/machines` ports ArchipelagoGame's physical maintenance rules: tool
gates, bounded gesture travel, deferred repair completion, verification tests,
and the current aircraft and land-vehicle procedure catalog. It has no scene,
input, or UI dependencies; game code supplies tool identifiers and translates
its events into animation, clock advancement, repair effects, and feedback.

## Dialogue

`packages/dialogue` ports the reusable branching conversation runtime from
ArchipelagoGame. A `Definition` contains authored nodes and choices;
conditions filter choices against the caller's `Context`, and effects update
the owning game's state. The package is deliberately presentation-neutral, so
the game can render `current` and `available_at` with its own canvas/UI layer.

## Wireframe renderer

`packages/wireframe` defines the Vulkan vertex/push-constant contract for the
depth-tested wireframe pass. The Slang shader at `assets/shaders/wireframe.slang`
expands each edge to a screen-space ribbon, uses the active Vulkan depth
attachment for occlusion, and interpolates endpoint colors. Build its SPIR-V
stages with `make shaders`.

## Terrain authoring

The executable is now a clipmap terrain lab. It edits a five-level height and
material hierarchy over an infinite ocean plane: sculpt, smooth, and paint the
island with the mouse while the colored rings show the nested terrain levels.

## Spline road networks

`packages/roads` defines a renderer-independent 3D road graph. Nodes carry
position, up direction, and junction radius; cubic Bézier edges carry their two
control points, road width, and shoulder width. `roads.bake` adaptively sweeps
the edge profiles, trims them at shared nodes, and emits one angle-sorted cap
per junction, producing a single indexed mesh with road, shoulder, and junction
surface tags. The result owns dynamic vertex and index arrays and should be
released with `roads.mesh_destroy`.

The terrain lab exposes this as **ROADS [M]**. Click empty terrain to start or
extend a chain, click an existing node to connect or branch, and drag the cyan
control handles to shape each Bézier edge. The wheel changes new-road width;
Shift+wheel changes the selected junction radius, right-click ends the current
chain, and Backspace removes the selected junction. Press K to cycle asphalt,
gravel, cobblestone, and dirt for new roads or every edge attached to the
selected junction. Different surfaces can meet inside one welded network.
Road graphs participate in project save/load and formation undo/redo.

```odin
graph: roads.Graph
a := roads.add_node(&graph, {0, 2, 0})
b := roads.add_node(&graph, {40, 6, 20})
roads.add_edge(&graph, a, b, {12, 3, 0}, {28, 5, 20}, 7)
mesh := roads.bake(&graph)
defer roads.mesh_destroy(&mesh)
```

## Quick start

```sh
make doctor
make run
```

`ZELDA_ENGINE_ROOT` overrides the default sibling-engine location. The project
uses a pinned commit of the `catermujo/Odin` fork; run `make bootstrap-fork` on
macOS when the local fork compiler is not already installed. `make bootstrap`
provisions the fork plus the other project toolchain dependencies.
Jolt Physics is provisioned automatically from Zelda Engine's pinned source
checkout when building, releasing, or testing Adriatic.

## Everyday commands

| Command | Purpose |
| --- | --- |
| `make fmt` | Format Odin sources. |
| `make check` | Type-check the application. |
| `make test` | Run starter tests. |
| `make run` | Build and run the development executable. |
| `make release` | Build an optimized executable. |
| `make physics-build` | Fetch and build Zelda Engine's pinned Jolt dependency. |
