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

`packages/flight` contains the deterministic fixed-wing model ported from
ArchipelagoGame. It owns vector and orientation math, aerodynamic forces,
propeller thrust, stall behavior, airflow-scaled control surfaces, and passive
airframe stability. The calling game owns collision, water interaction, input,
audio, visuals, damage, and AI policy.

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
