# Mouse emote: sleep

## Goal

Create a restful lying-down state with a seamless sleeping idle and clean wakeup.

## Motion brief

The mouse circles or checks its resting spot, lowers its chest and haunches,
curls its body and tail, rests its head near the forepaws, and settles into slow
breathing with occasional ear twitches. Wakeup reverses the weight carefully,
then finishes with a stretch.

## Work

- Author settle, curl, head-down, sleeping loop, wake, stretch, and stand phases.
- Ground the body, head, paws, and tail against sampled terrain without flattening
  the procedural body volume.
- Add slow breathing, rare ear/tail twitches, and deterministic variation.
- Define immediate and gentle wake paths for gameplay interruption versus authored
  scenes.
- Prevent ordinary idle look and locomotion channels from leaking into sleep.
- Add deterministic trigger/capture coverage and tests for loop seams, wake modes,
  terrain placement, and interruption.

## Acceptance

- The sleep loop has no visible seam and does not drift across the ground.
- Breathing and twitches are subtle, deterministic, and compatible with scarves.
- Immediate wake restores control promptly; gentle wake completes without pops.
