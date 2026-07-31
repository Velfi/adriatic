# Mouse emote: point

## Goal

Create a directional pointing action that can target a world-space subject.

## Motion brief

The mouse looks toward the target, shifts weight away from the pointing side,
extends one forepaw, and holds a clear directional line from shoulder through
paw. The free paw braces and the tail counters the lateral lean.

## Work

- Extend emote parameters with optional world target and left/right paw choice.
- Convert the target into mouse-local yaw and elevation with sensible clamps.
- Blend head look, chest turn, shoulder reach, paw extension, and tail balance.
- Preserve a readable pose when the target is behind or nearly vertical by
  clamping and turning the body instead of twisting joints unnaturally.
- Add deterministic targets for capture and tests for target conversion,
  handedness, clamping, and cancellation.

## Acceptance

- Viewers can identify the intended target from the pose alone.
- The pointing paw does not stretch, detach, or pass through the head or chest.
- Moving targets can be followed smoothly during the hold phase.

