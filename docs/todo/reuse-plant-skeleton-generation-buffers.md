# Reuse plant skeleton generation buffers

Status: open. Research completed 2026-08-03.

## Goal

Eliminate repeated dynamic-array growth allocations while generating temporary
plant skeletons without sacrificing contiguous storage, clear ownership, or
bounded memory use.

## Context

- `lsystem.Plant` owns append-only dynamic arrays of segments and leaves.
- Skeleton generation currently starts those arrays empty and destroys them
  after `plants.generate` converts the temporary skeleton into a persistent
  `Generated_Plant`.
- Allocation tracking attributes 10,440,688 allocations and 67.74 GiB of
  cumulative traffic to the leaf append in
  `packages/plants/plants_skeletons_shrubs.odin`.
- The reported 384 B through approximately 24 KiB allocation sizes match Odin's
  geometric dynamic-array capacities for a 48-byte `lsystem.Leaf`: 8, 24, 56,
  120, 248, and 504 elements.
- Individual leaves have no independent lifetime, stable identity, or removal
  behavior. Do not replace the arrays with `core:container/handle_map` or an
  element free-list pool.

## Work

- Add a narrowly owned skeleton-generation workspace containing reusable
  `[dynamic]lsystem.Segment` and `[dynamic]lsystem.Leaf` buffers.
- Make skeleton generation populate borrowed workspace storage instead of
  unconditionally creating newly owned arrays.
- Reset reused arrays with `clear` so capacity survives between generations;
  delete the buffers only when their owning workspace is destroyed.
- Preserve the existing `Interpret_Result` error behavior while making
  ownership explicit on every success and error path. No slice or element
  pointer may escape after the workspace is released or reset.
- Use one workspace for synchronous generation. If generation is concurrent,
  use one workspace per worker or per maximum concurrent job; do not introduce
  a contended global pool.
- Add species/detail-aware initial capacity estimates or observed high-water
  estimates and use `non_zero_reserve` because append fully initializes each
  element.
- Define a measured retention policy for unusually large buffers. Discard an
  oversized buffer after its job when retaining it would materially exceed the
  normal high-water capacity; do not shrink ordinary buffers after every use.
- Keep the final `Generated_Plant` arrays independently owned by their current
  cache and destruction path.
- Do not add a generation arena unless measurement shows substantial remaining
  heterogeneous temporary allocation traffic after buffer reuse. If an arena
  is evaluated, reserve the two main arrays so resize operations do not strand
  superseded buffers until arena reset.

## Benchmark

Compare matched workloads for:

1. current allocate/grow/delete behavior;
2. capacity reservation with deletion after each generation;
3. reusable workspace buffers with `clear` and initial reservation.

Record for each variant:

- generation wall time;
- allocation and resize counts;
- cumulative allocated bytes;
- peak live bytes;
- retained workspace capacity after warm-up;
- segment and leaf length/capacity by species, maturity step, and detail level.

Include ordinary catalog/cache generation, repeated Plant Generator Lab edits,
and the species/detail combination with the largest skeleton. Run enough
iterations to separate warm-up allocations from steady-state behavior.

## Tests

- Verify generated segments, leaves, attachments, bounds, and errors are
  identical before and after reuse for representative seeds across every
  species and detail level.
- Verify repeated generation does not retain data from the previous plant.
- Exercise early returns for invalid support, interpretation failure, segment
  limit, and attachment limit without deleting borrowed workspace buffers or
  leaking persistent results.
- Verify two concurrent workspaces cannot alias storage if concurrent
  generation is supported.
- Verify oversized-buffer eviction returns retained capacity to the configured
  range.

## Acceptance

- After workspace warm-up, repeated generation that stays within its retained
  high-water capacities performs no segment or leaf backing-store allocations.
- Allocation tracking no longer reports the shrub leaf append as a dominant
  steady-state allocator.
- Generated plant output and error behavior remain deterministic and unchanged.
- Temporary buffers remain contiguous and iteration requires no handle lookup
  or pointer chasing.
- Workspace ownership, reset timing, concurrency rules, and oversize retention
  policy are documented next to the implementation.
- A reproducible before-and-after benchmark records both allocation reduction
  and wall-time impact; do not mark complete on allocation counts alone if the
  matched workload regresses materially.

## Research basis

- Odin `clear` resets dynamic-array length while retaining its allocation;
  `non_zero_reserve` establishes capacity without requesting zeroed spare
  memory.
- Fixed-size pools are suited to independently allocated and freed nodes, not
  append-only contiguous arrays with one shared lifetime.
- Arena allocation is appropriate for heterogeneous allocations sharing a bulk
  lifetime, but dynamic-array resizing in a monotonic arena can retain obsolete
  backing buffers until reset. Buffer reuse directly addresses this workload
  with less ownership machinery.
