# Mouse emote: sniff

## Goal

Create a mouse-specific scenting action that can idle or investigate a target.

## Motion brief

The mouse lifts its muzzle, samples the air with rapid nose twitches, makes two
small head searches, then settles. Ears independently track the search and the
chest breath subtly expands.

## Work

- Support a short one-shot sniff and an optional looping investigation hold.
- Add muzzle/nose twitch motion without scaling the whole head visibly.
- Layer small head search arcs, independent ear responses, whisker motion if the
  current model supports it, and restrained breathing.
- Accept an optional scent target to bias the search direction.
- Add deterministic trigger, capture coverage, and one-shot/loop/cancel tests.

## Acceptance

- Nose motion remains visible at gameplay distance without becoming cartoony
  vibration.
- The looping version has no perceptible seam.
- Targeted sniffing turns naturally and never overrides player facing abruptly.

