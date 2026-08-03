# Bound sparse shoreline index generation

Status: open. Sparse draw integration reverted 2026-08-03 after visual regression.

## Goal

Keep sparse land rendering inexpensive as the number of persisted terrain pages
grows.

## Work

- Remove the per-cell linear scan of all `terrain_pages` performed through
  `sample_land` while constructing sparse clipmap indices.
- Use the already-computed visible-page set, a direct page lookup, or an
  equivalent bounded residency mask for land classification.
- Preserve cell-level shoreline rejection so coastal residency chunks do not
  render as rectangular terrain slabs over water.
- Measure clipmap regeneration near a coast with representative and worst-case
  terrain-page counts.
- Add correctness coverage for clipmap holes, camera detail-level changes, and
  coastline-crossing dirty updates.

## Acceptance

- Sparse index construction does not linearly search every persisted page for
  every candidate cell.
- Regeneration cost scales with visible clipmap cells and locally relevant
  pages, not total map page count.
- Shorelines remain free of rectangular land bleed and nested clipmap levels do
  not overlap or leave holes.
- A reproducible before-and-after benchmark records the improvement.

## Progress evidence

- Visible-page queries iterate intersecting page coordinates through
  `terrain_page_lookup`; they do not scan all persisted pages.
- `tools/terrain_page_lookup_bench.odin` measured 100,000 queries over 1,536
  pages at 81.449 ms for the legacy scan and 2.778 ms for the bounded lookup,
  a 29.32× improvement on 2026-08-03.
- The bounded page lookup and its terrain test remain. Sparse per-cell draw
  buffers were reverted because they produced level-sized rectangular terrain
  gaps in the live editor. A replacement must retain the established clipmap
  transition topology and pass live visual validation before completion.
