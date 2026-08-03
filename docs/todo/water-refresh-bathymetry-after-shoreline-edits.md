# Refresh bathymetry after shoreline edits

Status: completed 2026-08-03.

## Goal

Keep the shallow seabed continuous with the authored coastline after terrain
sculpting, undo, and redo.

## Work

- Define the ownership rule for generated bathymetry versus explicitly authored
  harbor, river, estuary, and dredged bathymetry.
- Rebuild or patch terrain-derived bathymetry samples inside bounded shoreline
  edit regions.
- Preserve explicitly authored underwater edits when the generated coastal bed
  is refreshed.
- Update bathymetry revisions and renderer invalidation exactly once per
  committed terrain operation.
- Apply the same refresh behavior to commit, cancel, undo, redo, and semantic
  terrain-layer reevaluation paths.
- Add tests for coast advance, coast retreat, chunk boundaries, authored-bed
  preservation, and exact undo/redo restoration.

## Acceptance

- Moving a coastline cannot leave former land elevations submerged as stale
  seabed or expose stale underwater shelves as land.
- The terrain-to-bathymetry transition is continuous within the intended coastal
  tolerance after editing and history operations.
- Authored harbor and dredged depths survive unrelated shoreline edits.
- Refresh work is bounded to affected coastal chunks rather than rebuilding all
  bathymetry.

## Completion evidence

- Ocean chunks are terrain-derived and refreshable; harbor and river chunks are
  authored and preserved as complete chunks.
- Brush and sculpt commits refresh intersecting generated samples. Undo, redo,
  and semantic full-terrain invalidation refresh generated bathymetry once.
- Sculpt previews never mutate bathymetry, so cancel retains the pre-gesture
  committed bed without refresh work.
- Tests cover coast advance and retreat, bounded revisions, shared chunk edges,
  and authored-bed preservation. All 28 terrain package tests pass.
