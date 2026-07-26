---
name: perf-anal
description: This skill should be used when the user asks to "analyze performance", "read flame instrumentation", "inspect flame dumps", "find frame spikes", or use the Adriatic instrument profile.
version: 0.1.0
---

# Adriatic performance analysis

Use the instrument profile to collect Odin function instrumentation, then use the
local flame analyzer to summarize frame cost, identify spikes, and inspect one
frame's scopes. Keep the output in catermujo's source-of-truth format so the same
analysis workflow works across both repositories.

## Collect a session

Build and launch the instrumented application:

```sh
make instrument
```

Exercise the scene or reproduce the slow operation. Close the application through
its normal quit path so `flame_graph_destroy` runs and exports the session. Avoid
SIGINT or force-kill when the export matters; process termination skips Odin
`defer` cleanup.

Automatic export covers the complete retained history, currently 180 completed
frames, without requiring a range selection.

The instrument build stages runtime assets in `build/instrument`. The application
changes its working directory to the executable directory, so the default dump
base resolves there:

```text
build/instrument/flame.graph
build/instrument/flame.scopes.ndjson
build/instrument/flame.frames.ndjson
build/instrument/flame.folded
```

`flame.graph` is the base name. The analyzer accepts the base name or either
NDJSON sidecar and resolves the sibling scopes sidecar automatically.

## Source format

Keep all instrumentation consumers on these sidecars:

- `flame.scopes.ndjson` starts with one `history_header` record, followed by one
  `frame_scopes` record per frame. Each scope record contains `other_ms`,
  `scope_count`, and aggregated colored scopes.
- `flame.frames.ndjson` starts with the same header, followed by one `frame`
  record per frame. Each frame contains raw nested slots with source locations,
  tick bounds, relative start time, and duration.
- `flame.folded` contains semicolon-separated folded stacks with performance-counter
  tick weights for standard flamegraph viewers.

Use `freq_hz` from the header when converting `start_ticks`, `end_ticks`, or
folded weights. Adriatic's current clock uses nanosecond ticks and emits
`freq_hz: 1000000000`; do not assume a machine-specific frequency.

## Analyze the session

Run the copied analyzer directly from the repository root:

```sh
python3 tools/flame_dump.py summary build/instrument/flame.graph --top 12
```

The summary reports frame count, average frame/FPS, CPU/wait/GPU averages, the
worst frame, top aggregated scopes, and worst frames. Feed the scopes sidecar
directly when path resolution needs to be explicit:

```sh
python3 tools/flame_dump.py summary \
    build/instrument/flame.scopes.ndjson \
    --top 16
```

Analyze spikes with the default p95 threshold:

```sh
python3 tools/flame_dump.py spikes build/instrument/flame.graph --top 20
```

Use an explicit percentile or a fixed frame-time threshold. Select one mode per
invocation:

```sh
python3 tools/flame_dump.py spikes build/instrument/flame.graph \
    --percentile 99 --top 20

python3 tools/flame_dump.py spikes build/instrument/flame.graph \
    --ms 20 --top 20
```

Inspect a particular frame after obtaining its ID from `summary` or `spikes`:

```sh
python3 tools/flame_dump.py frame build/instrument/flame.graph \
    --frame-id 1842 --top 24
```

Accept the original odd-style single-dash spellings when reproducing an old
command, for example `-path`, `-top`, `-p`, `-ms`, and `-frame_id`.

## Read results

Start with `summary` to establish whether the problem is broad frame cost or a
small number of spikes. Compare `avg frame` with `worst frames`; a large gap
indicates bursty work. Compare `cpu`, `wait`, `gpu`, and `other` before changing
code. Use `top scopes` for repeated cost and `frame` for one bad frame's nested
scope breakdown.

Treat `other_ms` as unbucketed frame time. It is not an additional measured
function; it is the remainder after the exported scope buckets. Treat GPU time
as unavailable unless `gpu_valid` is true.

Use `flame.frames.ndjson` when source-location nesting is needed. Use
`flame.scopes.ndjson` for fast aggregate reports. Use `flame.folded` when opening
the data in a standard folded-stack viewer.

## Troubleshoot missing output

Check the following in order:

1. Confirm that `make instrument` completed and that the instrument binary is
   `build/instrument/adriatic`.
2. Confirm that the application ran at least one completed frame.
3. Close normally; Ctrl-C does not execute shutdown export cleanup.
4. List `build/instrument` and check for `flame.scopes.ndjson`.
5. Pass the absolute sidecar path to `tools/flame_dump.py` if the shell is not at
   the repository root.

Do not analyze `flame.graph.json` as the primary artifact. It is a legacy debug
export retained for the in-app developer button; the automatic instrument export
is the catermujo-compatible NDJSON plus folded set.

## Additional resources

- **`tools/flame_dump.py`** - Local analyzer implementing `summary`, `spikes`,
  and `frame` commands against the source-of-truth sidecars.
