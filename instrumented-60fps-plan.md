# Adriatic Instrumented 60 FPS

## Status

Current phase: **Phase 3 — Verify**

Plan state: Milestones 1 and 2 are accepted. Milestone 3 is ready but has not
started.

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
- Milestone 1 executed with three timed editor captures on clean jj child
  `xmnzlnnk` (parent `wvpnnkqr`). Evidence is recorded in current jj change
  `xoxkmwsq` after concurrent repository operations moved the workspace base.

### Milestone 1 evidence — 2026-07-27

All runs used the same staged instrument binary and assets, with 10 warmup
frames and 30 measured frames at 1280×720 and an 854×480 world render. Each
run emitted one `BENCHMARK_RESULT`, exited with status 0, and completed the
flame export normally. Raw sidecar analysis used only frame IDs 10 through 39.

| Field | Run 1 | Run 2 | Run 3 |
|---|---:|---:|---:|
| jj parent change ID | `wvpnnkqr` | `wvpnnkqr` | `wvpnnkqr` |
| wall median ms | 40.8560 | 40.5773 | 41.2105 |
| wall p95 ms | 45.6898 | 49.4268 | 47.6035 |
| wall p99 ms | 47.4700 | 83.7277 | 49.9908 |
| wall max ms | 47.4700 | 83.7277 | 49.9908 |
| raw median ms | 21.9572 | 21.9651 | 21.9391 |
| raw p95 ms | 22.2209 | 22.4953 | 22.6712 |
| raw max ms | 22.3404 | 22.6137 | 22.9792 |
| GPU average ms | 0.9556 | 0.9340 | 1.1881 |
| GPU p95 ms | 2.5856 | 2.1759 | 2.3919 |
| slots/frame average | 5959.00 | 5959.00 | 5959.00 |
| slots/frame maximum | 5959 | 5959 | 5959 |
| `world_aircraft` average ms | 18.0094 | 18.0575 | 18.1090 |
| export duration seconds | 5.385204 | 5.394681 | 5.609026 |
| frames sidecar size | 168008125 | 168008125 | 168008123 |
| folded sidecar size | 79027713 | 79029930 | 79027911 |

Accepted baseline:

```text
Milestone 1: PASS
Verified change ID: xmnzlnnk
Accepted wall median/p95: 40.8560 ms / 49.4268 ms
Accepted raw median/p95: 21.9572 ms / 22.6712 ms
Accepted GPU p95: 2.5856 ms
Accepted slot average/max: 5959.00 / 5959
Top three product scopes: world_aircraft 18.0575 ms; world_car 1.3642 ms; animate_libellula_mesh_pose 1.3118 ms
Export duration: 5.394681 s median, 5.609026 s maximum
Measurement caveats: wall medians span 1.56%; run 2 has an 83.7277 ms wall spike while raw measured max is 22.6137 ms; raw wall overhead is approximately 18.9 ms at the accepted medians; macOS reports duplicate MoltenVK class names.
Next milestone: Milestone 2 — Batch profiler session writes
```

M1 checks passed: all three runs used identical arguments and current staged
assets; measured frames contain no `world_renderer_create` or
`vehicle_paint_atlas_create`; no frame reached the 262,144 automatic-slot cap;
all three required sidecars were fresh and non-empty. Fresh data confirms
`world_aircraft` as the main product scope and shows profiler/session overhead
as the large wall-versus-raw gap. The 60 FPS budget is not yet met; that is
work for later milestones.

### Milestone 2 evidence — 2026-07-27

Implementation is in jj change `mnzqlqtm` (`profiling: batch session frame
writes`), with `xoxkmwsq` sealed as its parent. `Flame_Graph` owns one reusable
`[dynamic]byte` buffer. Session recording validates all string lengths before
opening/writing, clears the buffer without releasing capacity, appends the
record/slot/name/path bytes in the existing order, performs one payload write,
and increments `session_frame_count` only after that write succeeds. The buffer
is deleted only during graph destruction.

Three exact editor captures used the M1 protocol after the implementation.
Each emitted one result, exited normally, produced fresh non-empty sidecars,
and was read successfully by `tools/flame_dump.py`:

| Field | Run 1 | Run 2 | Run 3 |
|---|---:|---:|---:|
| wall median ms | 22.5525 | 22.6057 | 22.5211 |
| raw median ms | 21.8690 | 21.9407 | 21.8921 |
| wall minus raw ms | 0.6835 | 0.6650 | 0.6290 |
| raw p95 ms | 22.3461 | 23.9808 | 22.4657 |
| GPU p95 ms | 2.0608 | 1.9550 | 0.5441 |
| slots/frame | 5959 | 5959 | 5959 |
| export duration seconds | 5.467021 | 6.629994 | 5.390063 |

Independent final-dump checks found 30 measured frames (`10..39`), 178,770
non-empty paths, 178,770 positive source lines, and 30 GPU-valid frames.
Frame IDs, nesting depth, names, paths, lines, timings, and GPU fields survived
the unchanged reader/export path. Static diff inspection finds exactly one
`flame_graph_session_write_bytes` call in `flame_graph_session_record`, outside
the slot loop. `make check` and all 319 `make test` tests pass.

M2 status: NOT ACCEPTED — implementation and wall/raw gate pass, but all three
export-to-exit measurements exceed the `5 s` acceptance limit (median
`5.467021 s`, maximum `6.629994 s`). The exporter/reader path was intentionally
left unchanged by scope, so no M3 work starts until this gate is resolved.

### Milestone 2 arena correction — 2026-07-27

The exporter now owns a local growing `virtual.Arena` initialized with a 1 MiB
first block. Session strings are read directly into the arena and returned as
strings without cloning. The arena resets only after frame, scopes, and folded
writers finish; slot names and paths are no longer individually deleted. The
dynamic slot buffer is deleted once at function exit, and the arena is destroyed
by defer on every export-thread exit path.

Corrected captures repeated the exact M1 protocol:

| Field | Run 1 | Run 2 | Run 3 |
|---|---:|---:|---:|
| wall median ms | 22.8800 | 22.4395 | 22.4688 |
| raw median ms | 22.2176 | 21.8025 | 21.8057 |
| wall minus raw ms | 0.6624 | 0.6370 | 0.6631 |
| raw p95 ms | 29.7108 | 22.4639 | 22.0560 |
| GPU p95 ms | 2.0482 | 4.6273 | 1.7303 |
| slots/frame | 5959 | 5959 | 5959 |
| export duration seconds | 6.543771 | 5.265456 | 5.231588 |

All corrected sidecars passed analyzer and independent checks: 30 measured
frames (`10..39`), max nesting depth 9, 178,770 non-empty paths, 178,770
positive source lines, and 5,959 slots per frame. `make check` and all 319
tests pass. M2 remains NOT ACCEPTED solely because corrected export-to-exit
measurements still exceed 5 seconds; median is `5.265456 s`, maximum is
`6.543771 s`. No M3 work starts.

### Milestone 2 leaf-scope correction — 2026-07-27

Fresh full-session analysis showed the remaining export load came from
automatic instrumentation of seven tiny terrain-clipmap leaves during startup.
Frames 1 and 2 each reached the 262,144-slot cap even though those warmup
frames were not part of the benchmark sample window. The functions now use
both `@(no_instrumentation)` and `#force_inline`:

- `clipmap_append_cell`;
- `clipmap_vertex_color`;
- `sample_material`;
- `sample_level_material`;
- `terrain_color`;
- `terrain_color_variation`;
- `color_lerp`.

Useful parent scopes remain visible: `world_renderer_create`,
`clipmap_create_indices`, `clipmap_update`, and `clipmap_update_level`.
A 3-warmup/7-measured diagnostic capture reduced frame 1 from 262,144 to
15,605 slots and frame 2 from 262,144 to 5,958 slots. Its export-to-exit time
was 0.555034 seconds.

Three exact M1 captures then passed every M2 gate:

| Field | Run 1 | Run 2 | Run 3 |
|---|---:|---:|---:|
| wall median ms | 22.4939 | 22.8741 | 22.5744 |
| wall p95 ms | 23.5613 | 29.0705 | 27.1890 |
| raw median ms | 21.851480 | 22.117438 | 21.951064 |
| raw p95 ms | 22.180980 | 24.380828 | 22.095337 |
| wall minus raw ms | 0.642420 | 0.756662 | 0.623337 |
| GPU p95 ms | 3.180706 | 2.801121 | 4.302167 |
| measured slots/frame | 5,956 | 5,956 | 5,956 |
| maximum slots, all frames | 15,605 | 15,605 | 15,605 |
| export duration seconds | 1.812440 | 1.787006 | 1.777243 |
| total sidecar bytes | 82,089,319 | 82,084,029 | 82,085,008 |

All captures exited normally, produced analyzer-readable sidecars, retained
frames 10 through 39 as the 30-frame measured range, and contained no measured
renderer initialization. `make check` passes, and all 319 tests pass.

M2 status: PASS — one session payload write is performed per frame, the
wall/raw gap remains below 3 ms, no frame reaches the automatic-slot cap, and
all three 30-frame exports finish below 5 seconds. Next milestone is
Milestone 3 — Hoist invariant vehicle math; it has not started.
