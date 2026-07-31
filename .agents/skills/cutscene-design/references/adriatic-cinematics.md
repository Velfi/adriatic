# Adriatic cinematic runtime

Use this reference when designing or implementing against the checked-in cinematic system. Reinspect source before coding because this summary may age.

## Source map

- `packages/cinematic/cinematic.odin`: renderer-independent shot definitions, deterministic playback, easing, and wipe sampling.
- `src/cinematic.odin`: Editor integration, story-meeting example, pose restoration, and canvas fallback.
- `README.md`, **Cinematics**: public usage example and system overview.
- `src/cinematic_export.odin`: deterministic cinematic export pipeline.
- `packages/dialogue`: branching dialogue runtime and deterministic text reveal.

## Supported model

`Camera` contains position, target, and focal length. A `Shot` contains an id, duration, starting and ending cameras, easing, and an optional outgoing wipe. A `Script` borrows a slice of shots and may loop. Playback samples a camera deterministically from elapsed time.

Author cameras with:

```odin
cinematic.camera(position, target, focal_length)
```

Author a stationary composition with `cinematic.hold`; author interpolated position, target, and focal length with `cinematic.move`.

Available easing:

- `.Linear`: constant interpolation.
- `.Smooth`: smoothstep arrival and departure.
- `.Smoother`: gentler smootherstep arrival and departure.

Available wipes:

- `.Left`, `.Right`, `.Up`, `.Down`
- `.Iris`
- `.Clockwise`
- `.Checker`

The outgoing wipe begins near the end of its shot. At full cover playback advances to the next shot, then reveals its incoming camera. Without a wipe, the next shot is a direct cut.

## Important constraints

- Shot storage must outlive playback; `Script.shots` is a borrowed slice.
- A shot does not contain dialogue, actor animation, audio, arbitrary events, or branching.
- The current Editor adapter updates the camera from playback and has story-specific pose restoration. General entry/exit and skip semantics must be designed at the owning feature level.
- The runtime has no authored camera-roll field, path spline, look-at subject binding, collision avoidance, letterbox track, or camera shake track.
- A zero-duration shot is valid, but looping scripts must have positive total duration.
- Negative shot or wipe durations make a script invalid.

Do not silently encode unsupported beats as comments inside a camera script. List the required integration work and define event timing and end-state semantics explicitly.

## Implementation pattern

Prefer stable storage owned by the relevant game state, derive compositions from world anchors, save the gameplay camera before playback, and restore or deliberately replace it on completion. Validate all required anchors before starting.

```odin
shots := [?]cinematic.Shot {
    cinematic.move(
        "arrival",
        1.35,
        gameplay_camera,
        wide_camera,
        .Smoother,
    ),
    cinematic.hold(
        "reveal",
        1.25,
        wide_camera,
        cinematic.wipe(.Iris, .8),
    ),
    cinematic.hold("response", 1.5, close_camera),
}
script := cinematic.Script{id = "scene-id", shots = shots[:]}
```

Treat the numbers as starting points requiring visual review, not universal timing rules.
