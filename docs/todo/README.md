# Mouse emote animation backlog

Complete the foundation before beginning the first production set. Later actions
must extend the shared pose and playback interfaces rather than add one-off
player state.

0. [Emote foundation](mouse-emote-00-foundation.md)
1. [Wave](mouse-emote-wave.md)
2. [Cheer](mouse-emote-cheer.md)
3. [Bow](mouse-emote-bow.md)
4. [Point](mouse-emote-point.md)
5. [Shrug](mouse-emote-shrug.md)
6. [Sniff](mouse-emote-sniff.md)
7. [Curious head tilt](mouse-emote-curious-head-tilt.md)
8. [Surprised recoil](mouse-emote-surprised-recoil.md)
9. [Sit](mouse-emote-sit.md)
10. [Groom](mouse-emote-groom.md)
11. [Pick up and hold](mouse-emote-pick-up-hold.md)
12. [Sleep](mouse-emote-sleep.md)

Shared requirements:

- Emotes blend into and out of the procedural locomotion pose without popping.
- Locomotion, becoming airborne, entering a vehicle, and other incompatible
  gameplay states cancel an emote cleanly.
- Head, ears, paws, body, and tail remain procedural channels; emotes contribute
  offsets and weights rather than replacing the mouse renderer.
- Every emote can be triggered deterministically for capture and visual QA.
- Add focused tests for timing, cancellation, looping, and state transitions.
- Do not serialize transient playback state into fixtures or preferences.

Implementation note: `src/world_renderer.odin` currently has unrelated local
changes. Preserve or isolate that work before starting the foundation because
the pose extraction will overlap the mouse-rendering section of that file.

