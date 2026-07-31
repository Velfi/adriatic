# Mouse emote: foundation

Status: completed 2026-07-31.

## Goal

Create the transient playback, composable pose, development-control, and visual
test infrastructure required by every production mouse emote. This task should
not add a finished player-facing emote.

## Preparation

- Inspect and preserve the existing unrelated changes in `src/world_renderer.odin`
  before editing its mouse-rendering section.
- Record baseline captures of player idle, walk, run, jump/fall, turn, brake,
  posted idle, driving, and customization preview poses.
- Identify which current player animation fields are transient and confirm that
  the new runtime will remain outside fixture and preference serialization.

## Playback runtime

- Define a stable `Mouse_Emote` identity for no emote and the twelve planned
  production actions without coupling playback logic to UI labels.
- Add transient playback state containing the active action, elapsed time,
  normalized phase, blend weight, loop count, cancellation state, handedness,
  optional local/world attention target, and deterministic variation seed.
- Define shared anticipation, performance, hold/loop, recovery, and blend-out
  semantics.
- Provide start, cancel, update, active, and completion operations with tests.
- Define replacement behavior when a new emote starts during another emote.
- Keep runtime state explicitly excluded from fixture and hot-reload persistence.

## Composable pose interface

- Define a `Mouse_Emote_Pose` contribution that can express:
  - pelvis, spine, chest, neck, and head position/rotation offsets;
  - independent left/right ear offsets and rotations;
  - independent forepaw and hind-paw targets or procedural offsets;
  - tail base, curl, lift, and tip behavior;
  - body height, compression, breathing, blink, and idle-motion weights.
- Include per-channel weights so an emote can control one region without
  replacing the entire procedural mouse pose.
- Extract the necessary inline pose calculations from `world_mouse_model` behind
  narrow helpers while preserving existing output at zero emote weight.
- Add corresponding tail inputs through `player_tail` rather than duplicating
  tail simulation inside emote code.
- Preserve planted-paw grounding for channels not owned by the emote.

## Ownership and priority

- Document and implement the initial priority order:
  1. vehicle and incompatible gameplay poses;
  2. airborne or urgent movement recovery;
  3. emote-owned channels;
  4. ordinary locomotion;
  5. idle secondary motion.
- Define cancellation thresholds for movement intent, actual velocity, becoming
  airborne, entering a vehicle, pausing, and leaving player control.
- Support channel masks so later work can layer upper-body actions over sitting.
- Ensure cancellation restores gameplay control immediately while visual pose
  recovery may blend over a short bounded interval.

## Development controls

- Add deterministic live-control commands to start and cancel an emote by name.
- Support left/right handedness, fixed variation seed, optional target position,
  normalized-time scrubbing, and playback freeze.
- Add capture plumbing for emote name, phase/time, handedness, target, and view.
- Provide standard front, three-quarter, and side camera presentations without
  requiring gameplay input.
- Return useful validation errors for unknown actions or invalid parameters.

## Visual test matrix

- Create a lightweight emote lab or equivalent deterministic capture target.
- Cover all headgear, scarf enabled/disabled, mailbag enabled/disabled, and at
  least representative light/dark fur combinations.
- Cover flat ground, a mild slope, standing idle, seated-base compatibility,
  and movement interruption.
- Make comparison captures easy to produce without restarting the live editor.

## Tests

- Test phase progression, looping, completion, cancellation, replacement,
  handedness, deterministic variation, target conversion, and channel masks.
- Test that a zero-weight or inactive emote produces the existing neutral pose.
- Test that runtime state is reset during player placement and other existing
  transient animation resets.
- Run the existing animation and fixture tests after integration.

## Acceptance

- Existing locomotion, idle, airborne, driving, customization, and NPC mouse
  poses are visually unchanged when no emote is active.
- A synthetic test pose can independently move each supported channel and blend
  cleanly from zero to full weight and back.
- Start, cancel, replace, freeze, and scrub behavior is deterministic and covered
  by focused tests.
- Movement and incompatible gameplay states always win without visible popping
  or delayed player control.
- The capture matrix can render an arbitrary synthetic pose from the three
  standard views with the required accessory combinations.

## Completion evidence

- `src/mouse_emote.odin` defines the stable action identities, transient
  playback state, shared phases, replacement/cancellation rules, channel masks,
  target conversion, deterministic variation, and identity/synthetic poses.
- `src/mouse_emote_player.odin` enforces gameplay, vehicle, airborne, pause, and
  player-control priority from the global frame path.
- `world_mouse_model` consumes weighted position and pitch/yaw/roll offsets for
  all five body bones, independent ear transforms, four paw offsets/contact
  ownership values, secondary-motion weights, and tail rendering offsets.
- `player_tail` consumes the shared tail direction and lift before simulation;
  no duplicate emote tail solver was introduced.
- Root `Editor.mouse_emote` remains outside `Fixture` and is reset by player
  placement and full game reset. Fixture schema check, Editor load/store, and
  fixture lifecycle gates pass.
- Live control and the Adriatic MCP expose start, replace, cancel, freeze, scrub,
  handedness, target, seed, and loop controls with parameter validation.
- Capture accepts emote, time, hand, seed, target, headgear, scarf, mailbag, and
  ground-normal overrides. Evidence is under
  `build/captures/mouse-emote-foundation/` and includes three standard views,
  every headgear value, scarf/mailbag combinations, both hands, and a mild slope.
- Nine no-emote before/after captures are under
  `build/captures/mouse-emote-foundation-baseline/` and
  `build/captures/mouse-emote-foundation-post/`. Pixel deltas remained below
  0.34% while the worktree and ZE revision were changing concurrently.
- Seven standalone runtime tests and eight integrated runtime/player-placement
  tests pass. `make check` and the current Vulkan build pass.
- The full repository suite was attempted and remains red in unrelated existing
  airport-stamp, v7-to-v8 fixture-migration, and settlement generation tests.
