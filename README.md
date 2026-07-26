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
remain presentation policy in `src/`. On foot, tap Shift while moving to toggle running:
running builds extra speed, steers momentum in a broad arc, and lets the mouse
face into a turn before its velocity catches up for a drifting-car feel. At
speed, press and hold Space to hop and charge a drift, steer to charge faster,
then release Space for a short mini-turbo. Running switches itself off after
the mouse releases movement and coasts to a stop.

The game runtime supports standard SDL game controllers throughout (the editor
remains keyboard-and-mouse only). On foot, the left stick moves, the right
stick looks, the triggers zoom, the south face button jumps or drifts, the
north face button toggles running, and the west face button interacts. Cars
use the triggers for throttle/brake, left-stick steering, right-stick camera,
right shoulder for the handbrake, and west to exit. Aircraft use the left
stick for pitch/roll, right stick for the camera, shoulders for yaw, triggers
for power, south to recenter, west to exit, and north to reset.

The runtime switches prompts and cursor policy according to the device most
recently used, with Xbox, PlayStation, and Nintendo face-button labels. Start
opens or closes pause menus; D-pad, left stick, accept, and cancel provide menu
navigation. Disconnecting the controller in active use pauses the game and
offers keyboard/mouse fallback.

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

## City density brush

**CITY BRUSH [N]** paints a persistent settlement-density field instead of a
one-shot rectangle. Left-drag increases density and right-drag reduces it;
wheel adjusts radius, Shift+wheel adjusts flow, and Alt+wheel adjusts hardness.
The editor shows the density overlay and an exact staged building preview while
the tool is active. Density controls both packing and height, while generated
buildings avoid water, steep foundations, existing formations, road shoulders,
and junctions and align to nearby road curves. City density is saved with the
project and participates in formation undo/redo.

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
| `make fmt` | Format all project Odin sources. |
| `make check` | Type-check the application. |
| `make test` | Run starter tests. |
| `make run` | Build and run the development executable. |
| `make release` | Build an optimized executable. |
| `make physics-build` | Fetch and build Zelda Engine's pinned Jolt dependency. |

The executable owns capture commands:

```sh
build/dev/adriatic capture building build/captures/building.png 4
build/dev/adriatic capture foliage-forest build/captures/forest.png
build/dev/adriatic capture bougainvillea build/captures/bougainvillea-seeds
```

The generic form is `adriatic capture <mode> <output.png> [target]`.
`capture bougainvillea` writes the six-seed palette/habit validation matrix to
an output directory; append seed values to override the default matrix.

## Releases

Pushing a `v*` tag builds self-contained macOS and Windows x64 archives and
publishes a GitHub Release. See [docs/release.md](docs/release.md) for the
required engine checkout settings and optional Apple signing credentials.
