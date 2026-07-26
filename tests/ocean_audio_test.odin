package tests

import ocean_audio "../packages/ocean_audio"
import "core:math"
import "core:testing"

@(test)
ocean_synth_is_deterministic_and_bounded :: proc(t: ^testing.T) {
    a := ocean_audio.new_synth(42)
    b := ocean_audio.new_synth(42)
    peak := f32(0)
    energy := f64(0)
    samples: [2]f32
    matching: [2]f32
    for _ in 0 ..< ocean_audio.SAMPLE_RATE * 3 {
        ocean_audio.render(&a, samples[:])
        ocean_audio.render(&b, matching[:])
        testing.expect(t, samples == matching)
        peak = max(peak, max(abs(samples[0]), abs(samples[1])))
        energy += f64(samples[0] * samples[0] + samples[1] * samples[1])
    }
    testing.expect(t, peak < 1)
    testing.expect(t, energy > 1)
}

@(test)
ocean_synth_produces_stereo_motion_without_dc_drift :: proc(t: ^testing.T) {
    synth := ocean_audio.new_synth(7)
    sum_left, sum_right, stereo_delta := f64(0), f64(0), f64(0)
    samples: [2]f32
    count := ocean_audio.SAMPLE_RATE * 8
    for _ in 0 ..< count {
        ocean_audio.render(&synth, samples[:])
        sum_left += f64(samples[0])
        sum_right += f64(samples[1])
        stereo_delta += math.abs(f64(samples[0] - samples[1]))
    }
    testing.expect(t, stereo_delta > 10)
    testing.expect(t, math.abs(sum_left / f64(count)) < .02)
    testing.expect(t, math.abs(sum_right / f64(count)) < .02)
}

@(test)
ocean_synth_fades_smoothly_when_muted :: proc(t: ^testing.T) {
    synth := ocean_audio.new_synth(19)
    samples: [2]f32
    ocean_audio.render(&synth, samples[:])
    ocean_audio.set_muted(&synth, true)
    ocean_audio.render(&synth, samples[:])
    testing.expect(t, synth.gain > 0 && synth.gain < 1)
    for _ in 0 ..< ocean_audio.SAMPLE_RATE {
        ocean_audio.render(&synth, samples[:])
    }
    testing.expect(t, synth.gain < .001)
}
