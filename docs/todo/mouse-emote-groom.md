# Mouse emote: groom

## Goal

Create a characteristic face-washing and fur-grooming sequence.

## Motion brief

From sitting, the mouse licks or prepares both forepaws, rubs them over its muzzle
and cheeks in alternating passes, flicks its ears, then lowers its paws with a
satisfied shake.

## Work

- Build on the seated posture and add a multi-pass grooming sequence.
- Coordinate paired paw contact with muzzle, cheeks, forehead, and ear bases.
- Add head reactions, blinking if available, ear flicks, breathing, and a small
  finishing shake.
- Use authored contact targets or lightweight IK so paws follow the posed head.
- Check all headgear variants and shorten or redirect passes that would intersect.
- Add deterministic captures and tests for contact order, looping, and cancel.

## Acceptance

- Paw-to-face contacts stay attached through head motion without visible gaps.
- The sequence reads as grooming even without sound effects.
- Headgear and scarf combinations do not create obvious intersections.

