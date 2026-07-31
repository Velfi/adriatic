# Mouse emote: wave

## Goal

Create a friendly one-paw wave using the shared mouse emote runtime.

## Dependency

Complete [Mouse emote: foundation](mouse-emote-00-foundation.md) first.

## Motion brief

The mouse settles onto its haunches, raises its chest, plants one forepaw, and
waves the other two or three times. The head tilts toward the raised paw, the
ears perk, and the tail counterbalances the upright posture. The silhouette must
read clearly from the normal gameplay camera.

## Work

- Author wave-specific anticipation, performance, recovery, and blend-out curves
  through the shared pose interface.
- Add a stable player-facing trigger using the foundation's live-control and
  capture plumbing for deterministic development coverage.
- Suppress ordinary paw gait motion while each emote-controlled paw is weighted
  in; preserve grounding for the planted paws.
- Cancel and recover smoothly when movement or another incompatible state wins.
- Add unit tests for phase progression, repeat count, interruption, and return
  to neutral.
- Add a deterministic capture target showing front three-quarter and side views.

## Acceptance

- The paw completes two or three unmistakable wave arcs with no wrist or elbow
  discontinuity.
- Starting and stopping the emote produces no visible pop in body, paws, or tail.
- Movement interruption restores full player control immediately while the pose
  blends out.
- The action works with every fur pattern, scarf setting, and head accessory.
