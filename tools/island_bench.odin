package main

import islands "../packages/islands"
import "core:fmt"
import "core:time"

WARMUP_GENERATIONS :: 2
MEASURED_GENERATIONS :: 16

main :: proc() {
    for index in 0 ..< WARMUP_GENERATIONS {
        plan := islands.generate(u32(index))
        islands.destroy(&plan)
    }

    samples: [MEASURED_GENERATIONS]f64
    total: f64
    for index in 0 ..< MEASURED_GENERATIONS {
        started := time.tick_now()
        plan := islands.generate(u32(0x49534c45 + index))
        elapsed_ms := time.duration_seconds(time.tick_since(started)) * 1000
        islands.destroy(&plan)
        samples[index] = elapsed_ms
        total += elapsed_ms
    }

    // Insertion sort keeps this tiny benchmark independent of generic sorting
    // setup and makes the reported median deterministic.
    for index in 1 ..< len(samples) {
        value := samples[index]
        cursor := index
        for cursor > 0 && samples[cursor - 1] > value {
            samples[cursor] = samples[cursor - 1]
            cursor -= 1
        }
        samples[cursor] = value
    }
    median := (samples[len(samples) / 2 - 1] + samples[len(samples) / 2]) * .5
    fmt.printf(
        "island_generate count=%d mean_ms=%.3f median_ms=%.3f min_ms=%.3f max_ms=%.3f\n",
        len(samples),
        total / f64(len(samples)),
        median,
        samples[0],
        samples[len(samples) - 1],
    )
}
