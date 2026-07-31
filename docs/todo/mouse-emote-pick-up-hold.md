# Mouse emote: pick up and hold

## Goal

Create the reusable object-handling action for collecting, inspecting, offering,
and carrying small props.

## Motion brief

The mouse focuses on an object, reaches with both forepaws, draws it to a stable
chest-level hold, and tracks it with the head. The base action ends in a held
state that other interactions can branch from.

## Work

- Define an emote prop contract with world transform, grip points, size class,
  ownership/attachment transition, and release behavior.
- Author reach, grasp, lift, settle, held idle, lower, and release phases.
- Use two-paw contact targets or lightweight IK and blend shoulder/chest motion
  to avoid stretched limbs.
- Make held idle compatible with standing and seated bases.
- Handle cancellation without duplicating, dropping, or orphaning the prop.
- Add a simple deterministic test prop, capture coverage, and state/ownership
  tests for pickup, hold, interruption, and release.

## Acceptance

- Both paws remain attached to their grip points through the held phase.
- The prop transition between world and mouse ownership is visually seamless.
- Cancellation always leaves the prop in a valid, deterministic state.

