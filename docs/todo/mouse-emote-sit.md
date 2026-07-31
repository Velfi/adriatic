# Mouse emote: sit

## Goal

Create a stable seated posture that can host other upper-body emotes.

## Motion brief

The mouse lowers its pelvis onto its haunches, brings the forepaws beneath the
chest, straightens the upper body, and wraps or rests the tail alongside it.

## Work

- Implement sit as a held posture with enter, idle, and exit phases.
- Solve hindquarter compression and forepaw placement against terrain height.
- Add seated breathing, small weight shifts, ear motion, and tail settling.
- Define upper-body channel masks so wave, sniff, groom, point, and hold can layer
  over the seated base.
- Exit smoothly into idle or locomotion without foot sliding.
- Add deterministic capture and tests for layering, interruption, and terrain.

## Acceptance

- The pelvis visibly rests on the haunches without sinking through the ground.
- Seated idle loops seamlessly and remains alive without constant large motion.
- Supported upper-body emotes can play without disturbing seated grounding.

