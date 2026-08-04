# Plant replacement performance report

Status: all six corrected plant workloads pass their absolute frame-time
budgets. A matched relative base exists for the gallery only; the earlier
`plant_transition` base accidentally measured the wheat-card lab and is not a
valid comparison for the corrected pine and oak plant corridors.

## Contract

- Profile: `m4-max-720p`
- Host: Apple M4 Max, arm64 macOS 25.5.0
- Repetitions: 3
- Warmup/sample frames: 90/360 per repetition
- Window/world resolution: 1280×720 / 854×480
- Base comparison: matched `b50a86d5` artifacts recorded on the same profile
- Updated comparison: dirty working tree at `2a5ac0e7`

## Results

| Scenario | Median | p95 | p99 | Max | Absolute budget |
|---|---:|---:|---:|---:|---:|
| Plant gallery | 8.297 ms | 9.221 ms | 9.434 ms | 9.510 ms | pass |
| Pine transition | 11.912 ms | 12.708 ms | 12.963 ms | 30.230 ms | pass |
| Oak transition | 8.252 ms | 8.908 ms | 16.604 ms | 20.718 ms | pass |
| Olive orchard | 8.191 ms | 8.868 ms | 9.235 ms | 30.831 ms | pass |
| Support-heavy climbers | 8.294 ms | 9.248 ms | 9.391 ms | 9.457 ms | pass |
| Largest runtime plant | 8.266 ms | 9.160 ms | 16.462 ms | 31.082 ms | pass |

The matched relative comparison is:

| Scenario | Metric | Base | Updated | Delta | Delta % | 5% gate |
|---|---:|---:|---:|---:|---:|---:|
| Plant gallery | median | 65.410 ms | 8.297 ms | −57.113 ms | −87.3% | pass |
| Plant gallery | p95 | 67.102 ms | 9.221 ms | −57.881 ms | −86.3% | pass |

The gallery now submits 189,404 world vertices (35,605 unique), down from
3,016,088 submitted vertices in the matched base. The bounded pine corridor
submits 358,136 indices (16,239 unique vertices); oak submits 253,796 indices
(21,646 unique vertices). Neither corrected transition scene emits foliage-card
geometry. The retained 96-tree lab targets remain available as visual stress
scenes, while benchmarks use 36 trees distributed across the full 348 m LOD
corridor.

## Generated asset size

- Manifest assets: 107 (35 reviewed catalog anchors, 64 residence pots, 8 airport planters)
- Total payload: 127,852,016 bytes
- Largest asset: 2,279,584 bytes
- Format v7: four mesh/organ payloads plus atlas-only Distant LOD with 8×3 color,
  alpha, and normal views
- `plant-compile` removes stale unreferenced `.plant` payloads from its selected
  output directory; the measurement contains exactly the manifest set

## Reproduction

```sh
make release
python3 tools/perf.py run --scenario plant_gallery --repeat 3 --output /tmp/adriatic-plant-current-gallery.json
python3 tools/perf.py run --scenario plant_transition --repeat 3 --output /tmp/adriatic-plant-current-transition.json
python3 tools/perf.py run --scenario plant_transition_oak --repeat 3 --output /tmp/adriatic-plant-current-transition-oak.json
python3 tools/perf.py run --scenario olive_orchard --repeat 3 --output /tmp/adriatic-plant-current-olive.json
python3 tools/perf.py run --scenario plant_climbers --repeat 3 --output /tmp/adriatic-plant-current-climbers.json
python3 tools/perf.py run --scenario plant_runtime_max --repeat 3 --output /tmp/adriatic-plant-current-runtime-max.json
```

Base artifacts retained from the matched pre-replacement run:

- `/tmp/adriatic-plant-before-gallery-focused.json`
- `/tmp/adriatic-plant-before-transition-focused.json` (wheat-card workload;
  retained for provenance, not used as a plant-transition comparison)
