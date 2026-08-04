# Plant replacement performance report

Status: in progress. These measurements cover the first two deterministic
plant scenarios; the remaining acceptance matrix is not yet complete.

## Contract

- Profile: `m4-max-720p`
- Host: Apple Silicon (`arm64`), macOS
- Repetitions: 3
- Warmup/sample frames: 90/360 per repetition
- Window/world resolution: 1280×720 / 854×480
- Base: `b50a86d5` exported to `/tmp`, with only the benchmark scenario and
  foreground-control harness copied from the working tree
- Updated: dirty working tree based on `b50a86d5`
- Both benchmark windows were explicitly foregrounded before sampling.

## Matched results

| Scenario | Metric | Base | Updated | Delta | Delta % | Relative gate |
|---|---:|---:|---:|---:|---:|---:|
| Plant gallery | median | 65.410 ms | 65.755 ms | +0.345 ms | +0.53% | pass |
| Plant gallery | p95 | 67.102 ms | 67.611 ms | +0.509 ms | +0.76% | pass |
| Plant gallery | p99 | 67.884 ms | 68.108 ms | +0.224 ms | +0.33% | — |
| Plant gallery | max | 70.027 ms | 69.322 ms | −0.705 ms | −1.01% | — |
| Plant transition | median | 8.293 ms | 8.277 ms | −0.016 ms | −0.19% | pass |
| Plant transition | p95 | 48.985 ms | 50.699 ms | +1.714 ms | +3.50% | pass |
| Plant transition | p99 | 62.322 ms | 65.851 ms | +3.528 ms | +5.66% | — |
| Plant transition | max | 68.740 ms | 80.870 ms | +12.130 ms | +17.65% | fail |

The plan's relative CPU/GPU p95 limit is no more than 5% above baseline; both
measured scenarios pass that relative gate. The repository's absolute 60 FPS
p95 budget fails in both trees. The transition maximum also regressed and must
be profiled before acceptance. No claim is made for scenarios not yet measured.

Geometry was matched exactly: the gallery submitted 3,016,088 world vertices;
the transition scene submitted 10,016 world vertices and 7,060,974 foliage-card
vertices in both trees.

## Generated asset size

- Manifest entries: 35 support-independent mature variants
- Total payload: 55,470,936 bytes (54,240 KiB on disk)
- Largest asset: 6,128,624 bytes
- Each asset contains five branch/organ LOD payloads and 8×3 impostor metadata.
- Support-dependent climbers are intentionally runtime-generated.

## Reproduction

```sh
python3 tools/perf.py run --scenario plant_gallery --repeat 3 \
  --output /tmp/adriatic-plant-after-gallery-focused.json
python3 tools/perf.py run --scenario plant_transition --repeat 3 \
  --output /tmp/adriatic-plant-after-transition-focused.json
```

Base artifacts:

- `/tmp/adriatic-plant-before-gallery-focused.json`
- `/tmp/adriatic-plant-before-transition-focused.json`

Updated artifacts:

- `/tmp/adriatic-plant-after-gallery-focused.json`
- `/tmp/adriatic-plant-after-transition-focused.json`
