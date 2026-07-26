package tests

import spray_audio "../packages/spray_audio"
import "core:math"
import "core:testing"

@(test)
spray_synth_is_deterministic_stereo_and_bounded :: proc(t: ^testing.T) {
    a := spray_audio.new_synth(42)
    b := spray_audio.new_synth(42)
    spray_audio.set_active(&a, true, .8)
    spray_audio.set_active(&b, true, .8)
    a_samples, b_samples: [spray_audio.SAMPLE_RATE]f32
    spray_audio.render(&a, a_samples[:])
    spray_audio.render(&b, b_samples[:])
    testing.expect(t, a_samples == b_samples)

    energy, stereo_difference := f64(0), f64(0)
    for frame in 0 ..< len(a_samples) / 2 {
        left, right := a_samples[frame * 2], a_samples[frame * 2 + 1]
        energy += f64(left * left + right * right)
        stereo_difference += math.abs(f64(left - right))
        testing.expect(t, abs(left) < 1 && abs(right) < 1)
    }
    testing.expect(t, energy > 1)
    testing.expect(t, stereo_difference > 1)
}

@(test)
spray_synth_has_click_free_attack_and_release :: proc(t: ^testing.T) {
    synth := spray_audio.new_synth(7)
    samples: [2]f32
    spray_audio.set_active(&synth, true)
    spray_audio.render(&synth, samples[:])
    testing.expect(t, synth.level > 0 && synth.level < 1)

    for _ in 0 ..< spray_audio.SAMPLE_RATE / 4 {
        spray_audio.render(&synth, samples[:])
    }
    testing.expect(t, synth.level > .99)
    before_release := synth.level
    spray_audio.set_active(&synth, false)
    spray_audio.render(&synth, samples[:])
    testing.expect(t, synth.level > 0 && synth.level < before_release)

    for _ in 0 ..< spray_audio.SAMPLE_RATE / 2 {
        spray_audio.render(&synth, samples[:])
    }
    testing.expect(t, synth.level < .001)
}
