# Adriatic Instrumented 60 FPS

## Status

Current phase: **Phase 3 — Verify**

Plan state: draft approved for checkpoint creation. Milestone 1 is ready for
execution. Later milestones must not begin until Milestone 1 evidence is
recorded and accepted.

## Feature

Make Adriatic sustain 60 FPS in the instrument profile while retaining useful
function-level flame data and current rendering quality.

## Problem

The GPU is not the limiting resource. Recent instrument captures show two CPU
costs:

1. profiler bookkeeping and session export overhead from high-frequency leaf
   scopes;
2. per-frame world generation, dominated by aircraft geometry and detailed
   terrain-following aircraft shadows.

The existing `lkolpltw` change removed most useless leaf instrumentation:

- automatic slots fell from the 262,144-slot cap to about 6,139 slots per
  steady frame;
- raw steady frame time fell from roughly 87 ms to 22.34 ms;
- instrument benchmark median fell from 939.47 ms to 41.98 ms;
- `world_aircraft` remains about 16.93 ms of raw CPU time;
- GPU time remains about 2.9 ms and is not the current bottleneck.

The 41.98 ms wall-clock result came from a tiny 2-warmup/10-sample run. Its p95
is invalid because initialization leaked into the measured range. Milestone 1
must replace this provisional evidence with a reproducible baseline.

## Scope

In scope:

- deterministic instrument-profile measurement;
- profiler per-frame recording overhead;
- invariant vehicle transform and normal work;
- product-side Postale, Libellula, and Libellula Mk2 shadow geometry;
- validation, benchmark, and visual regression evidence.

Out of scope for the first pass:

- general GPU tuning while GPU time remains comfortably below budget;
- unrelated foliage, architecture, simulation, or audio optimization;
- visual quality reductions without deterministic capture evidence;
- product-specific behavior in `zelda-engine`;
- a GPU-resident vehicle renderer unless the midpoint gate proves it necessary.

## Dependencies and constraints

- Use the catermujo-compatible sidecars:
  `build/instrument/flame.scopes.ndjson`,
  `build/instrument/flame.frames.ndjson`, and
  `build/instrument/flame.folded`.
- Build and stage instrument assets together. A binary-only
  `instrument-build` can leave a stale or missing shader in
  `build/instrument`.
- Close benchmark runs normally so `flame_graph_destroy` exports the session.
  Do not use SIGINT or force-kill a capture that must be analyzed.
- Keep `zelda-engine` product-neutral.
- Use `jj` for every VCS mutation and inspect diffs with `--git`.
- Refer to revisions by jj change ID, not commit ID.
- Preserve unrelated working-copy changes in their own jj change.
- Do not use web search. The local source and local Aspera checkout are the
  allowed references.

## Success criteria

The feature is complete when all enabled instrument benchmark scenarios at
1280×720 with an 854×480 world render size satisfy the existing contract:

- median frame time: at most 16.667 ms;
- p95 frame time: at most 16.667 ms;
- p99 frame time: at most 20.0 ms;
- maximum frame time: at most 33.333 ms.

Additional gates:

- no automatic flame-slot overflow;
- profiler bookkeeping adds at most 3 ms to the raw frame time;
- GPU time remains below 8 ms at p95;
- instrument export completes normally and remains analyzer-readable;
- release benchmarks still pass;
- validation profile reports no ASAN or Vulkan validation error;
- aircraft shadows remain readable, continuous, terrain-following, and absent
  over water.

## Milestones

### Milestone 1 — Lock the instrument measurement protocol

Establish a reproducible baseline with correct runtime staging, enough warmup,
explicit evidence fields, and separate wall-clock and raw-frame measurements.

Acceptance criteria:

- three identical editor runs complete normally;
- each run uses 10 warmup frames and 30 measured frames;
- all required sidecars are fresh and non-empty;
- measured frames contain no renderer initialization;
- no frame reaches the 262,144 automatic-slot cap;
- the three wall-clock medians differ by at most 10%;
- evidence records wall, raw CPU, GPU, slot count, dump size, and export time;
- the accepted baseline is written into this file before Milestone 2 starts.

Detailed procedure appears in
[Milestone 1 execution](#milestone-1-execution).

### Milestone 2 — Batch profiler session writes

Replace per-slot session writes in `packages/dio/flame.odin` with one reusable
serialized frame buffer and one file write per completed frame.

Current `flame_graph_session_record` performs a record write plus roughly three
writes per slot. At 6,139 slots this is about 18,400 writes per frame, outside
the raw flame-frame interval but inside benchmark wall time.

Acceptance criteria:

- one session payload write per completed frame;
- no persistent per-frame allocation growth;
- session round-trip preserves frame IDs, nesting, source locations, names,
  timing, and GPU metrics;
- analyzer output remains valid;
- wall-clock median is no more than 3 ms above raw median;
- a 30-frame export finishes within 5 seconds.

Likely files:

- `packages/dio/flame.odin`;
- focused flame session tests if an existing test package can own them.

Expected commit description:

`profiling: batch session frame writes`

### Milestone 3 — Hoist invariant vehicle math

Remove repeated calculations from inner vehicle geometry loops without
changing submitted geometry.

Work:

- calculate a flat aircraft triangle normal once per triangle, not once per
  corner;
- calculate car and trailer sine, cosine, and transform bases once per frame;
- hoist paint layer, propeller blur, and other frame-invariant values outside
  triangle loops.

Acceptance criteria:

- visible vertex and triangle counts are unchanged;
- deterministic captures are pixel-identical or explain only floating-point
  noise;
- `world_car` is at most 0.5 ms raw;
- `world_aircraft` improves on the accepted Milestone 1 baseline;
- instrument build and relevant tests pass.

Likely files:

- `src/world_renderer.odin`;
- product-local vehicle transform helpers, only if needed.

Expected commit description:

`vehicles: hoist frame transform invariants`

### Milestone 4 — Use low-poly aircraft shadow proxies

Stop projecting every visible aircraft triangle through repeated terrain
samples. Build product-side low-poly shadow proxy meshes for Postale,
Libellula, and Libellula Mk2, then feed those proxies through the existing
terrain-following projection.

Keep detailed visible meshes unchanged. Do not move product shadow policy into
`zelda-engine`.

Acceptance criteria:

- both visible aircraft together submit at most 1,024 shadow triangles per
  frame;
- aircraft shadow projection is at most 1.5 ms raw;
- `world_aircraft` is at most 8 ms raw;
- shadows remain continuous on flat ground, slopes, and road crowns;
- shadows do not render over water;
- Postale, Libellula, and Libellula Mk2 captures are approved;
- world-vertex-count reduction is documented as intentional shadow LOD, not
  silent capacity loss.

Likely files:

- `packages/vehicles/` for product-local proxy data or builders;
- `src/world_renderer.odin` for proxy submission.

Expected commit description:

`shadows: project low-poly aircraft proxies`

### Midpoint sunk-cost gate

After Milestone 4, rerun the Milestone 1 protocol.

Continue only if the core behavior is demonstrable:

- raw p95 is below 14 ms;
- instrument wall median and p95 are at or near the 16.667 ms contract;
- `world_aircraft` is at most 8 ms;
- profiler overhead is at most 3 ms.

If these gates fail, stop and inspect the fresh dump. Do not continue adding
blind annotations or shadow approximations.

If visible aircraft geometry still costs more than 6 ms, inspect the local
Aspera source at `~/pjs/ws/cat_a/rt/gfx/aspera` for immutable GPU mesh and
per-object transform patterns. Record a design decision before starting a GPU
path.

### Milestone 5 — Conditional GPU-resident vehicle geometry

This milestone is skipped when the midpoint gate passes.

If required, keep immutable vehicle vertices in GPU buffers and submit
per-vehicle model and animation transforms instead of rebuilding the full
visible mesh on the CPU.

Acceptance criteria:

- a written design identifies buffer ownership, animation matrices, paint
  data, hot reload, and destruction;
- every created Vulkan object is named immediately;
- visible aircraft CPU generation is at most 3 ms;
- no product-specific policy enters `zelda-engine`;
- validation and all visual captures pass.

Expected commit description:

`vehicles: submit immutable GPU geometry`

### Milestone 6 — Final integration and regression gate

Run the final 90-warmup/360-sample instrument suite, release benchmarks,
validation profile, and deterministic shadow captures.

Acceptance criteria:

- every success criterion in this plan passes;
- all enabled instrument scenarios pass their budgets;
- release performance does not regress;
- ASAN and Vulkan validation remain clean;
- temporary diagnostics and experiment switches are removed;
- final jj diff contains only reviewed milestone work.

## Milestone 1 execution

### M1.1 — Preserve working-copy ownership

From the repository root:

```sh
rtk jj status
rtk jj diff --git
```

If `@` contains unrelated changes, leave them in place and start a clean child:

```sh
rtk jj new
rtk jj status
```

Record the relevant parent change ID:

```sh
rtk jj log -r '@-::@' -n 3
```

Do not amend, squash, or otherwise rewrite the existing `lkolpltw` leaf-churn
change during M1.

### M1.2 — Build and stage one coherent instrument runtime

Build the binary and stage current assets and generated shaders:

```sh
rtk make instrument-build build/instrument/runtime-assets.stamp
```

Preflight:

```sh
rtk test -x build/instrument/adriatic
rtk test -s build/instrument/shaders/grass.vert.spv
rtk test -d build/instrument/assets
```

If any preflight check fails, M1 is blocked. Do not run against partially
staged assets.

### M1.3 — Run the iteration capture

Use the deterministic editor scenario:

```sh
rtk env \
  -u VK_INSTANCE_LAYERS \
  -u VK_LOADER_LAYERS_ENABLE \
  ZELDA_ENGINE_GPU_PROFILER=1 \
  build/instrument/adriatic \
  --benchmark editor 10 30 1280 720 854 480
```

Required behavior:

- app prints one `BENCHMARK_RESULT`;
- app exits by itself;
- normal shutdown output appears;
- automatic export completes;
- no signal is sent to the process.

Measure export duration from `BENCHMARK_RESULT` until process exit. A slow
export is evidence, not permission to kill the process.

Run this exact capture three times. Preserve the numeric result from each run.
The dump files contain only the latest run, so analyze each run before starting
the next.

### M1.4 — Analyze each run

Run the source-of-truth analyzer:

```sh
rtk python3 tools/flame_dump.py \
  summary build/instrument/flame.graph --top 24

rtk python3 tools/flame_dump.py \
  spikes build/instrument/flame.graph --percentile 95 --top 20
```

Inspect the raw frame sidecar for frame IDs 10 through 39. These correspond to
the measured range after 10 warmup frames. Calculate:

- raw median, p95, p99, and maximum `total_ms`;
- average and maximum `len(slots)`;
- average and p95 GPU time using only `gpu_valid` frames;
- top aggregate self-time and call-count functions.

Use a streaming reader. Do not load the entire multi-gigabyte sidecar at once,
and do not print raw frame JSON to the terminal.

Explicitly check:

- no measured frame has 262,144 slots;
- `world_renderer_create` does not appear in measured frames;
- `vehicle_paint_atlas_create` does not appear in measured frames;
- GPU remains below the CPU budget;
- `world_aircraft` remains the largest product scope unless new data proves
  otherwise.

### M1.5 — Record evidence

Fill one row per run:

| Field | Run 1 | Run 2 | Run 3 |
|---|---:|---:|---:|
| jj parent change ID | | | |
| wall median ms | | | |
| wall p95 ms | | | |
| wall p99 ms | | | |
| wall max ms | | | |
| raw median ms | | | |
| raw p95 ms | | | |
| raw max ms | | | |
| GPU average ms | | | |
| GPU p95 ms | | | |
| slots/frame average | | | |
| slots/frame maximum | | | |
| `world_aircraft` average ms | | | |
| export duration seconds | | | |
| frames sidecar size | | | |
| folded sidecar size | | | |

Then record the accepted baseline:

```text
wall median = median(run wall medians)
wall p95    = maximum(run wall p95 values)
raw median  = median(run raw medians)
raw p95     = maximum(run raw p95 values)
GPU p95     = maximum(run GPU p95 values)
slot max    = maximum(run slot maxima)
```

### M1.6 — M1 pass/fail decision

M1 passes when:

- all three captures used identical arguments and current staged assets;
- all three exported normally;
- all evidence fields are complete;
- wall medians vary by no more than 10%;
- no measured frame includes renderer initialization;
- no measured frame reaches the slot cap;
- current bottleneck is stated from fresh data.

M1 fails when:

- assets were stale or incomplete;
- a process was force-killed;
- startup entered the measured range;
- one run is missing sidecars or GPU validity;
- results vary by more than 10% without an explained system event;
- the latest dump contradicts the assumed `world_aircraft` bottleneck.

On failure, fix only the measurement defect and repeat M1. Do not start M2.

### M1.7 — M1 handoff entry

Append this block after verification:

```text
Milestone 1: PASS | FAIL
Verified change ID:
Accepted wall median/p95:
Accepted raw median/p95:
Accepted GPU p95:
Accepted slot average/max:
Top three product scopes:
Export duration:
Measurement caveats:
Next milestone:
```

If M1 requires a tool or documentation change, keep that work in one change
and use:

`profiling: lock instrument baseline`

Do not create a code commit when M1 only records evidence in this plan.

## Progress log

### 2026-07-27

- Phase 1 problem, scope, dependencies, success criteria, and complexity
  confirmed from the performance handoff and repository contract.
- Phase 2 milestone ordering confirmed.
- Checkpoint draft created.
- Milestone 1 awaiting execution.
