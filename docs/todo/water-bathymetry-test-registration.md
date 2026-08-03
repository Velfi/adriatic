# Register bathymetry editing tests correctly

Status: completed 2026-08-03.

## Goal

Ensure bathymetry editing behavior is exercised by independently registered
tests rather than hidden inside another test procedure.

## Work

- Move `bathymetry_area_edits_only_polygon_samples` to package scope.
- Audit `packages/terrain/bathymetry_test.odin` for any other accidentally
  nested or unregistered tests.
- Confirm the focused terrain test command reports both generated-bathymetry
  ownership and polygon-edit cases by name.
- Add boundary coverage for an edit crossing bathymetry chunk coordinates.

## Acceptance

- Every bathymetry test is declared at package scope and appears in test output.
- Polygon edits change samples inside the polygon and preserve samples outside.
- A cross-chunk polygon edit produces the same result on both sides of the
  chunk boundary.

## Completion evidence

- The current radial bathymetry API has package-scope inside/outside and
  shared-chunk-edge tests in `packages/terrain/terrain_pages_test.odin`.
- Generated bathymetry ownership remains covered by the near/distant island
  test.
- The focused three-test gate passes. The stash-era polygon API no longer
  exists, so its acceptance requirement was applied to the current bounded
  radial edit operation.
