---
name: cutscene-design
description: Design, revise, analyze, storyboard, and implement Adriatic cutscenes and cinematic sequences, including dialogue beats, actor blocking, camera framing and movement, shot timing, focal length, easing, cuts, wipes, transitions, gameplay handoffs, skip behavior, and implementation-ready shot scripts. Use when the user asks for a cutscene, cinematic, scripted scene, camera sequence, shot list, storyboard, in-engine dialogue scene, reveal, montage, arrival, departure, or transition between gameplay and authored presentation.
---

# Cutscene Design

Design cutscenes as playable, economical sequences in which performance, camera, dialogue, sound, and state changes serve the same dramatic turn.

## Establish context

1. Read `README.md` and the relevant story, location, character, quest, and scene sources. Treat checked-in behavior and text as canon.
2. Read `references/adriatic-cinematics.md` before designing against or changing the current cinematic runtime.
3. Read `references/cutscene-blueprint.md` when producing a beat sheet, shot list, storyboard, implementation plan, or code-ready specification.
4. Use `$autowriter` for substantial new dialogue or voice-sensitive prose. Retain ownership of staging, timing, camera grammar, transitions, and synchronization.
5. Inspect current spatial anchors and runtime integration before choosing exact camera coordinates. Prefer deriving cameras from actors, props, and stable world anchors over unexplained absolute coordinates.

## Build the dramatic spine

- State the scene's entry condition, dramatic question, turning point, exit state, and player-facing purpose.
- Give every shot one primary job: orient, reveal, connect, intensify, release, or hand control back.
- Enter late and leave early. Remove coverage that repeats information without changing tension, knowledge, relationship, or state.
- Stage visible actions around concrete Adriatic details: aircraft, boats, tools, parcels, food, weather, stone, canvas, lamps, gardens, and civic work.
- Preserve player agency. Do not assign unchosen feelings or identity to the player character; show observable action and consequence.

## Direct performance and camera together

- Block actors and props before selecting coverage. Record who moves, where attention shifts, and what must remain legible.
- Motivate camera movement with a reveal, changing relationship, actor motion, or transfer of attention. Prefer a hold when movement adds no information.
- Establish geography before close coverage unless confusion is intentional.
- Keep targets near the active subject and check foreground occlusion, terrain, clipping, horizon, and screen direction.
- Use focal-length changes deliberately; avoid simultaneous aggressive travel, reframing, and lens change unless disorientation is the point.
- Favor `.Smoother` for authored arrivals and settles, `.Smooth` for ordinary reframing, and `.Linear` only for mechanical or intentionally constant motion.
- Treat cuts as invisible changes in viewpoint. Use a wipe only when the transition itself conveys passage, concealment, punctuation, or a graphic match.

## Integrate dialogue and action

- Split speech at changes in speaker, intention, visual focus, or action. Do not cut merely because a sentence is long.
- Let important lines begin after the viewer has found the relevant face or object.
- Protect punch lines, revelations, and choices from competing camera movement or transition masks.
- Specify whether dialogue is automatic, timed, input-advanced, branching, or interruptible. Never imply synchronization that the current systems cannot provide.
- Keep player choices readable and camera-neutral until selection. After selection, branch state and presentation explicitly.

## Design transitions and control handoff

- Define entry from gameplay: trigger, camera source, player/vehicle state, UI treatment, and input policy.
- Define exit to gameplay: final camera, restored or new player pose, quest/state effects, dialogue state, UI, and input restoration.
- Specify skip behavior and the authoritative end state. Skipping must apply required state changes exactly once and land in a valid camera and control state.
- Account for interruption, missing actors or anchors, replay, save/load, and failure to start. Prefer a safe fallback over a partially active cinematic.
- Identify audio cues and silence as timed events, but do not claim frame-accurate audio support unless it exists in the inspected implementation.

## Match the current runtime

- Use only supported primitives when the request is implementation-ready: `cinematic.camera`, `cinematic.move`, `cinematic.hold`, `cinematic.wipe`, `Script`, playback, and sampling.
- Distinguish a cut from a wipe: adjacent shots without `wipe_out` cut at the boundary; `wipe_out` overlaps the outgoing and incoming views.
- Keep authored shot storage alive for the full playback lifetime because scripts borrow their shot slices.
- Mark dialogue cues, actor animation, event tracks, branching, camera shake, letterboxing, audio synchronization, and generalized skip as new scope unless inspection finds a newer implementation.
- Keep product-specific rules and presentation in Adriatic. Do not move them into `zelda-engine`.
- If implementation changes any state reachable from `Fixture`, invoke `$fixture-state` before editing.

## Produce the artifact

Match the user's requested format. Otherwise provide:

1. A one-sentence scene purpose.
2. Entry conditions and exit state.
3. A timed beat sheet.
4. An implementation-ready shot table using the schema in `references/cutscene-blueprint.md`.
5. Dialogue or dialogue placeholders, with `$autowriter` used for substantive prose.
6. Required state/events, unsupported capabilities, and fallback behavior.
7. A compact validation plan.

When asked to implement, edit the relevant code, validate in proportion to risk, and use `$capture-adriatic` to render a deterministic review artifact when visual inspection is useful. Use `$hotshot` only when the user asks to inspect the already-running game.

## Final pass

- Verify continuity, geography, eyelines, screen direction, camera clearance, timing, and transition intent.
- Confirm that each spoken beat has enough reading time and that important visuals are not masked by UI or wipes.
- Confirm entry, completion, skip, interruption, and replay all converge on valid, explicit state.
- Separate implemented behavior from proposals. Call out every new engine or content requirement.
- Tighten the sequence until every shot earns its duration.
