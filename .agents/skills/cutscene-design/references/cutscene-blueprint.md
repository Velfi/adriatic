# Cutscene blueprint

Use this schema for a design that another contributor can implement without inventing missing behavior.

## Header

- **ID:** stable machine-friendly scene id
- **Purpose:** one sentence describing the player-facing dramatic change
- **Trigger:** exact quest, interaction, location, or state condition
- **Entry:** player/vehicle pose, camera source, actors, props, UI, audio, and input state
- **Exit:** authoritative world/quest/dialogue state plus camera, UI, audio, and input restoration
- **Duration:** target total and acceptable range
- **Playback:** one-shot/replayable; automatic/input-advanced; skippable/unskippable

## Timed beat sheet

Describe the sequence in dramatic beats before decomposing it into camera shots:

| Time | Beat | Visible action | Dialogue/audio | State/event |
|---:|---|---|---|---|
| 0.0–1.5 | Orient | … | … | … |

Use approximate time ranges. The beat sheet owns dramatic synchronization; the shot table owns camera implementation.

## Shot table

| ID | Time/duration | Job | Framing and subjects | Camera from → to | Lens | Ease | Dialogue/action cue | Transition | Implementation |
|---|---:|---|---|---|---:|---|---|---|---|
| `arrival-wide` | 1.35 s | Orient | … | anchor-relative positions and targets | 1.45 | Smoother | … | Cut | `cinematic.move` |

For every shot:

- Give it a stable, semantic id.
- State the single dramatic job.
- Identify active and protected screen regions.
- Express camera placement relative to stable subjects or anchors when exact coordinates are not yet measured.
- Record position, target, and focal length when values are known.
- Separate camera duration from dialogue duration when they differ.
- Name the transition and explain why it is visible; use `Cut` by default.
- Mark unsupported action/event synchronization as integration work.

## Dialogue and performance track

For each cue, specify speaker, text or placeholder, start rule, advance rule, actor action, look target, and interruptibility. Use node or cue ids that can remain stable through prose revisions.

Substantial new dialogue should be authored with `$autowriter`; the shot plan should not depend on an exact sentence duration until the final text is available.

## Control and state contract

Define:

- Start validation and failure fallback.
- Input policy during playback.
- UI/HUD visibility.
- Camera ownership and saved pose.
- Gameplay, quest, inventory, and dialogue effects.
- Normal completion behavior.
- Skip behavior and the exact end state it applies.
- Interruption behavior.
- Replay and save/load behavior.
- Cleanup and idempotency: required effects occur exactly once.

## Review checklist

- Capture representative frames at the start, midpoint, transition boundary, and end.
- Check multiple aspect ratios or safe areas when UI/dialogue is present.
- Check near/far actor and prop placements if anchors can vary.
- Step across shot boundaries and wipe halves to detect pops.
- Verify camera restoration, controls, UI, state effects, skip, and replay.
- Review without dialogue audio, then with the final dialogue timing.
