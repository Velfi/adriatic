# Mouse emote: bow

## Goal

Create a polite, readable bow suitable for greetings and dialogue conclusions.

## Motion brief

The mouse draws one forepaw toward its chest, lowers head and shoulders from the
hips, holds briefly, then rises. Ears soften outward and the tail extends for
balance.

## Work

- Author anticipation, descent, hold, rise, and recovery pose curves.
- Keep the hind paws planted and derive chest, neck, and head offsets through the
  existing skeleton.
- Add a restrained forepaw-to-chest gesture and tail counterbalance.
- Ensure hats, ears, muzzle, scarf, and mailbag remain clear of the body.
- Add deterministic trigger, capture coverage, and phase/cancellation tests.

## Acceptance

- The gesture reads as a bow rather than sniffing or crouching.
- The head follows a smooth arc and never intersects the ground or chest.
- The held pose can be lengthened for dialogue without changing entry or exit.

