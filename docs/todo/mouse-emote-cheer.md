# Mouse emote: cheer

## Goal

Create a joyful full-body celebration using the shared emote runtime.

## Motion brief

The mouse compresses, springs into a small hop with both forepaws high, lands
softly, and finishes with an eager chest-up bounce. Ears rise on takeoff and the
tail sweeps down and back to support the jump.

## Work

- Add a cheer pose track with anticipation, takeoff, airborne peak, landing,
  rebound, and recovery beats.
- Coordinate the emote with grounded and airborne player state without applying
  unintended gameplay velocity.
- Drive both forepaws symmetrically, then introduce a small asymmetry at the
  finish to avoid a mechanical silhouette.
- Add landing compression and secondary ear, scarf, body-softness, and tail
  response.
- Add deterministic trigger and capture coverage.
- Test completion, interruption during each beat, and neutral recovery.

## Acceptance

- The action reads as celebration in silhouette with effects and UI disabled.
- Feet neither penetrate the ground nor imply a gameplay jump that did not occur.
- Landing compression settles without oscillation or a pose snap.

