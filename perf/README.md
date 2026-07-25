# Adriatic performance scenarios

`tools/perf.py` runs deterministic renderer scenarios through the release app,
collects frame-time distributions, and checks the configured budgets.

```sh
python3 tools/perf.py run --scenario foliage --repeat 3 \
  --output /tmp/adriatic-foliage-perf.json

python3 tools/perf.py run --scenario all --output /tmp/adriatic-perf.json
```

Build `build/release/adriatic` first with `make release`, or pass `--build`.
Each run uses the configured window size, internal world-render size, warmup,
sample count, and absolute budgets from `perf/scenarios.json`.

Results also retain peak world-mesh, road-mesh, and foliage-card vertex counts
with capacity utilization. These counters make geometry-heavy changes auditable:
a passing frame time is not sufficient if the scene silently reaches a mesh
capacity and drops later geometry.

The built-in scene registry currently supports `editor`, `foliage`,
`foliage_forest`, `foliage_understory`, `foliage_stress`, `formations`, `roads`,
and `architecture`. Add a deterministic scene seed in `benchmark_seed_scene`
and a configuration entry to extend the suite.

The 60 FPS contract is expressed primarily through the 16.667 ms median and
p95 budgets. The looser p99 and maximum limits retain evidence of isolated
hitches instead of averaging them away.
